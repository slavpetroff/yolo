---
phase: 2
plan: 02
title: "Migrate log-event.sh and collect-metrics.sh to native Rust modules"
wave: 1
depends_on: []
must_haves:
  - "log_event module writes JSONL to `.yolo-planning/.events/event-log.jsonl`"
  - "collect_metrics module writes JSONL to `.yolo-planning/.metrics/run-metrics.jsonl`"
  - "Both modules callable as functions from other Rust code (no shell-outs)"
  - "Event type validation when v2_typed_protocol=true"
  - "Correlation ID resolution from execution-state.json"
  - "UUID generation via uuid crate (no uuidgen shell-out)"
---

## Task 1: Implement log_event module

**Files:** `yolo-mcp-server/src/commands/log_event.rs` (new)

**Acceptance:** `log_event::log(event_type, phase, plan, data_pairs, cwd)` appends a JSON line to `.yolo-planning/.events/event-log.jsonl`. Must:
1. Check `v3_event_log` flag in config.json (exit early if false)
2. Validate event type against allowed list when `v2_typed_protocol=true`
3. Resolve `correlation_id` from `YOLO_CORRELATION_ID` env var, then `.execution-state.json`
4. Generate `event_id` via `uuid::Uuid::new_v4()` (lowercase)
5. Build JSON with: ts, event_id, correlation_id, event, phase, plan (optional), data (optional)
6. Append atomically to event-log.jsonl
7. Create `.events/` directory if needed
8. Never fail fatally (return Ok on any error)

Also expose `pub fn execute(args, cwd)` for `yolo log-event <type> <phase> [plan] [key=value...]` CLI entry point.

## Task 2: Implement collect_metrics module

**Files:** `yolo-mcp-server/src/commands/collect_metrics.rs` (new)

**Acceptance:** `collect_metrics::collect(event, phase, plan, data_pairs, cwd)` appends a JSON line to `.yolo-planning/.metrics/run-metrics.jsonl`. Must:
1. Create `.metrics/` directory if needed
2. Build JSON with: ts, event, phase, plan (optional), data (optional)
3. Append atomically
4. Never fail fatally

Also expose `pub fn execute(args, cwd)` for `yolo collect-metrics <event> <phase> [plan] [key=value...]` CLI entry point. Parse key=value pairs from args.

## Task 3: Eliminate shell-outs to log-event.sh and collect-metrics.sh in hard_gate.rs

**Files:** `yolo-mcp-server/src/commands/hard_gate.rs`

**Acceptance:** Replace all `Command::new("bash").arg(log_event_sh)` and `Command::new("bash").arg(collect_metrics_sh)` calls inside `emit_res` closure and elsewhere with direct calls to `log_event::log()` and `collect_metrics::collect()`. The `#[cfg(not(tarpaulin_include))]` guards around these shell-outs can be removed since native Rust calls are testable. Behavior must be identical.

## Task 4: Register CLI commands and add tests

**Files:** `yolo-mcp-server/src/commands/mod.rs`, `yolo-mcp-server/src/cli/router.rs`, `yolo-mcp-server/src/commands/log_event.rs` (append tests), `yolo-mcp-server/src/commands/collect_metrics.rs` (append tests)

**Acceptance:** `yolo log-event` and `yolo collect-metrics` registered in router. Tests cover: event logging with valid type, event type rejection with v2_typed_protocol, correlation_id resolution chain, metrics collection, key=value parsing, directory creation on first write. `cargo test` passes.
