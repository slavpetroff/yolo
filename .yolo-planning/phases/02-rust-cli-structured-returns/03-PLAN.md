---
phase: 2
plan: 3
title: "Telemetry and state persistence structured returns"
wave: 1
depends_on: []
must_haves:
  - "log-event returns JSON with event_id, event_type, phase, written (bool)"
  - "collect-metrics returns JSON with event, phase, written (bool), metrics_file path"
  - "persist-state returns JSON with changed files, sections preserved, output_path"
  - "recover-state returns JSON (already returns JSON) with added ok/cmd/elapsed_ms envelope"
  - "All existing tests in all 4 files still pass"
  - "New tests verify JSON output for each command"
---

# Plan 3: Telemetry & State Persistence Structured Returns

## Overview

Retrofit 4 commands that deal with telemetry and state persistence: `log-event`, `collect-metrics`, `persist-state`, and `recover-state`. These are frequently called during phase execution and currently return minimal or empty output, causing wasted context when the caller cannot confirm what happened.

**NOTE:** Uses inline JSON envelope pattern (same shape as StructuredResponse from Plan 1) to avoid cross-plan file dependencies.

## Task 1: log-event structured return

**Files:**
- `yolo-mcp-server/src/commands/log_event.rs`

**Acceptance:**
- `execute()` returns JSON: `{"ok": true, "cmd": "log-event", "delta": {"event_type": "...", "phase": N, "event_id": "...", "written": true}, "elapsed_ms": N}`
- When event logging is disabled (v3_event_log=false), returns `{"ok": true, "cmd": "log-event", "delta": {"written": false, "reason": "v3_event_log disabled"}, "elapsed_ms": N}`
- When v2_typed_protocol rejects the event type, returns `{"ok": true, "cmd": "log-event", "delta": {"written": false, "reason": "unknown event type rejected"}, "elapsed_ms": N}` (exit code 3 SKIPPED, not error)
- All existing tests pass

**Implementation Details:**

The core `log()` function is called both from `execute()` (CLI) and from other Rust code. The structured return should be in `execute()` only. The `log()` function should be modified to return useful info:

1. Change `log()` signature to return `Result<LogResult, String>` where `LogResult` is a small struct: `{ written: bool, event_id: Option<String>, reason: Option<String> }`
2. In `execute()`, use the `LogResult` to build the JSON envelope
3. The event_id is already generated as a UUID -- just return it

For backward compatibility, callers of `log()` that ignore the result (`let _ = log(...)`) will still work since `LogResult` is simply a richer return value.

```rust
pub struct LogResult {
    pub written: bool,
    pub event_id: Option<String>,
    pub reason: Option<String>,
}
```

## Task 2: collect-metrics structured return

**Files:**
- `yolo-mcp-server/src/commands/collect_metrics.rs`

**Acceptance:**
- `execute()` returns JSON: `{"ok": true, "cmd": "collect-metrics", "delta": {"event": "...", "phase": N, "written": true, "metrics_file": "..."}, "elapsed_ms": N}`
- Changed files list includes the metrics file path
- All existing tests pass

**Implementation Details:**

Similar pattern to log-event:
1. Change `collect()` to return `Result<CollectResult, String>` with `{ written: bool, metrics_file: String }`
2. In `execute()`, build JSON envelope from the result
3. The metrics_file path is deterministic: `.yolo-planning/.metrics/run-metrics.jsonl`

```rust
pub struct CollectResult {
    pub written: bool,
    pub metrics_file: String,
}
```

## Task 3: persist-state structured return

**Files:**
- `yolo-mcp-server/src/commands/persist_state.rs`

**Acceptance:**
- Returns JSON: `{"ok": true, "cmd": "persist-state", "changed": ["<output_path>"], "delta": {"has_decisions": true, "has_todos": true, "has_blockers": false, "has_codebase_profile": true, "project_name": "..."}, "elapsed_ms": N}`
- Error case (missing archived file) returns `{"ok": false, ...}`
- All existing tests pass

**Implementation Details:**

The `generate_root_state()` function already extracts sections and checks `section_has_body()`. Thread those booleans back to the caller:

1. Change `generate_root_state()` to return a tuple: `(String, PersistDelta)` where PersistDelta has bools for each section
2. In `execute()`, build JSON envelope with the delta
3. The changed files list is just `[output_path]`

```rust
struct PersistDelta {
    has_decisions: bool,
    has_todos: bool,
    has_blockers: bool,
    has_codebase_profile: bool,
}
```

## Task 4: recover-state structured return envelope

**Files:**
- `yolo-mcp-server/src/commands/recover_state.rs`

**Acceptance:**
- Already returns JSON, but needs the standard envelope wrapping
- Returns: `{"ok": true, "cmd": "recover-state", "delta": {<existing JSON fields>}, "elapsed_ms": N}`
- When feature disabled or no phase dir found, returns `{"ok": true, "cmd": "recover-state", "delta": {"recovered": false, "reason": "..."}, "elapsed_ms": N}` with exit code 3 (SKIPPED)
- All existing tests still pass (update assertions for new envelope)

**Implementation Details:**

The current implementation returns the raw JSON object (`{"phase":1,"phase_name":"setup",...}`). Wrap it:

1. Add timer at function start
2. For the `Ok(("{}".to_string(), 0))` early returns (disabled/no phase dir), return the standard envelope with `recovered: false`
3. For the main result, embed the existing JSON object as `delta`:
```rust
let envelope = serde_json::json!({
    "ok": true,
    "cmd": "recover-state",
    "delta": result,  // the existing JSON
    "elapsed_ms": start.elapsed().as_millis() as u64
});
```
4. Update exit codes: feature disabled -> 3 (SKIPPED), no phase dir -> 3, success -> 0, error -> 1

## Task 5: Update tests for all 4 commands

**Files:**
- `yolo-mcp-server/src/commands/log_event.rs` (test module)
- `yolo-mcp-server/src/commands/collect_metrics.rs` (test module)
- `yolo-mcp-server/src/commands/persist_state.rs` (test module)
- `yolo-mcp-server/src/commands/recover_state.rs` (test module)

**Acceptance:**
- All existing test assertions hold
- Each test additionally parses the CLI output as JSON and validates envelope fields
- Tests for log-event validate event_id is returned
- Tests for collect-metrics validate metrics_file path
- Tests for persist-state validate section booleans
- Tests for recover-state validate the delta contains the recovery data under the envelope

**Implementation Details:**

For log-event and collect-metrics, the `log()` / `collect()` functions are tested separately from `execute()`. Add tests for `execute()` that check the JSON envelope. For tests calling `log()` / `collect()` directly, update them to use the new return types.

For recover-state, existing tests parse `out` as JSON. Update to parse `json["delta"]` instead of `json` directly:
```rust
let result: Value = serde_json::from_str(&out).unwrap();
assert_eq!(result["ok"], true);
assert_eq!(result["cmd"], "recover-state");
let delta = &result["delta"];
assert_eq!(delta["phase"], 1);
assert_eq!(delta["phase_name"], "setup");
```
