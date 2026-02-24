#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="${BATS_TEST_DIRNAME}/../.."
  SKILL_FILE="$PROJECT_ROOT/skills/execute-protocol/SKILL.md"
  ARCHITECT_FILE="$PROJECT_ROOT/agents/yolo-architect.md"
  EXEC_STATE_SCHEMA="$PROJECT_ROOT/config/schemas/execution-state-schema.json"
  MESSAGE_SCHEMAS="$PROJECT_ROOT/config/schemas/message-schemas.json"
}

# --- HITL vision gate artifact tests ---

@test "SKILL.md defines Step 2c vision gate enforcement section" {
  grep -q '### Step 2c' "$SKILL_FILE"
}

@test "Step 2c checks awaiting_approval status" {
  grep -q 'awaiting_approval' "$SKILL_FILE"
}

@test "step_2c is tracked in REQUIRED_STEPS" {
  grep -q 'step_2c' "$SKILL_FILE"
}

@test "awaiting_approval is a valid execution status" {
  # Verify it appears in the valid statuses documentation
  grep -q '"awaiting_approval"' "$SKILL_FILE"
}

@test "HITL gate summary table exists in SKILL.md" {
  grep -q 'HITL gate summary' "$SKILL_FILE"
}

@test "Architect agent documents structured response with paused status" {
  grep -q '"paused"' "$ARCHITECT_FILE"
}

@test "execution-state-schema.json exists and contains awaiting_approval" {
  [ -f "$EXEC_STATE_SCHEMA" ]
  grep -q 'awaiting_approval' "$EXEC_STATE_SCHEMA"
}

@test "hitl_approval schema exists in message-schemas.json" {
  grep -q 'hitl_approval' "$MESSAGE_SCHEMAS"
}
