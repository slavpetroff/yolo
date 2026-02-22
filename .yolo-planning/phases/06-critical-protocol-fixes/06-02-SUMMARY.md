---
phase: "06"
plan: "02"
title: "Fix README and STACK.md stale claims"
status: complete
completed: 2026-02-22
tasks_completed: 4
tasks_total: 4
commit_hashes:
  - b935150
deviations:
  - "Test count (1,610) confirmed accurate -- no change needed (plan estimated 1,624)"
---

Corrected stale agent count, hook count, agent table, and STACK.md version in README.md.

## What Was Built

- Fixed agent count from 7 to 6 across all README references (removed non-existent Scout/QA rows, added Reviewer)
- Updated hook claims from "21 hooks" to "19 hook handlers" across 3 occurrences
- Fixed agent permission ratios ("4 of 7" to "3 of 6") and corrected Debugger mode (plan, not acceptEdits)
- Updated STACK.md version from 2.3.0 to 2.5.0

## Files Modified

- `README.md` -- fix: agent table, hook counts, permission ratios, architecture diagram, project structure
- `.yolo-planning/codebase/STACK.md` -- fix: version 2.3.0 to 2.5.0

## Deviations

Test count (1,610) was verified as accurate (687 bats + 923 Rust = 1,610). The plan estimated 1,624 but the actual count confirmed the existing claim, so no change was made.
