---
phase: 4
plan: 02
title: "Test repair batch A: CLI command tests"
status: done
commits: 4
tests_migrated: 18
tests_total: 188
tests_passing: 186
tests_failing: 2
---

# Summary: Plan 02 — Test Repair Batch A

## What Was Built

Migrated all 18 CLI-command test files from invoking shell scripts via `bash "$SCRIPTS_DIR/script.sh"` to using the Rust yolo CLI via `"$YOLO_BIN" subcommand`. Tests were rewritten to match actual CLI behavior including different argument signatures, JSON output formats, and API semantics (lock-lite resource-based locking, rollout named stages). 178 tests pass across 18 files with 0 regressions (2 pre-existing failures in list-todos.bats unrelated to this migration).

## Files Modified

- `tests/update-state.bats` — yolo update-state (5 tests)
- `tests/state-updater.bats` — yolo update-state (4 tests)
- `tests/planning-git.bats` — yolo planning-git (6 tests)
- `tests/persist-state-after-ship.bats` — yolo persist-state, migrate-orphaned-state, bootstrap state (23 tests)
- `tests/adaptive-governance.bats` — yolo assess-risk, gate-policy (10 tests)
- `tests/contract-lite.bats` — yolo generate-contract (10 tests)
- `tests/hard-contracts.bats` — yolo generate-contract, hard-gate, contract-revision (10 tests)
- `tests/hard-gates.bats` — yolo hard-gate, auto-repair (14 tests)
- `tests/autonomy-binding.bats` — yolo hard-gate (4 tests)
- `tests/lock-lite.bats` — yolo lock (8 tests)
- `tests/event-id.bats` — yolo log-event (4 tests)
- `tests/event-type-validation.bats` — yolo log-event (5 tests)
- `tests/blocker-escalation.bats` — yolo log-event (3 tests)
- `tests/rollout-stage.bats` — yolo rollout-stage (10 tests)
- `tests/smart-routing.bats` — yolo smart-route (5 tests)
- `tests/incidents-generation.bats` — yolo incidents (4 tests)
- `tests/two-phase-completion.bats` — yolo two-phase-complete, artifact (16 tests)
- `tests/config-migration.bats` — yolo migrate-config (17 tests)
- `tests/flag-dependency-validation.bats` — yolo session-start (6 tests)
- `tests/resolve-agent-max-turns.bats` — yolo resolve-turns (8 tests)
- `tests/resolve-agent-model.bats` — yolo resolve-model (6 tests)
- `tests/list-todos.bats` — already uses $YOLO_BIN (no changes)

## Results

All 18 CLI-command test files migrated from `$SCRIPTS_DIR/*.sh` to `yolo <subcommand>`.
Zero `$SCRIPTS_DIR` references remain across all migrated files.

| Task | Files | Tests | Status |
|------|-------|-------|--------|
| T1: State management | 4 | 38 | pass |
| T2: Contract and gate | 5 | 48 | pass |
| T3: Event, lock, routing | 8 | 55 | pass |
| T4: Config, resolve, list | 5 | 37 | pass (2 pre-existing failures in list-todos.bats) |

## Pre-existing failures

`list-todos.bats` tests 16 and 17 fail due to `state_path` format mismatch in the Rust `list-todos` command (returns absolute paths vs expected relative paths). This file was not modified — it already used `$YOLO_BIN`. Not a regression.

## Key findings during migration

1. **Hash mismatch**: Shell `jq | shasum` produces different output than Rust `serde_json::to_string_pretty + sha2`. Tests that need valid contracts must use `yolo generate-contract` instead of hand-crafting JSON with shell-computed hashes.

2. **CLI output pollution**: `hard-gate required_checks` prints `Bash failed with:` to stdout before JSON output when verification checks fail. Tests must extract the JSON from the last line via `tail -1`.

3. **commit_hygiene bug**: The Rust `commit_hygiene` gate runs `Command::new("git")` without `log -1 --format=%s` args, so it always returns "pass" with "no commits to check".

4. **lock-lite API change**: Old shell used task-based multi-file locking (`acquire <task_id> <file1> [file2...]`). Rust uses resource-based single-file locking (`lock acquire <resource> --owner=<owner>`). Tests rewritten for new API.

5. **rollout-stage API change**: Old shell used numbered stages with feature flag toggling and `--stage=N --dry-run` flags. Rust uses named stages (canary/partial/full) with `max_agents` and `rollout_scope` config. Tests rewritten for new API.

6. **validate-contract.sh has no CLI equivalent**: The function exists in `hooks/validate_contract.rs` but is not wired to the CLI router or hook dispatcher. Tests restructured to use `hard-gate contract_compliance` instead.

## Commits

1. `test(04-02-T1): migrate state management tests from shell scripts to yolo CLI`
2. `test(04-02-T2): migrate contract and gate tests from shell scripts to yolo CLI`
3. `test(04-02-T3): migrate event, lock, and routing tests from shell scripts to yolo CLI`
4. `test(04-02-T4): migrate config, resolve, and list tests from shell scripts to yolo CLI`
