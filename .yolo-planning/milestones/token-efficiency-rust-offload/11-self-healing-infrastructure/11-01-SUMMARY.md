---
phase: 11
plan: 1
title: MCP Tool Retry with Exponential Backoff and Circuit Breaker
status: complete
tasks_completed: 5
tasks_total: 5
commit_hashes:
  - b9e9b88
  - a3d73ba
  - 1009cd2
  - 56b15a1
commits:
  - "feat(mcp): add retry config and circuit breaker module"
  - "feat(mcp): wire retry and circuit breaker into MCP tool dispatch"
  - "feat(mcp): track retry count and circuit breaker events in telemetry"
  - "test(mcp): add integration tests for retry and circuit breaker"
---

## What Was Built

Added retry logic with exponential backoff and circuit breaker protection to all 5 MCP tool calls. A new `retry.rs` module provides `RetryConfig` (3 max retries, 100ms base delay, 1000ms max), `CircuitBreaker` (per-tool failure tracking, opens after 5 consecutive failures, auto-resets after 60s), and `retry_tool_call()` async wrapper with jitter (0-50% of delay via SystemTime nanos). Non-retryable errors ("Unknown tool", "No test_path") are detected and skip retry. The `tool_usage` telemetry table gained a `retry_count` column with backward-compatible ALTER TABLE migration. Server.rs dispatches all tool calls through the retry wrapper and logs retry events to stderr.

## Files Modified

- `yolo-mcp-server/src/mcp/retry.rs` — CREATE: RetryConfig, CircuitBreaker, retry_tool_call(), is_retryable_error(), compute_delay(), 12 unit tests
- `yolo-mcp-server/src/mcp/mod.rs` — EDIT: Added `pub mod retry;`
- `yolo-mcp-server/src/mcp/server.rs` — EDIT: Replaced direct tool dispatch with retry wrapper, added Arc<Mutex<CircuitBreaker>> and RetryConfig, pass retry_count to telemetry, 6 integration tests
- `yolo-mcp-server/src/telemetry/db.rs` — EDIT: Added retry_count column migration, record_tool_call_with_retry() method

## Deviations

- **Tasks 1+2 combined into one commit**: RetryConfig/CircuitBreaker structs and retry_tool_call() are tightly coupled in the same module file, so they were implemented together rather than in two separate commits. This resulted in 4 commits instead of the planned 5.
- **Jitter uses SystemTime nanos mod instead of rand**: Plan specified "simple SystemTime nanosecond mod" which was followed exactly. No external rand crate was needed.
- **tokio::sync::Mutex instead of std::sync::Mutex for CircuitBreaker**: The circuit breaker is accessed inside async contexts across await points, requiring tokio's async-aware Mutex rather than std's blocking Mutex.
