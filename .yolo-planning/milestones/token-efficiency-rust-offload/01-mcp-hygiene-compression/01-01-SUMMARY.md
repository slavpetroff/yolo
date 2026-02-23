---
phase: "01"
plan: "01"
title: "Add markdown minification and compression CLI commands"
status: complete
commits: 4
files_modified:
  - "yolo-mcp-server/src/commands/tier_context.rs"
  - "yolo-mcp-server/src/commands/compress_context.rs"
  - "yolo-mcp-server/src/commands/prune_completed.rs"
  - "yolo-mcp-server/src/commands/mod.rs"
  - "yolo-mcp-server/src/cli/router.rs"
---

# Summary: Add Markdown Minification and Compression CLI Commands

## What Was Built

- `minify_markdown()` function in tier_context.rs that collapses consecutive empty lines, removes bare `---` separators (preserving tier headers), and trims trailing whitespace
- Minification applied automatically in `build_tiered_context()` before returning the combined field
- `yolo compress-context` CLI command that finds `.context-*.md` files, applies minification, and reports per-file savings as JSON
- `yolo prune-completed` CLI command that removes PLAN.md files from completed phases (where every plan has a matching SUMMARY.md)
- 11 new unit tests across all 3 modules (62 total pass)

## Files Modified

- `yolo-mcp-server/src/commands/tier_context.rs` -- Added `pub fn minify_markdown()`, applied in `build_tiered_context()`, updated existing test, added 5 new tests
- `yolo-mcp-server/src/commands/compress_context.rs` -- New module: finds `.context-*.md` files, applies minification, reports savings JSON; 2 inline tests
- `yolo-mcp-server/src/commands/prune_completed.rs` -- New module: scans phase dirs for completion, prunes PLAN.md files; 4 inline tests
- `yolo-mcp-server/src/commands/mod.rs` -- Added `compress_context` and `prune_completed` module declarations
- `yolo-mcp-server/src/cli/router.rs` -- Added `"compress-context"` and `"prune-completed"` routes with imports

## Tasks Completed

### Task 1: Add minify_markdown to tier_context.rs
- Added `pub fn minify_markdown(text: &str) -> String` with line-by-line iteration
- Collapses 2+ consecutive empty lines to 1, removes bare `---` lines, trims trailing whitespace
- Applied in `build_tiered_context()` after `format!("{}\n{}\n{}", tier1, tier2, tier3)`
- Updated `test_combined_equals_tiers_joined` to `test_combined_is_minified_tiers_joined`
- Commit: `5509379`

### Task 2: Add compress-context CLI command
- Created `compress_context.rs` with `execute()` following standard CLI pattern
- Supports `--analyze-only` (report without modifying) and `--phase-dir <path>` flags
- JSON output: `{ok, cmd, analyze_only, files: [{file, original_bytes, original_tokens_est, minified_bytes, savings_bytes, savings_pct}], total_*}`
- Route: `"compress-context"` in router.rs near `"compile-context"`
- Commit: `b909c0b`

### Task 3: Add prune-completed CLI command
- Created `prune_completed.rs` with phase completion detection
- A phase is complete when every `*-PLAN.md` / `*.plan.jsonl` has a matching `*-SUMMARY.md`
- Removes plan files from completed phases, preserves summaries
- JSON output: `{ok, cmd, pruned_phases, files_removed, bytes_freed}`
- Route: `"prune-completed"` in router.rs
- Commit: `b6e46c3`

### Task 4: Add Rust unit tests
- 5 minify_markdown tests: collapses empty lines, removes bare separators, trims trailing whitespace, preserves code blocks, minified context smaller
- 2 compress_context tests: analyze-only mode, write mode
- 4 prune_completed tests: removes plans keeps summaries, skips incomplete, multi-plan phase, partial summaries skipped
- Commit: `dcdb559`

## Deviations

- **DEVN-05 (Pre-existing):** 2 test failures in `hooks::dispatcher::tests` (`test_dispatch_empty_json_object`, `test_session_start_non_compact_empty`). Not introduced by this plan. Not fixed per protocol.

## Must-Haves Verification

| Requirement | Status |
|-------------|--------|
| minify_markdown function reduces empty lines and separators | PASS |
| compress-context CLI reports per-tier token breakdown and applies minification | PASS |
| prune-completed CLI strips completed plan details from phase directories | PASS |
| All existing 20 tier_context tests + 13 MCP tests pass | PASS (62 total related tests pass) |
