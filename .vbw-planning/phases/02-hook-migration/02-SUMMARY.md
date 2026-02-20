---
plan: 02
title: "Migrate log-event.sh and collect-metrics.sh to native Rust modules"
status: complete
commits: 4
tests_added: 22
tests_total: 260
---

## What Was Built

Native Rust replacements for `scripts/log-event.sh` and `scripts/collect-metrics.sh`, eliminating all bash shell-outs from `hard_gate.rs`.

## Tasks Completed

1. **log_event module** (`yolo-mcp-server/src/commands/log_event.rs`)
   - `log_event::log()` function callable from other Rust code
   - `log_event::execute()` CLI entry point for `yolo log-event`
   - v3_event_log feature flag check (exit early if false)
   - v2_typed_protocol event type validation (30+ known types)
   - Correlation ID resolution: YOLO_CORRELATION_ID env var -> .execution-state.json -> ""
   - UUID v4 generation via `uuid` crate (no uuidgen shell-out)
   - Atomic JSONL append to `.yolo-planning/.events/event-log.jsonl`
   - 12 tests

2. **collect_metrics module** (`yolo-mcp-server/src/commands/collect_metrics.rs`)
   - `collect_metrics::collect()` function callable from other Rust code
   - `collect_metrics::execute()` CLI entry point for `yolo collect-metrics`
   - key=value pair parsing from CLI args
   - Atomic JSONL append to `.yolo-planning/.metrics/run-metrics.jsonl`
   - 10 tests

3. **hard_gate.rs shell-out elimination** (`yolo-mcp-server/src/commands/hard_gate.rs`)
   - Replaced `Command::new("bash").arg(log_event_sh)` with `log_event::log()`
   - Replaced `Command::new("bash").arg(collect_metrics_sh)` with `collect_metrics::collect()`
   - Removed `#[cfg(not(tarpaulin_include))]` guards (native calls are testable)
   - All 14 existing hard_gate tests pass unchanged

4. **CLI registration** (`yolo-mcp-server/src/cli/router.rs`, `yolo-mcp-server/src/commands/mod.rs`)
   - Added `log-event` and `collect-metrics` routes to CLI router
   - Registered both modules in commands/mod.rs
   - Added `uuid` crate to Cargo.toml

## Files Modified

- `yolo-mcp-server/src/commands/log_event.rs` (new)
- `yolo-mcp-server/src/commands/collect_metrics.rs` (new)
- `yolo-mcp-server/src/commands/hard_gate.rs` (modified)
- `yolo-mcp-server/src/commands/mod.rs` (modified)
- `yolo-mcp-server/src/cli/router.rs` (modified)
- `yolo-mcp-server/Cargo.toml` (modified)
- `yolo-mcp-server/Cargo.lock` (modified)

## Deviations

None. All must-haves met.
