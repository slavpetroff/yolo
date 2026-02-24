---
phase: "02"
plan: "04"
title: "HITL hardening tests"
wave: 2
depends_on: ["01", "02", "03"]
must_haves:
  - "REQ-05: Rust unit tests verify request_human_approval writes execution state"
  - "REQ-05: Rust unit tests verify structured JSON response format"
  - "REQ-06: Bats tests verify Step 2c vision gate text exists in execute protocol"
  - "REQ-06: Bats tests verify step_2c in required steps array"
  - "REQ-06: Bats tests verify awaiting_approval status documented"
---

# Plan 04: HITL hardening tests

## Goal

Add comprehensive tests validating the HITL hardening changes from Plans 01-03. Rust unit tests verify the MCP tool behavior (writes state, returns structured JSON). Bats tests verify the execute protocol documentation includes the vision gate enforcement step and schema updates.

## Tasks

### Task 1: Rust unit tests for request_human_approval state writing

**File:** `yolo-mcp-server/src/mcp/tools.rs` (test module, after line ~497)

**What to change:**

Add new tests to the existing `#[cfg(test)] mod tests` block:

1. **`test_request_human_approval_writes_execution_state`**: Call `request_human_approval` with a valid `plan_path`, then read `.yolo-planning/.execution-state.json` from disk and verify:
   - `status` is `"awaiting_approval"`
   - `approval.plan_path` matches the input
   - `approval.approved` is `false`
   - `approval.requested_at` is a valid ISO 8601 timestamp

2. **`test_request_human_approval_structured_response`**: Call the tool and verify the response JSON contains:
   - `status` field with value `"paused"`
   - `approval.plan_path` matching input
   - `approval.state_file` pointing to `.yolo-planning/.execution-state.json`

3. **`test_request_human_approval_preserves_existing_state`**: Write a pre-existing execution state with `"status": "running"` and other fields (phase, wave, plans), then call `request_human_approval`. Verify:
   - Status changed to `"awaiting_approval"`
   - Other fields (phase, wave, plans) are preserved
   - Approval metadata was added

Use a temp directory with `CWD_MUTEX` (following existing test patterns) to avoid test interference.

**Why:** The existing tests (lines 480-497) only verify text output from the old stub. New tests must validate disk writes and structured responses.

### Task 2: Rust unit test for write_approval_state helper

**File:** `yolo-mcp-server/src/mcp/tools.rs` (test module)

**What to change:**

Add tests for the `write_approval_state` helper:

1. **`test_write_approval_state_request`**: Call with `approved=false`, verify execution state file has `"awaiting_approval"` status.
2. **`test_write_approval_state_approve`**: First write `awaiting_approval` state, then call with `approved=true`. Verify status changed to `"running"` and `approval.approved` is `true` with a valid `approved_at` timestamp.
3. **`test_write_approval_state_creates_dir`**: Call when `.yolo-planning/` does not exist. Verify the directory and file are created.

**Why:** The helper is the core state mutation logic. It must work correctly for both the request and resume paths.

### Task 3: Bats tests for execute protocol vision gate

**File:** `tests/unit/hitl-vision-gate.bats` (new file)

**What to change:**

Create a bats test file with the following tests:

1. **Step 2c section exists**: Grep for `### Step 2c: Vision gate enforcement` in `skills/execute-protocol/SKILL.md`
2. **Step 2c checks awaiting_approval**: Grep for `awaiting_approval` in the Step 2c section
3. **step_2c in REQUIRED_STEPS**: Grep for `step_2c` in the `REQUIRED_STEPS` array in Step 5
4. **awaiting_approval is valid status**: Grep for `awaiting_approval` in the valid statuses documentation
5. **Vision gate summary table exists**: Grep for `HITL gate summary` in Step 4.5
6. **Architect agent documents structured response**: Grep for `status.*paused` in `agents/yolo-architect.md`
7. **Execution state schema exists**: Verify `config/schemas/execution-state-schema.json` exists and contains `awaiting_approval`
8. **hitl_approval schema in message-schemas.json**: Grep for `hitl_approval` in `config/schemas/message-schemas.json`

Follow existing test patterns: `load test_helper`, `PROJECT_ROOT="${BATS_TEST_DIRNAME}/../.."` setup.

**Why:** Bats tests verify the documentation/protocol artifacts are correctly structured, catching regressions if protocol text is edited later.

### Task 4: Update existing step ordering test expectations

**File:** `tests/workflow-integrity-context.bats`

**What to change:**

The REQUIRED_STEPS test is at `tests/workflow-integrity-context.bats` (around line 89). Update it to expect `step_2c` in the list:

1. Find the test checking `REQUIRED_STEPS` content and add `step_2c` to the expected values (between `step_2b` and `step_3`)
2. Find the test checking the "Required:" display text and update to include `step_2c`
3. Add a new test asserting `step_2c` presence in the REQUIRED_STEPS array, following the pattern of existing step tracking tests (lines 63-81)

**Why:** Existing tests must be updated to match the new protocol structure. Failing to update would cause test failures after Plan 02 lands.
