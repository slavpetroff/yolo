# Phase 1: Version Unification — Research

## Findings

### bump_version.rs (lines 93-108)
- `VersionFiles` struct: `version_file: &'static str` + `json_files: Vec<(&'static str, &'static str)>`
- Manages 4 files: VERSION, plugin.json, .claude-plugin/marketplace.json, root marketplace.json
- Missing: Cargo.toml (TOML, not JSON)
- `execute()` parses `--verify` and `--offline` flags only

### CLI Router (router.rs)
- bump-version already registered as `Command::BumpVersion`
- Args passed as `&[String]` slice — downstream checks with `.iter().any()`
- No router changes needed for new flags

### Archive Skill (archive.md lines 55-73)
- Bash math for --major/--minor: `cut -d. -f1`, `$((MAJOR + 1)).0.0`
- Falls back to `yolo bump-version` for patch only
- git add includes `.claude-plugin/marketplace.json` (must update if deleted)

### Cargo.toml
- Version at 2.7.1 (drifted from 2.9.5)
- No `toml_edit` dependency currently
- Edition 2024, standard deps (serde, tokio, regex, reqwest)

### toml_edit Pattern
```rust
use toml_edit::DocumentMut;
let mut doc = content.parse::<DocumentMut>()?;
doc["package"]["version"] = toml_edit::value(version);
fs::write(path, doc.to_string())?;
```

## Relevant Patterns
- JSON pointer navigation: `serde_json::Value::pointer("/path/to/field")`
- Flag parsing: `args.iter().any(|a| a == "--flag")`
- Test setup: `tempfile::TempDir` with `fs::write()` for each test file
- Binary path: `env::var("HOME").map(|h| format!("{}/.cargo/bin/yolo", h))`

## Risks
1. Archive.md git-adds deleted `.claude-plugin/marketplace.json` — must update
2. Cargo.toml with comments could be mangled — toml_edit preserves formatting
3. Test setup_test_env() lacks Cargo.toml — must add
4. 55 files reference `$HOME/.cargo/bin/yolo` — Phase 3 scope, not Phase 1

## Recommendations
- Add `toml_edit = "0.22"` to dependencies
- Create `read_toml_version()` + `write_toml_version()` helpers
- Extend VersionFiles with TOML file tracking (separate vec or enum)
- Add `--major`/`--minor` flags to execute() with `increment_major()`/`increment_minor()`
- Update archive.md to delegate all bump logic to CLI
- Delete `.claude-plugin/marketplace.json`, update bump_version.rs
- Force sync Cargo.toml to 2.9.5 as part of initial commit
