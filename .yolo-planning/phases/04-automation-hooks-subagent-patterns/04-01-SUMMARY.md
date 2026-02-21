---
phase: 4
plan: 01
title: Test infrastructure and helper modernization
status: done
commits: [48c6370, 08a1db6, b4ceef8]
---

# Summary: 04-01 Test Infrastructure and Helper Modernization

## What Was Built

Modernized test infrastructure to use the Rust yolo CLI instead of removed shell scripts:
- Task 1: Added `YOLO_BIN` export and `yolo_cmd()` helper to shared test helper
- Task 2: Migrated 16 agent-shutdown-integration tests from `$SCRIPTS_DIR/*.sh` to `yolo hook` CLI
- Task 3: Migrated 43 hooks-isolation-lifecycle tests from 9 shell scripts to yolo CLI equivalents

Key behavioral adaptations for Rust CLI differences:
- PostToolUse is advisory-only (always exit 0) -- old task-verify.sh had circuit breaker with exit 2
- Commit format validation removed -- PreToolUse now runs security_filter (fail-closed on missing file_path)
- detect-stack resolves config from project_dir arg, not CWD -- tests copy stack-mappings.json into temp dirs
- `normalize_agent_role` strips `yolo:` prefix once (`yolo:yolo-scout` -> `yolo-scout`, not `scout`)

## Files Modified

- `tests/test_helper.bash` -- added YOLO_BIN export and yolo_cmd() helper (commit `48c6370`)
- `tests/agent-shutdown-integration.bats` -- migrated 16 tests to yolo hook CLI (commit `08a1db6`)
- `tests/hooks-isolation-lifecycle.bats` -- migrated 43 tests to yolo hook CLI (commit `b4ceef8`)

## Verification

All 3 test files pass with 0 failures:
- `tests/test_helper.bash` -- helper loaded by all test files
- `tests/agent-shutdown-integration.bats` -- 16/16 pass
- `tests/hooks-isolation-lifecycle.bats` -- 43/43 pass
