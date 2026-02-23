---
phase: 2
plan: 1
title: "StructuredResponse helper + update-state + compile-context"
wave: 1
depends_on: []
must_haves:
  - "New structured_response.rs module with StructuredResponse builder"
  - "update-state returns JSON with changed files, before/after plan counts, phase advancement info"
  - "compile_context MCP tool returns tier sizes, cache hit info, output path in JSON"
  - "All existing tests in state_updater.rs and tier_context.rs still pass"
  - "New Rust unit tests verify JSON output parsing for both commands"
---

# Plan 1: StructuredResponse Helper + Core Workflow Commands

## Overview

Create the shared `StructuredResponse` helper module that all subsequent plans will use, then retrofit `update-state` and the MCP `compile_context` tool to return structured JSON. These are the highest-impact commands because they are called most frequently during phase execution.

## Task 1: Create StructuredResponse helper module

**Files:**
- `yolo-mcp-server/src/commands/structured_response.rs` (new)
- `yolo-mcp-server/src/commands/mod.rs` (add module declaration)

**Acceptance:**
- `StructuredResponse` struct with fields: `ok: bool`, `cmd: String`, `changed: Vec<String>`, `delta: serde_json::Value`, `elapsed_ms: u64`, `error: Option<String>`
- `StructuredResponse::success(cmd)` and `StructuredResponse::error(cmd, msg)` constructors
- `.with_changed(files)`, `.with_delta(value)`, `.with_elapsed(ms)` builder methods
- `.to_json_string()` method that serializes to the standard JSON envelope
- `Timer` helper struct: `Timer::start()` returns a timer, `.elapsed_ms()` returns milliseconds since start
- Exit code constants: `EXIT_SUCCESS = 0`, `EXIT_ERROR = 1`, `EXIT_PARTIAL = 2`, `EXIT_SKIPPED = 3`

**Implementation Details:**

```rust
use serde::Serialize;
use serde_json::{json, Value};
use std::time::Instant;

pub const EXIT_SUCCESS: i32 = 0;
pub const EXIT_ERROR: i32 = 1;
pub const EXIT_PARTIAL: i32 = 2;
pub const EXIT_SKIPPED: i32 = 3;

pub struct Timer(Instant);

impl Timer {
    pub fn start() -> Self { Self(Instant::now()) }
    pub fn elapsed_ms(&self) -> u64 { self.0.elapsed().as_millis() as u64 }
}

#[derive(Serialize)]
pub struct StructuredResponse {
    pub ok: bool,
    pub cmd: String,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub changed: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub delta: Option<Value>,
    pub elapsed_ms: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}
```

Provide `impl StructuredResponse` with builder pattern. The `to_json_string()` method calls `serde_json::to_string(&self)`.

## Task 2: Retrofit update-state to return structured JSON

**Files:**
- `yolo-mcp-server/src/commands/state_updater.rs`

**Acceptance:**
- `update_state()` returns JSON string instead of plain text
- Delta includes: `trigger` (plan/summary), `plans_before`/`plans_after`, `summaries_before`/`summaries_after`, `phase_advanced` (bool), `new_phase` (if advanced), `status_changed_to` (if changed)
- Changed files list includes all files actually written (STATE.md, ROADMAP.md, .execution-state.json)
- Error case (file not found, not a plan/summary) returns `ok: false` with descriptive error
- Exit code 3 (SKIPPED) for "not a PLAN.md or SUMMARY.md file"

**Implementation Details:**

The function signature stays `pub fn update_state(file_path: &str) -> Result<String, String>` but the returned String is now JSON. Track which files are written by collecting paths in a `Vec<String>`. Before calling `update_state_md`, capture the plan/summary counts, then capture after. If `advance_phase` changes the phase, record that in the delta.

Early returns for non-target files should use:
```rust
StructuredResponse::error("update-state", "Not a PLAN.md or SUMMARY.md file")
    .to_json_string()
```

The Err variant stays for actual I/O errors. The Ok variant now returns JSON.

## Task 3: Retrofit compile_context MCP tool to return structured JSON

**Files:**
- `yolo-mcp-server/src/mcp/mod.rs` or the file containing the `compile_context` tool handler

**Acceptance:**
- compile_context tool result includes: tier1_size (bytes), tier2_size (bytes), tier3_size (bytes), total_size (bytes), cache_hit (bool), output_path, role, phase
- The existing output string (the compiled context) is still returned as the primary content, but the JSON metadata is appended as a trailing comment or returned alongside
- Alternatively: if compile_context already returns the context string to the MCP caller, add a new `compile_context_meta` or embed in the existing response

**Implementation Details:**

Look at how compile_context is implemented in the MCP server. The tier_context module already has `build_tier1`, `build_tier2`, `build_tier3_volatile`. After building each tier, capture `.len()` as the byte size. Build a delta JSON with those sizes and return it. If there is a cache layer (cache_context.rs), note the cache hit status.

Since the MCP tool returns content to the LLM agent, the structured metadata should be a JSON block at the end of the output, after `--- END COMPILED CONTEXT ---`, formatted as:
```
<!-- compile_context_meta: {"ok":true,"cmd":"compile-context",...} -->
```

## Task 4: Add tests for structured responses

**Files:**
- `yolo-mcp-server/src/commands/structured_response.rs` (inline tests)
- `yolo-mcp-server/src/commands/state_updater.rs` (update existing tests)

**Acceptance:**
- Unit tests for StructuredResponse builder (success, error, with_changed, with_delta, serialization)
- Timer test (elapsed > 0 after sleep)
- Updated state_updater tests parse the returned JSON and validate fields
- At least 1 test per: plan trigger, summary trigger, non-target file, missing file

**Implementation Details:**

Update existing tests in `state_updater.rs` to parse the returned string as JSON:
```rust
let result = update_state(plan_file.to_str().unwrap()).unwrap();
let json: serde_json::Value = serde_json::from_str(&result).unwrap();
assert_eq!(json["ok"], true);
assert_eq!(json["cmd"], "update-state");
assert!(json["changed"].as_array().unwrap().len() > 0);
```

Keep the existing assertions about file content (STATE.md, ROADMAP.md) -- those validate side effects. Add assertions about the JSON response that validate the delta.
