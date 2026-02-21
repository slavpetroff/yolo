---
phase: 1
plan: 3
title: "Bats integration tests for token economics dashboard"
wave: 1
depends_on: []
must_haves:
  - "yolo report shows per-agent token spend (input/output/cache_read/cache_write) per phase"
  - "Cache hit rate percentage calculated from telemetry data"
  - "Dashboard renders in terminal with YOLO brand formatting"
---

# Plan 3: Bats Integration Tests for Token Economics

## Goal
Add comprehensive bats integration tests that exercise the `yolo report-tokens` CLI command end-to-end, verifying dashboard output, JSON mode, phase filtering, edge cases, and brand formatting.

## Tasks

### Task 1: Create `token-economics.bats` test file
**Files to modify:**
- `tests/token-economics.bats` (NEW)

**What to implement:**
Create a bats test file with these test cases:

1. **`report-tokens: exits 0 with no data and shows help message`** — Run `yolo report-tokens` with empty planning dir. Verify exit 0 and output contains guidance message.

2. **`report-tokens: shows per-agent token breakdown`** — Seed `.metrics/run-metrics.jsonl` with `agent_token_usage` events for dev (phase 1), architect (phase 1), and qa (phase 2). Run `yolo report-tokens`. Verify output contains "Per-Agent Token Spend" header and shows dev, architect, qa rows.

3. **`report-tokens: calculates cache hit rate`** — Seed with known token values (cache_read=7000, cache_write=1000, input=2000). Run `yolo report-tokens`. Verify output contains "Cache Hit Rate" and shows "70%" (7000/10000).

4. **`report-tokens: identifies waste agents`** — Seed with agent that has input=50000, output=2000 (25:1 ratio). Verify output contains "Waste" section and flags this agent.

5. **`report-tokens: computes ROI per task`** — Seed event-log with 5 `task_completed_confirmed` events and token data totaling 100000 tokens. Verify ROI shows "20000 tokens/task".

6. **`report-tokens: --json outputs valid JSON`** — Run with `--json` flag. Pipe to `jq -e '.'`. Verify exit 0 and JSON contains keys: `per_agent`, `cache_hit_rate`, `waste`, `roi`.

7. **`report-tokens: --phase=N filters correctly`** — Seed data for phase 1 and 2. Run with `--phase=1`. Verify output only shows phase 1 agents, no phase 2 data.

8. **`report-tokens: handles empty metrics gracefully`** — Create empty `.metrics/run-metrics.jsonl` and empty `.events/event-log.jsonl`. Verify exit 0, output shows zeros/defaults.

**Test expectations:**
- All 8 tests pass with exit code 0
- Tests use the standard `setup_temp_dir`/`teardown_temp_dir` pattern from `test_helper.bash`
- Tests reference `$YOLO_BIN` for the binary path

### Task 2: Add `agent_token_usage` event seeding helper to test_helper.bash
**Files to modify:**
- `tests/test_helper.bash`

**What to implement:**
- Add a `seed_agent_token_event()` helper function that takes (role, phase, input_tokens, output_tokens, cache_read, cache_write) and appends a properly formatted JSONL line to `.yolo-planning/.metrics/run-metrics.jsonl`
- Add a `seed_task_completed()` helper that takes (phase, task_id) and appends a `task_completed_confirmed` event to `.yolo-planning/.events/event-log.jsonl`
- These helpers reduce boilerplate across the 8 tests

**Test expectations:**
- Existing tests continue to pass (helpers are additive, no changes to existing functions)
- New tests in `token-economics.bats` use these helpers

### Task 3: Add Rust unit tests for edge cases
**Files to modify:**
- `yolo-mcp-server/src/commands/token_economics_report.rs` (append `#[cfg(test)] mod tests`)

**What to implement:**
- Test: zero division safety — when no tokens recorded, cache hit rate returns 0% not NaN/panic
- Test: missing fields — when JSONL event has partial data (e.g., no cache_write), defaults to 0
- Test: large dataset — seed 100+ events across 5 phases, verify aggregation completes without error and totals are correct
- Test: ROI with zero tasks — verify graceful output ("N/A" or "no tasks completed")

**Test expectations:**
- All edge case tests pass
- No panics on division by zero or missing fields
