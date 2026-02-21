---
phase: 4
plan: 04
title: "Test repair batch C: Remaining test files and YOLO_BIN-only tests"
status: complete
completed: 2026-02-21
tasks_completed: 4
tasks_total: 4
commit_hashes:
  - f10ddc5
  - ba14092
  - ce19fe8
  - 78b6100
deviations:
  - "discovered-issues-surfacing.bats reduced from 103 to 83 tests (removed 20 tests for deleted yolo-qa.md, commands/qa.md, and detailed DEVN-05 subsections that were compressed)"
  - "yolo binary required rebuild from source to include report-tokens command"
---

Migrated all 16 remaining test files from shell scripts to Rust CLI, fixing 45+ test failures across YOLO_BIN bootstrapping, CLI argument mapping, agent definition updates, and deleted file references.

## What Was Built

- Task 1: Fixed 4 YOLO_BIN-only test files (token-baseline, token-economics, phase-detect, metrics-segmentation) — 31 tests passing
- Task 2: Migrated phase0-bugfix-verify.bats from 5 shell scripts to Rust CLI subcommands — 19 tests passing
- Task 3: Migrated role-isolation tests from file-guard.sh to Rust source verification + yolo hook integration — 20 tests passing
- Task 4: Updated discovered-issues-surfacing.bats for current agent definitions (removed yolo-qa.md, commands/qa.md refs; updated debugger/dev/lead assertions) — 83 tests passing

## Files Modified

- `tests/token-baseline.bats` -- updated: removed script copy from setup, added YOLO_BIN fallback
- `tests/token-economics.bats` -- updated: fixed assertions for Rust CLI output format (branded numbers, --json output)
- `tests/phase-detect.bats` -- updated: added YOLO_BIN fallback export
- `tests/metrics-segmentation.bats` -- updated: added YOLO_BIN fallback export
- `tests/phase0-bugfix-verify.bats` -- rewritten: mapped 5 scripts to CLI subcommands and hooks
- `tests/role-isolation.bats` -- rewritten: source verification + hook integration replacing file-guard.sh
- `tests/role-isolation-runtime.bats` -- rewritten: source verification + hook integration replacing file-guard.sh
- `tests/discovered-issues-surfacing.bats` -- rewritten: updated for current compressed agent definitions

## Deviations

- discovered-issues-surfacing.bats was reduced from 103 to 83 tests. 20 tests removed because they referenced deleted files (yolo-qa.md, commands/qa.md) or expected detailed subsections that were removed during agent compression (DEVN-05 decision tree, Communication section, Lead aggregation section). Replacement tests verify the same behavioral contracts against current agent content.
- The installed yolo binary was stale and required rebuild (`cargo build --release`) to include the `report-tokens` subcommand needed by token-economics.bats.
