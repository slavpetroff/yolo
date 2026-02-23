---
phase: 1
plan: 02
status: complete
---
## Summary
Fixed three bugs in hard_gate.rs: the protected_file gate was calling bare `git` instead of `git diff --name-only --cached`, the commit_hygiene gate was calling bare `git` instead of `git log -1 --pretty=%s`, and insufficient arguments returned exit code 0 instead of 2. Updated corresponding test assertion.

## What Was Built
- Fixed `protected_file` gate to call `git diff --name-only --cached` for detecting staged forbidden files
- Fixed `commit_hygiene` gate to call `git log -1 --pretty=%s` for extracting the last commit subject
- Changed insufficient-args exit code from 0 to 2 (hard failure) to match error semantics
- Updated `test_execute_gate_missing_args` to assert exit code 2

## Files Modified
- `yolo-mcp-server/src/commands/hard_gate.rs` — 3 bug fixes + 1 test update

## Tasks
- Task 1: Fix protected_file gate broken git command — complete
- Task 2: Fix commit_hygiene gate broken git command — complete
- Task 3: Fix insufficient-args exit code from 0 to 2 — complete
- Task 4: Add/update unit tests for fixed gates — complete

## Commits
- ad791f6: fix(hard-gate): fix broken git commands and exit codes

## Deviations
None
