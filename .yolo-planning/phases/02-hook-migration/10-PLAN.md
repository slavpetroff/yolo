---
phase: 2
plan: 10
title: "Migrate cache and delta scripts to native Rust (cache-context, cache-nuke, delta-files, map-staleness)"
wave: 2
depends_on: [1]
must_haves:
  - "cache_context computes deterministic cache key from phase, role, plan, config flags, git diff, codebase mapping"
  - "cache_nuke wipes plugin cache and temp caches with optional --keep-latest"
  - "delta_files outputs changed files from git diff or SUMMARY.md extraction"
  - "map_staleness checks codebase map freshness by comparing META.md git_hash against HEAD"
  - "SHA-256 via sha2 crate, git via Command::new(git) — no Command::new(bash)"
---

## Task 1: Implement cache_context module

**Files:** `yolo-mcp-server/src/commands/cache_context.rs` (new)

**Acceptance:** `cache_context::execute(phase, role, config_path, plan_path) -> Result<(String, i32), String>`. Build hash input from deterministic sources: phase, role, plan content SHA-256 (sha2 crate), V3 config flags, git diff filenames (`Command::new("git").args(["diff", "--name-only", "HEAD"])`), codebase mapping fingerprint (for debugger/dev/qa/lead/architect roles), rolling summary fingerprint. Compute final SHA-256, truncate to 16 chars. Check cache at `.yolo-planning/.cache/context/{hash}.md`. Output: `hit {hash} {path}` or `miss {hash}`. Exit 0 always. Also expose CLI entry point.

## Task 2: Implement cache_nuke module

**Files:** `yolo-mcp-server/src/commands/cache_nuke.rs` (new)

**Acceptance:** `cache_nuke::execute(keep_latest: bool) -> Result<(String, i32), String>`. Resolve CLAUDE_DIR via `utils::resolve_claude_dir()`. Plugin cache at `{CLAUDE_DIR}/plugins/cache/yolo-marketplace/yolo/`. If `keep_latest`: list version dirs, sort by version, remove all but latest. Otherwise remove entire dir. Clean temp caches: remove `/tmp/yolo-*-{uid}-*` files using `std::fs::read_dir("/tmp/")` with prefix filter. Output JSON summary: `{wiped: {plugin_cache: bool, temp_caches: bool, versions_removed: N}}`. Also expose CLI entry point.

## Task 3: Implement delta_files module

**Files:** `yolo-mcp-server/src/commands/delta_files.rs` (new)

**Acceptance:** `delta_files::execute(phase_dir) -> Result<(String, i32), String>`. Strategy 1 (git available): `git diff --name-only HEAD` + `git diff --name-only --cached`, deduplicate and sort. If empty, try since last tag: `git describe --tags --abbrev=0` then `git diff --name-only {tag}..HEAD`. Fallback: last 5 commits. Strategy 2 (no git): extract from `*-SUMMARY.md` files in phase_dir, parse `## Files Modified` sections. Output one file per line. Graceful fallback to empty on any error. Also expose CLI entry point.

## Task 4: Implement map_staleness module (SessionStart hook + CLI)

**Files:** `yolo-mcp-server/src/hooks/map_staleness.rs` (new)

**Acceptance:** `map_staleness::execute(planning_dir) -> Result<(String, i32), String>`. Skip if compaction marker is fresh (<60s). Read `.yolo-planning/codebase/META.md`, parse `git_hash:`, `file_count:`, `mapped_at:` lines. Verify stored hash exists via `Command::new("git").args(["cat-file", "-e", hash])`. Count changed files: `git diff --name-only {hash}..HEAD | wc -l`. Calculate staleness percentage. If >30% -> "stale", else "fresh". In hook mode (detected by context): output `hookSpecificOutput` JSON with staleness advisory. In CLI mode: output key-value pairs. Register as SessionStart handler (non-compact) in dispatcher. Also expose CLI entry point.

## Task 5: Register CLI commands, wire map_staleness hook, and add tests

**Files:** `yolo-mcp-server/src/commands/mod.rs`, `yolo-mcp-server/src/cli/router.rs`, `yolo-mcp-server/src/hooks/dispatcher.rs`, `yolo-mcp-server/src/hooks/mod.rs`, `yolo-mcp-server/src/commands/cache_context.rs` (append tests), `yolo-mcp-server/src/commands/cache_nuke.rs` (append tests)

**Acceptance:** Register `yolo cache-context`, `yolo cache-nuke`, `yolo delta-files`, `yolo map-staleness` in router. Wire `map_staleness` as SessionStart (non-compact) handler in dispatcher. Tests cover: cache key determinism (same inputs = same hash), cache hit/miss detection, delta files from git diff, delta files from SUMMARY.md fallback, staleness calculation, temp cache cleanup. `cargo test` passes.
