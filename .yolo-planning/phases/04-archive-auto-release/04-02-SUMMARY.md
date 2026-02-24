---
phase: "04"
plan: "02"
title: "gh release create step in release-suite"
status: "complete"
completed: "2026-02-24"
tasks_completed: 3
tasks_total: 3
commit_hashes: ["c0bacf08"]
deviations: []
---

# Summary: gh release create step in release-suite

## What Was Built

Added Step 6 (gh-release) to release-suite that creates a GitHub Release via `gh release create` after successful push. Uses changelog body from extract-changelog as release notes. Gracefully handles: missing gh CLI (warn), --no-push (skip), --no-release (skip), dry-run mode. Added --no-release flag to release-suite.

## Files Modified

- `yolo-mcp-server/src/commands/release_suite.rs` — Added Step 6, --no-release flag, extract_changelog import, 1 new test, updated existing tests for 6-step expectations

## Deviations

None.
