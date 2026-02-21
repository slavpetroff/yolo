---
phase: 5
plan: 01
title: "Concurrent Request Handling & Telemetry Capture"
status: complete
---

## Summary
Refactored the MCP server to handle requests concurrently via tokio::spawn with an mpsc channel for ordered response writes. Fixed telemetry to record actual input/output byte lengths and tool names instead of hardcoded zeros and generic method names. Added 3 new tests covering concurrent request handling, telemetry byte lengths, and tool name recording.

## What Was Built
- Concurrent request dispatch: run_server now spawns each incoming request via tokio::spawn, with responses flowing through a 64-slot mpsc channel to a dedicated writer task that serializes output to stdout.
- Thread-safe TelemetryDb: Connection wrapped in std::sync::Mutex so Arc<TelemetryDb> can be shared across spawned tasks.
- Real telemetry capture: input_length computed from raw JSON line bytes, output_length from serialized response bytes, and tool_name records the actual tool (e.g. "compile_context") instead of generic "tools/call".
- 3 new tests: test_concurrent_requests (5 parallel requests), test_telemetry_records_byte_lengths (non-zero lengths), test_telemetry_records_tool_name (actual tool name).

## Tasks Completed
- Task 1: Refactor run_server to use tokio::spawn + mpsc for concurrent request handling (50b77c6)
- Task 2: Capture real telemetry input/output byte lengths (50b77c6)
- Task 3: Add tests for concurrent request handling and telemetry accuracy (50b77c6)

## Files Modified
- yolo-mcp-server/src/mcp/server.rs (concurrent dispatch, telemetry byte lengths, new tests)
- yolo-mcp-server/src/telemetry/db.rs (wrap Connection in Mutex for thread safety)
- yolo-mcp-server/src/main.rs (update return type to Box<dyn Error + Send + Sync>)

## Deviations
- All 3 tasks committed as a single atomic commit instead of 3 separate commits. The changes are deeply intertwined: Task 1's tokio::spawn requires Task 2's input_len parameter in the handle_request signature, and Task 3's test updates span both. Separate commits would create intermediate broken states.
- db.rs was modified (not listed in plan's Files) to wrap Connection in std::sync::Mutex, making TelemetryDb thread-safe for tokio::spawn. This is a necessary prerequisite for concurrent request handling.
- main.rs return type updated to match the new run_server signature (Box<dyn Error + Send + Sync>).
