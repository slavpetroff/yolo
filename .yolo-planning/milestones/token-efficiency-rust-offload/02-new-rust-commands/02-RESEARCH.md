# Research: Phase 2 — New Rust Commands for Deterministic Offload

## Findings

### Rust CLI Architecture
- **Command signature:** `pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String>`
- **Router registration:** 4 edits per new command — enum variant in `router.rs`, `from_arg()` match arm, `name()` match arm, `run_cli()` dispatch
- **JSON output pattern:** `serde_json::json!({"ok": true, "cmd": "name", "delta": {...}})` with exit code 0 for success
- **File I/O:** `atomic_io::atomic_write_with_checksum()` for safe writes, `std::fs::read_to_string()` for reads
- **Git ops:** `std::process::Command::new("git").args([...]).output()` pattern
- **Existing frontmatter parser:** Hand-rolled in `state_updater.rs:392-424` — splits on `---`, parses `key: value` lines. Reusable for `parse-frontmatter`

### Source File Layout (from codebase mapping)
- `yolo-mcp-server/src/router.rs` — Command enum + dispatch (all 69 commands registered here)
- `yolo-mcp-server/src/commands/` — Individual command modules
- `yolo-mcp-server/src/state_updater.rs` — State management + frontmatter parsing
- `yolo-mcp-server/src/atomic_io.rs` — Atomic file write utilities

### Audit Gap Analysis (from 01-AUDIT.md)
14 new commands needed, 5 enhancements needed. Phase 2 scope per ROADMAP.md: 4 new commands.

## Relevant Patterns

### Command Module Pattern
Each command lives in `yolo-mcp-server/src/commands/{name}.rs`:
```rust
pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    // Parse args
    // Do work
    // Return JSON + exit code
    Ok((serde_json::json!({"ok": true, "cmd": "name", ...}).to_string(), 0))
}
```

### Router Registration Pattern
```rust
// In router.rs enum:
CommandName,

// In from_arg():
"command-name" => Some(Self::CommandName),

// In name():
Self::CommandName => "command-name",

// In run_cli():
Command::CommandName => commands::command_name::execute(args, cwd),
```

### Frontmatter Reuse
`state_updater.rs` already has `parse_yaml_frontmatter()` logic (lines 392-424). The new `parse-frontmatter` command can call this directly or extract it into a shared utility.

## Risks

1. **Router.rs merge conflicts:** All 4 new commands modify `router.rs`. Must use non-overlapping insertion points or batch the enum/match additions.
2. **Frontmatter edge cases:** Existing parser is minimal (key: value only). PLAN.md frontmatter has arrays (`must_haves`, `depends_on`) and nested values. May need to extend parser or use a proper YAML crate.
3. **Plugin root path resolution:** Must replicate version-sort fallback logic (`sort -V` behavior) in Rust. The `semver` crate or manual version comparison needed.
4. **Git command subprocess errors:** `git-state` wraps multiple git commands; any can fail (not a repo, detached HEAD, etc.). Need robust error handling.

## Recommendations

### Priority Order (by call-site impact)
1. **`parse-frontmatter`** (S) — Enables all MD file metadata extraction without LLM. Reuses existing parser code. Foundation for other commands.
2. **`plugin-root`** (S) — 25+ call sites. Eliminates most-repeated deterministic operation. Pure path resolution.
3. **`config-read`** (S) — 15+ jq calls replaced. Simple JSON key extraction with default. Eliminates jq dependency.
4. **`compile-progress`** (M) — Status/resume dashboards. Directory walking + file counting. Medium complexity.
5. **`git-state`** (M) — Unifies 5+ distinct git read patterns. Subprocess wrapping. Medium complexity.

### Suggested Plan Split (max 5 tasks per plan, 2 plans for parallel execution)
- **Plan 02-01:** `parse-frontmatter` + `plugin-root` + `config-read` (3 small commands, disjoint from Plan 2)
- **Plan 02-02:** `compile-progress` + `git-state` (2 medium commands, both new files + router registration)

Both plans share `router.rs` edits but at different enum positions — wave 1 safe if insertion points are specified.
