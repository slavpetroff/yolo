---
phase: "02"
plan: "03"
title: "release-suite facade command"
status: "complete"
completed: "2026-02-24"
tasks_completed: 4
tasks_total: 4
commit_hashes: ["e11cea64"]
deviations: []
---

# Summary: release-suite facade command

## What Was Built

`yolo release-suite` orchestrating bump-version, git add, commit, tag, push with --dry-run, --no-push, --major/--minor flags. 9 unit tests.

## Files Modified

- `yolo-mcp-server/src/commands/release_suite.rs` — New module (619 lines, 9 tests)

## Deviations

None.
