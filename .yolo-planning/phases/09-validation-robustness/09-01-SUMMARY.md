---
phase: "09"
plan: "01"
title: "Upgrade validate_summary and add validate-plan command"
status: complete
completed: 2026-02-22
tasks_completed: 4
tasks_total: 4
commit_hashes:
  - 9308c84
  - 32d2d4d
  - 3108949
  - 7c0c5be
deviations: []
---

## What Was Built

- Upgraded validate_summary.rs to extract and validate YAML frontmatter fields (phase, plan, status, tasks_completed, tasks_total, commit_hashes) with status value validation and Deviations section check
- New `yolo validate-plan` CLI command that validates depends_on references against existing plan files and cross_phase_deps against completed SUMMARY.md files, returning structured JSON
- Replaced LLM-based cross-phase dependency check in execute-protocol SKILL.md with Rust CLI command call
- Added 6 new unit tests (3 for validate_summary frontmatter, 3 for validate_plan depends_on)

## Files Modified

- `yolo-mcp-server/src/hooks/validate_summary.rs` -- feat: added frontmatter extraction, field validation, status value check, Deviations section check, and 3 new tests
- `yolo-mcp-server/src/commands/validate_plan.rs` -- feat: new command with depends_on and cross-phase dependency validation, 13 unit tests
- `yolo-mcp-server/src/commands/mod.rs` -- feat: registered validate_plan module
- `yolo-mcp-server/src/cli/router.rs` -- feat: wired validate-plan route
- `skills/execute-protocol/SKILL.md` -- feat: replaced LLM cross-phase dep instruction with yolo validate-plan CLI call

## Deviations

None
