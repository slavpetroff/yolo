---
phase: 2
plan: 4
title: "Suggest-next, bump-version, session-start, planning-git structured returns"
status: complete
commits: 4
deviations: []
---

# Plan 04 Summary

Retrofitted the remaining 4 CLI commands to return structured JSON envelopes with operation deltas, using the inline `serde_json::json!` macro pattern.

## What Was Built

1. **suggest-next structured return**: Replaced plain-text string concatenation with a `Vec<Value>` of `{command, reason}` objects. Returns JSON envelope with `delta.suggestions` array and context metadata (phase, effort, map staleness). Legacy text preserved in `delta.text` for backward compat.

2. **bump-version structured return**: Both bump and verify modes now return JSON. Bump mode includes `delta.old_version`, `delta.new_version`, `delta.files_updated[]` with per-file old/new tracking. Verify mode returns `delta.versions[]` with per-file status and `delta.all_match` boolean.

3. **planning-git structured return**: All 3 subcommands (sync-ignore, commit-boundary, push-after-phase) return JSON envelopes. commit-boundary captures `commit_hash` via `git rev-parse --short HEAD` and reports `pushed` status. No-op cases return structured reasons.

4. **session-start structured return**: Added `structuredResult` field alongside existing `hookSpecificOutput`. Tracks all 15 steps as a `steps_completed` array, collects `warnings`, and surfaces `next_action`, `milestone`, `phase`, `config` in the structured delta. Refactored `build_context` to return `ContextResult` struct.

5. **Tests updated**: All 4 command test modules updated to parse JSON output and validate envelope fields (`ok`, `cmd`, `delta`, `elapsed_ms`).

## Files Modified

- `yolo-mcp-server/src/commands/suggest_next.rs` — JSON envelope with suggestions array, updated tests
- `yolo-mcp-server/src/commands/bump_version.rs` — JSON envelope for bump and verify modes, updated tests
- `yolo-mcp-server/src/commands/planning_git.rs` — JSON envelope for all 3 subcommands, updated tests
- `yolo-mcp-server/src/commands/session_start.rs` — structuredResult alongside hookSpecificOutput, ContextResult struct, updated tests

## Commits

- `b6c7c5b` feat(suggest-next): return structured JSON with suggestions array
- `2e80a81` feat(bump-version): return structured JSON for bump and verify modes
- `0e91320` feat(planning-git): return structured JSON for all subcommands
- `edf0b9b` feat(session-start): add structuredResult alongside hookSpecificOutput

## Test Results

945 tests passed, 0 failures. All existing assertions updated to parse JSON and validate envelope fields.
