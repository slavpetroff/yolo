---
phase: 1
plan: 02
title: "Migrate planning-git to Rust CLI"
status: complete
---

## What Was Built

Rust CLI subcommand `yolo planning-git` with three subcommands that replicate `scripts/planning-git.sh` behavior: `sync-ignore` manages root and transient .gitignore entries based on planning_tracking config mode; `commit-boundary` stages and commits planning artifacts with optional auto-push; `push-after-phase` pushes when auto_push=after_phase. All subcommands handle non-git repos gracefully (exit 0). 15 unit tests.

## Tasks

| # | Task | Commit |
|---|------|--------|
| 1 | Implement planning-git with sync-ignore subcommand | `70c3a11` |
| 2 | Add commit-boundary subcommand | `875929c` |
| 3 | Add push-after-phase subcommand | `5bc69f0` |
| 4 | Register in CLI router + mod.rs | `05b2d8b` (auto-registered by linter during plan-01 router commit) |

## Files Modified

- `yolo-mcp-server/src/commands/planning_git.rs` (new, 395 lines)
- `yolo-mcp-server/src/commands/mod.rs` (added `pub mod planning_git;`)
- `yolo-mcp-server/src/cli/router.rs` (added `planning-git` match arm + import)

## Test Coverage

15 unit tests covering:
- Config parsing (defaults, explicit values)
- sync-ignore: ignore mode adds line, commit mode removes line + creates transient, manual is no-op, non-git returns Ok
- commit-boundary: commit mode stages+commits, non-commit is no-op, no staged changes is no-op, missing action errors, non-git returns Ok
- push-after-phase: never mode is no-op, non-git returns Ok
- Routing: missing subcommand errors, unknown subcommand errors

## Deviations

- Task 4 registration was auto-applied by the linter/formatter when plan-01 dev committed `05b2d8b`. No separate commit needed since mod.rs and router.rs already contained the planning_git entries.
