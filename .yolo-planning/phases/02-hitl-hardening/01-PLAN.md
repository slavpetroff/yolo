---
phase: "02"
plan: "01"
title: "request_human_approval writes execution state and returns structured pause"
wave: 1
depends_on: []
must_haves:
  - "REQ-05: request_human_approval writes awaiting_approval status to .execution-state.json"
  - "REQ-05: request_human_approval returns structured JSON with status paused"
  - "REQ-05: request_human_approval records plan_path and timestamp in approval metadata"
---

# Plan 01: request_human_approval writes execution state and returns structured pause

## Goal

Transform the `request_human_approval` MCP tool from a stub that returns a text message into a real HITL gate that writes `"awaiting_approval"` status to `.yolo-planning/.execution-state.json` and returns a structured JSON pause signal. This gives the execute protocol a checkable on-disk state to enforce blocking.

## Tasks

### Task 1: Add execution state write to request_human_approval

**File:** `yolo-mcp-server/src/mcp/tools.rs` (lines 254-266)

**What to change:**

Replace the current stub implementation of the `"request_human_approval"` match arm with logic that:

1. Reads the current `.yolo-planning/.execution-state.json` from disk (if it exists)
2. Updates or creates the JSON with:
   - `"status": "awaiting_approval"`
   - `"approval": { "requested_at": "{ISO 8601}", "plan_path": "{plan_path}", "approved": false }`
3. Writes the updated JSON back to `.yolo-planning/.execution-state.json`
4. Returns a structured JSON response instead of plain text:

```json
{
  "content": [{"type": "text", "text": "HITL approval requested. Execution paused."}],
  "status": "paused",
  "approval": {
    "requested_at": "{ISO 8601}",
    "plan_path": "{plan_path}",
    "state_file": ".yolo-planning/.execution-state.json"
  }
}
```

Use `chrono::Utc::now().to_rfc3339()` for timestamps. Handle the case where the execution state file does not exist by creating a minimal one with just the approval fields.

**Why:** The current stub returns only text -- callers cannot programmatically detect the pause, and no on-disk state exists for other protocol steps to check. Writing `"awaiting_approval"` to disk is the foundation for enforce the vision gate in Plan 02.

### Task 2: Add approval resume helper

**File:** `yolo-mcp-server/src/mcp/tools.rs`

**What to change:**

Add a new internal helper function `write_approval_state(plan_path: &str, approved: bool) -> Result<(), String>` that:

1. Reads `.yolo-planning/.execution-state.json`
2. If `approved == false`: sets `"status": "awaiting_approval"` and writes the approval metadata object
3. If `approved == true`: sets `"status": "running"` and updates `"approval.approved": true, "approval.approved_at": "{ISO 8601}"`
4. Writes back atomically (write to temp file, then rename)

This helper is used by Task 1's implementation and will be used by a future `approve` CLI command.

**Why:** Encapsulates the state mutation logic so it can be reused by both the MCP tool and future approval/resume mechanisms without code duplication.

### Task 3: Update MCP tool input schema to document structured response

**File:** `yolo-mcp-server/src/mcp/tools.rs`

**What to change:**

Find where the MCP tool schema/description for `request_human_approval` is defined (the tool listing that gets returned to Claude Code). Update the description to document that the tool now:
- Writes execution state to disk
- Returns structured JSON with `status` and `approval` fields
- Requires `.yolo-planning/` directory to exist

If the tool schema is defined in a separate file (e.g., a JSON schema or Rust constant), update it there.

**Why:** Claude Code and agents need accurate tool descriptions to understand what the tool does and what response format to expect.
