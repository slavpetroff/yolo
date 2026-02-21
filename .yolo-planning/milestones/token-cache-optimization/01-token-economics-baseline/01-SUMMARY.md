---
phase: 1
plan: 1
title: "Extend telemetry schema with per-agent token metrics"
status: complete
---

# Summary: Extend Telemetry Schema with Per-Agent Token Metrics

## What Was Built

1. **agent_token_usage SQLite table** (`telemetry/db.rs`) — New table with columns for agent_role, phase, session_id, and four token counters (input/output/cache_read/cache_write). Added `record_agent_tokens()` for inserts and `query_agent_token_summary()` for aggregated reporting grouped by (agent_role, phase).

2. **agent_token_usage event type** (`commands/log_event.rs`) — Added to ALLOWED_EVENT_TYPES so agents can emit token usage events via `yolo log-event agent_token_usage` when v2_typed_protocol is enabled.

3. **Token estimate fields in compile_context** (`mcp/tools.rs`) — Response now includes `input_tokens_estimate`, `cache_read_tokens_estimate`, `cache_write_tokens_estimate`, and `volatile_bytes`. Tracks prefix_hash per role across calls to detect cache hits (same prefix = cache read, new prefix = cache write).

4. **collect-metrics integration test** (`commands/collect_metrics.rs`) — Verified that collect() correctly writes agent_token_usage events with all token fields to JSONL output.

## Files Modified

- `yolo-mcp-server/src/telemetry/db.rs` — Added agent_token_usage table, record_agent_tokens(), query_agent_token_summary()
- `yolo-mcp-server/src/commands/log_event.rs` — Added "agent_token_usage" to ALLOWED_EVENT_TYPES
- `yolo-mcp-server/src/mcp/tools.rs` — Added last_prefix_hashes to ToolState, token estimate fields to compile_context response
- `yolo-mcp-server/src/commands/collect_metrics.rs` — Added integration test for agent_token_usage event

## Commits
- `feat(telemetry): add agent_token_usage table with record and query methods`
- `feat(log-event): add agent_token_usage to allowed event types`
- `feat(mcp): add token estimate fields to compile_context response`
- `test(collect-metrics): add integration test for agent_token_usage event`

## Test Results
- telemetry::db — 3 tests passed (insert+aggregation, idempotent init, original)
- commands::log_event — 13 tests passed (including new agent_token_usage acceptance)
- mcp::tools — 16 tests passed (including token estimates and cache hit detection)
- commands::collect_metrics — 11 tests passed (including new agent_token_usage integration)

## Deviations
None. All tasks implemented as specified in the plan.
