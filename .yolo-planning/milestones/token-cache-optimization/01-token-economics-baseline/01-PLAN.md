---
phase: 1
plan: 1
title: "Extend telemetry schema with per-agent token metrics"
wave: 1
depends_on: []
must_haves:
  - "yolo report shows per-agent token spend (input/output/cache_read/cache_write) per phase"
---

# Plan 1: Extend Telemetry Schema with Per-Agent Token Metrics

## Goal
Add a new `agent_token_usage` table to the SQLite telemetry DB that captures per-agent token metrics (input_tokens, output_tokens, cache_read_tokens, cache_write_tokens) tagged with agent_role and phase. Also expose a `record_agent_tokens` method and wire it into the MCP compile_context tool so data is captured on every context compilation.

## Tasks

### Task 1: Add `agent_token_usage` table to telemetry DB
**Files to modify:**
- `yolo-mcp-server/src/telemetry/db.rs`

**What to implement:**
- Add a new `CREATE TABLE IF NOT EXISTS agent_token_usage` in the `init()` method with columns:
  - `id INTEGER PRIMARY KEY`
  - `agent_role TEXT NOT NULL`
  - `phase INTEGER`
  - `session_id TEXT`
  - `input_tokens INTEGER NOT NULL DEFAULT 0`
  - `output_tokens INTEGER NOT NULL DEFAULT 0`
  - `cache_read_tokens INTEGER NOT NULL DEFAULT 0`
  - `cache_write_tokens INTEGER NOT NULL DEFAULT 0`
  - `timestamp TEXT NOT NULL`
- Add a `record_agent_tokens()` method on `TelemetryDb` that inserts a row
- Add a `query_agent_token_summary()` method that returns aggregated token counts grouped by (agent_role, phase) — returns a `Vec` of structs or `Vec<Value>`

**Test expectations:**
- Rust unit test: insert 3 records for different roles/phases, query summary, verify aggregation is correct
- Rust unit test: verify table creation is idempotent (call init twice)

### Task 2: Add new event types for token tracking to log_event
**Files to modify:**
- `yolo-mcp-server/src/commands/log_event.rs`

**What to implement:**
- Add `"agent_token_usage"` to the `ALLOWED_EVENT_TYPES` array
- This allows agents to emit token usage events via `yolo log-event agent_token_usage <phase> role=dev input_tokens=5000 output_tokens=1200 cache_read=3000 cache_write=800`

**Test expectations:**
- Rust unit test: verify `agent_token_usage` event is accepted when `v2_typed_protocol=true`

### Task 3: Wire token recording into MCP compile_context tool
**Files to modify:**
- `yolo-mcp-server/src/mcp/tools.rs`

**What to implement:**
- After compile_context builds the combined output, record the prefix_bytes and volatile tail size as proxy token metrics into the tool_usage table via `record_tool_call` (already exists — enhance the output_length to use the actual combined length)
- Add `cache_read_tokens` and `cache_write_tokens` fields to the JSON response of compile_context (alongside existing `prefix_bytes` and `prefix_hash`) to enable downstream dashboard queries
- The response should include: `"input_tokens_estimate": prefix_bytes + volatile_bytes`, `"cache_read_tokens_estimate"` (if prefix_hash matches previous call, count as cache_read), `"cache_write_tokens_estimate"` (if new prefix_hash, count as cache_write)

**Test expectations:**
- Rust unit test in tools.rs: call compile_context twice with same role, verify second call has matching prefix_hash (implies cache read)
- Rust unit test: verify response contains `input_tokens_estimate` field

### Task 4: Add collect-metrics event type for agent tokens
**Files to modify:**
- `yolo-mcp-server/src/commands/collect_metrics.rs`

**What to implement:**
- No code changes needed to collect_metrics itself (it already accepts arbitrary event+data pairs)
- Add a Rust integration test that calls `collect("agent_token_usage", "1", Some("1"), &data_pairs, cwd)` with token fields and verifies the JSONL output contains them

**Test expectations:**
- Rust unit test: verify collect writes agent_token_usage event with input_tokens, output_tokens, cache_read_tokens, cache_write_tokens in data
