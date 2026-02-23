---
phase: "03"
plan: "01"
title: "phase-detect --suggest-route and resolve-model --with-cost --all flags"
status: complete
tasks_completed: 5
tasks_total: 5
commits: 5
commit_hashes:
  - "31098b6"
  - "d9312f9"
  - "c201632"
  - "8c4fc96"
  - "53ba5c7"
---

# Summary: Plan 03-01

## What Was Built

Added three flags to two existing Rust CLI commands for LLM token savings:
- `phase-detect --suggest-route`: appends `suggested_route={mode}` to output, mapping detected state to routing decisions (init/bootstrap/plan/execute/resume/archive)
- `resolve-model --with-cost`: wraps output in JSON `{"model":"opus","cost_weight":100}` instead of bare model name
- `resolve-model --all`: resolves all 9 agents in one call, returns JSON object
- `resolve-model --all --with-cost`: combined nested JSON output

## Files Modified

- `yolo-mcp-server/src/commands/phase_detect.rs` — --suggest-route flag, suggest_route_mode() helper, unit tests
- `yolo-mcp-server/src/commands/resolve_model.rs` — --with-cost and --all flags, cost_weight() helper, cache key variants, unit tests
- `tests/phase-detect.bats` — 3 new integration tests for --suggest-route
- `tests/resolve-agent-model.bats` — 3 new integration tests for --with-cost/--all

## Tasks Completed

### Task 1: Add --suggest-route to phase-detect
- **Commit:** `31098b6` — feat(phase-detect): add --suggest-route flag for LLM routing

### Task 2: Add --with-cost and --all to resolve-model
- **Commit:** `d9312f9` — feat(resolve-model): add --with-cost and --all flags

### Task 3: Rust unit tests for --suggest-route
- **Commit:** `c201632` — test(phase-detect): add unit tests for --suggest-route flag

### Task 4: Rust unit tests for --with-cost and --all
- **Commit:** `8c4fc96` — test(resolve-model): add unit tests for --with-cost and --all flags

### Task 5: Bats integration tests for new flags
- **Commit:** `53ba5c7` — test(commands): add bats integration tests for new flags

## Deviations

None. All must_haves delivered as planned.
