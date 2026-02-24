---
phase: "02"
plan: "03"
title: "Architect agent and schema updates for HITL gate"
wave: 1
depends_on: []
must_haves:
  - "REQ-06: Architect agent documents structured response format from request_human_approval"
  - "REQ-05: Execution state schema includes awaiting_approval status and approval object"
  - "REQ-06: Approval message schemas updated with gate_type field"
---

# Plan 03: Architect agent and schema updates for HITL gate

## Goal

Update the Architect agent definition and config schemas to align with the new HITL enforcement. The Architect needs to know what structured response to expect from `request_human_approval`, and the schemas need to formally recognize the `awaiting_approval` status and approval metadata.

## Tasks

### Task 1: Update Architect agent HITL Vision Gate section

**File:** `agents/yolo-architect.md` (lines 50-52)

**What to change:**

Replace the current HITL Vision Gate section:

```markdown
## HITL Vision Gate

Once you have generated the `ROADMAP.md`, you MUST halt execution and call the `request_human_approval` MCP tool. YOU CANNOT proceed until the human explicitly reviews the roadmap and provides approval. This ensures the Vision does not drift before the Swarm begins execution.
```

With an expanded version that documents the tool's structured response:

```markdown
## HITL Vision Gate

Once you have generated the `ROADMAP.md`, you MUST halt execution and call the `request_human_approval` MCP tool with `plan_path` set to the ROADMAP.md path.

**Expected response:** The tool writes `"status": "awaiting_approval"` to `.yolo-planning/.execution-state.json` and returns:
- `"status": "paused"` -- confirms execution is halted
- `"approval.plan_path"` -- the path you provided
- `"approval.state_file"` -- where the state was written

**After calling the tool:** STOP. Do not produce further output. The execute protocol enforces this gate at Step 2c -- execution cannot proceed until a human approves the roadmap and the execution state is updated to `"running"`.

This ensures the Vision does not drift before the Swarm begins execution.
```

**Why:** The Architect agent needs to understand the structured response format so it can verify the tool worked correctly and knows what behavior to expect.

### Task 2: Add approval object to execution state documentation

**File:** `config/schemas/message-schemas.json`

**What to change:**

Add a new `"hitl_approval"` message schema to the `schemas` object:

```json
"hitl_approval": {
  "allowed_roles": ["lead", "architect"],
  "payload_required": ["plan_path", "gate_type", "status"],
  "payload_optional": ["requested_at", "approved_at", "approved_by"],
  "description": "HITL approval gate state for vision gate and other blocking checkpoints"
}
```

The `gate_type` field supports future HITL gates beyond the vision gate (e.g., `"vision"`, `"security"`, `"scope_change"`).

Also update the `role_hierarchy` to allow architect to send `hitl_approval`:

```json
"architect": {"can_send": ["plan_contract", "approval_response", "hitl_approval"], ...}
```

**Why:** The message schema system should formally define the HITL approval message type so it can be validated by the typed protocol system (v2_typed_protocol).

### Task 3: Add execution state schema reference

**File:** `config/schemas/execution-state-schema.json` (new file)

**What to change:**

Create a JSON Schema document that formally defines the `.execution-state.json` format, including the new `awaiting_approval` status and `approval` object:

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Execution State",
  "type": "object",
  "properties": {
    "phase": { "type": "integer" },
    "phase_name": { "type": "string" },
    "status": {
      "type": "string",
      "enum": ["running", "awaiting_approval", "complete"]
    },
    "started_at": { "type": "string", "format": "date-time" },
    "completed_at": { "type": ["string", "null"], "format": "date-time" },
    "wave": { "type": "integer" },
    "total_waves": { "type": "integer" },
    "correlation_id": { "type": "string" },
    "steps_completed": {
      "type": "array",
      "items": { "type": "string" }
    },
    "plans": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "id": { "type": "string" },
          "title": { "type": "string" },
          "wave": { "type": "integer" },
          "status": { "type": "string" }
        }
      }
    },
    "approval": {
      "type": "object",
      "properties": {
        "requested_at": { "type": "string", "format": "date-time" },
        "plan_path": { "type": "string" },
        "approved": { "type": "boolean" },
        "approved_at": { "type": ["string", "null"], "format": "date-time" }
      },
      "required": ["plan_path", "approved"]
    }
  },
  "required": ["status"]
}
```

**Why:** The execution state JSON is read by multiple protocol steps, the MCP tool, and future CLI commands. A formal schema prevents drift and enables automated validation.
