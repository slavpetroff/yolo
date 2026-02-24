---
phase: "04"
plan: "01"
title: "extract-changelog CLI command"
status: "complete"
completed: "2026-02-24"
tasks_completed: 4
tasks_total: 4
commit_hashes: ["af74d0d8"]
deviations: []
---

# Summary: extract-changelog CLI command

## What Was Built

New `yolo extract-changelog` command that extracts the latest version section from CHANGELOG.md. Supports `## v{VERSION} (DATE)` and `## [{VERSION}] - DATE` formats. Returns structured JSON with version, date, body, and found fields. Gracefully handles missing file or no version sections.

## Files Modified

- `yolo-mcp-server/src/commands/extract_changelog.rs` — New module (6 tests)
- `yolo-mcp-server/src/commands/mod.rs` — Added module declaration
- `yolo-mcp-server/src/cli/router.rs` — Wired enum, from_str, name, dispatch, all_names

## Deviations

None.
