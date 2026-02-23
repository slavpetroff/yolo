---
phase: 2
plan: 3
title: "Telemetry and state persistence structured returns"
status: complete
commits: 5
deviations: []
---

# Plan 3 Summary: Telemetry & State Persistence Structured Returns

Retrofitted 4 commands (log-event, collect-metrics, persist-state, recover-state) to return structured JSON envelopes with the standard `ok/cmd/delta/elapsed_ms` shape.

## What Was Built

- `LogResult` struct and structured JSON return for `log-event` command (written/event_id/reason fields, exit code 3 for skipped paths)
- `CollectResult` struct and structured JSON return for `collect-metrics` command (written/metrics_file fields)
- `PersistDelta` struct and structured JSON return for `persist-state` command (section booleans, changed files array, ok:false on error)
- Standard envelope wrapper for `recover-state` command (recovered flag, exit code 3 for disabled/missing)
- Updated and new tests validating JSON envelope output for all 4 commands (44 tests, 0 failures)

## Files Modified

- `yolo-mcp-server/src/commands/log_event.rs` -- Added LogResult struct, updated log() return type, JSON envelope in execute()
- `yolo-mcp-server/src/commands/collect_metrics.rs` -- Added CollectResult struct, updated collect() return type, JSON envelope in execute()
- `yolo-mcp-server/src/commands/persist_state.rs` -- Added PersistDelta struct, updated generate_root_state() to return tuple, JSON envelope in execute()
- `yolo-mcp-server/src/commands/recover_state.rs` -- Wrapped output in standard envelope, added recovered flag, exit code 3 for early returns

## Commits

1. `ee6c8dd` feat(log-event): add structured JSON return with LogResult
2. `8a1dcbd` feat(collect-metrics): add structured JSON return with CollectResult
3. `7f28285` feat(persist-state): add structured JSON return with PersistDelta
4. `8a33863` feat(recover-state): wrap output in standard JSON envelope
5. `d12b6ad` test(telemetry-state): update and add tests for structured JSON returns
