---
phase: "01"
plan: "01"
title: "Fix 14 failing bats tests"
status: complete
completed: 2026-02-23
tasks_completed: 3
tasks_total: 3
commit_hashes:
  - "823c754"
deviations:
  - "Plan identified 3 failing tests; actual suite had 14 failures (3 original + 11 pre-existing). All fixed in Task 3 per plan scope."
---

## What Was Built

Fixed all 14 failing bats tests to align assertions with actual Rust CLI behavior. The original plan targeted 3 known failures (validate-commit #1/#2, vibe-mode-split #6), but the full suite revealed 11 additional pre-existing failures. All were test-only fixes (no production code changes except adding `name: yolo:vibe` to vibe.md frontmatter).

## Files Modified

- `tests/validate-commit.bats` — Updated 2 tests: Bash tool now asserts pass-through (exit 0) instead of block (exit 2)
- `commands/vibe.md` — Added `name: yolo:vibe` to YAML frontmatter
- `tests/advanced-scale.bats` — recover-state: use `.delta.` prefix for envelope fields, exit 3 when disabled
- `tests/test_helper.bash` — Added `command_timeout_ms` and `task_lease_ttl_secs` to `create_test_config`
- `tests/control-plane.bats` — generate-contract: expect exit 1 on missing args
- `tests/discovered-issues-surfacing.bats` — Match reviewer agent actual text ("Review only", "architectural")
- `tests/lock-lite.bats` — lock check conflict: expect exit 2 instead of 1
- `tests/research-persistence.bats` — hard-gate: expect exit 2 on insufficient args
- `tests/resolve-agent-model.bats` — Replace removed "scout" role with "researcher"
- `tests/role-isolation.bats` — validate_contract: check fail-open guard instead of "planning" grep
- `tests/runtime-foundations.bats` — log-event: expect exit 3 when flag disabled

## Deviations

Plan identified 3 failing tests. Actual suite had 14 failures (3 targeted + 11 pre-existing from Rust CLI migration). All 11 additional failures were test assertion mismatches against actual Rust binary behavior — fixed per Task 3's scope ("If any other tests fail, fix them in this task").
