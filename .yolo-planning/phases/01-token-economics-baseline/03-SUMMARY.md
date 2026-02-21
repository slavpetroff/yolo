---
phase: 1
plan: 3
title: "Bats integration tests for token economics dashboard"
status: complete
---

# Plan 3 Summary: Bats Integration Tests for Token Economics

## What Was Built

### Task 1: `tests/token-economics.bats` (8 tests)
- `report-tokens: exits 0 with no data and shows help message`
- `report-tokens: shows per-agent token breakdown` (seeds dev, architect, qa across 2 phases)
- `report-tokens: calculates cache hit rate` (7000/10000 = 70%)
- `report-tokens: identifies waste agents` (25:1 input/output ratio)
- `report-tokens: computes ROI per task` (100000 tokens / 5 tasks = 20000)
- `report-tokens: --json outputs valid JSON` (validates per_agent, cache_hit_rate, waste, roi keys)
- `report-tokens: --phase=N filters correctly` (phase 1 only, no phase 2 data)
- `report-tokens: handles empty metrics gracefully` (empty JSONL files)

### Task 2: Test helper functions in `tests/test_helper.bash`
- `seed_agent_token_event()` — seeds `agent_token_usage` events with integer JSON values
- `seed_task_completed()` — seeds `task_completed_confirmed` events

### Task 3: Rust edge case tests in `token_economics_report.rs` (4 tests)
- `test_zero_division_safety_cache_hit_rate` — empty stats and all-zero tokens yield 0%
- `test_missing_fields_default_to_zero` — partial JSONL data defaults missing fields to 0
- `test_large_dataset_aggregation` — 100 events across 5 phases, verifies correct totals
- `test_roi_with_zero_tasks` — zero completed tasks returns 0 tokens/task without panic

## Files Modified
- `tests/token-economics.bats` (NEW) — 8 bats integration tests for `yolo report-tokens`
- `tests/test_helper.bash` — added `seed_agent_token_event()` and `seed_task_completed()` helpers
- `yolo-mcp-server/src/commands/token_economics_report.rs` — added 4 edge case unit tests

## Deviations
- Fixed `seed_agent_token_event` to emit integer JSON values (not string-quoted) for compatibility with the Rust parser's `as_i64()` method.
- Bats tests use flexible output matching (multiple possible string patterns) since Plans 01/02 were built in parallel and exact output wording may vary.

## Verification
- All 10 Rust tests pass (`cargo test --bin yolo -- token_economics_report`: 10 passed, 0 failed)
- Bats test file parses correctly (`bats --count`: 8 tests detected)
- 3 commits, one per task
