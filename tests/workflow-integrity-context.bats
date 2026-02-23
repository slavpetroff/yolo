#!/usr/bin/env bats

load test_helper

# --- Task 1: Context compilation tests for ARCHITECTURE.md in execution family ---

setup() {
  setup_temp_dir
  create_test_config

  mkdir -p "$TEST_TEMP_DIR/.yolo-planning/codebase"
  echo "# Architecture" > "$TEST_TEMP_DIR/.yolo-planning/codebase/ARCHITECTURE.md"
  echo "Architecture overview" >> "$TEST_TEMP_DIR/.yolo-planning/codebase/ARCHITECTURE.md"
  echo "# Roadmap" > "$TEST_TEMP_DIR/.yolo-planning/codebase/ROADMAP.md"
  echo "# Conventions" > "$TEST_TEMP_DIR/.yolo-planning/codebase/CONVENTIONS.md"
  echo "# Stack" > "$TEST_TEMP_DIR/.yolo-planning/codebase/STACK.md"
  mkdir -p "$TEST_TEMP_DIR/phases"
}

teardown() {
  teardown_temp_dir
}

@test "dev compiled context includes ARCHITECTURE.md content" {
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" compile-context 1 dev "$TEST_TEMP_DIR/phases"
  [ "$status" -eq 0 ]
  grep -q "Architecture overview" "$TEST_TEMP_DIR/phases/.context-dev.md"
}

@test "qa compiled context includes ARCHITECTURE.md content" {
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" compile-context 1 qa "$TEST_TEMP_DIR/phases"
  [ "$status" -eq 0 ]
  grep -q "Architecture overview" "$TEST_TEMP_DIR/phases/.context-qa.md"
}

@test "debugger compiled context includes ARCHITECTURE.md content" {
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" compile-context 1 debugger "$TEST_TEMP_DIR/phases"
  [ "$status" -eq 0 ]
  grep -q "Architecture overview" "$TEST_TEMP_DIR/phases/.context-debugger.md"
}

@test "default family does NOT get ARCHITECTURE.md" {
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" compile-context 1 observer "$TEST_TEMP_DIR/phases"
  [ "$status" -eq 0 ]
  ! grep -q "Architecture overview" "$TEST_TEMP_DIR/phases/.context-observer.md"
}

# --- Task 2: Step ordering and anti-takeover integration tests ---

SKILL_FILE="$BATS_TEST_DIRNAME/../skills/execute-protocol/SKILL.md"
LEAD_FILE="$BATS_TEST_DIRNAME/../agents/yolo-lead.md"

# Step tracking in execution-state.json schema

@test "SKILL.md defines steps_completed in execution-state.json schema" {
  grep -q '"steps_completed": \[\]' "$SKILL_FILE"
}

@test "SKILL.md tracks step_2 completion" {
  grep -q 'steps_completed += \["step_2"\]' "$SKILL_FILE"
}

@test "SKILL.md tracks step_2b completion" {
  grep -q 'steps_completed += \["step_2b"\]' "$SKILL_FILE"
}

@test "SKILL.md tracks step_3 completion" {
  grep -q 'steps_completed += \["step_3"\]' "$SKILL_FILE"
}

@test "SKILL.md tracks step_3c completion" {
  grep -q 'steps_completed += \["step_3c"\]' "$SKILL_FILE"
}

@test "SKILL.md tracks step_3d completion" {
  grep -q 'steps_completed += \["step_3d"\]' "$SKILL_FILE"
}

@test "SKILL.md tracks step_4 conditional completion" {
  grep -q 'steps_completed += \["step_4"\]' "$SKILL_FILE"
}

# Step 5 validation gate

@test "SKILL.md defines REQUIRED_STEPS variable" {
  grep -q 'REQUIRED_STEPS=' "$SKILL_FILE"
}

@test "SKILL.md contains Step ordering violation error message" {
  grep -q "Step ordering violation" "$SKILL_FILE"
}

@test "SKILL.md contains Step ordering verified success message" {
  grep -q "Step ordering verified" "$SKILL_FILE"
}

@test "SKILL.md contains jq subtraction formula for step validation" {
  grep -q '\$req - \$done' "$SKILL_FILE"
}

# Anti-takeover in Lead agent

@test "Lead agent has Anti-Takeover Protocol section" {
  grep -q "## Anti-Takeover Protocol" "$LEAD_FILE"
}

@test "Lead agent has NEVER Write/Edit rule" {
  grep -q "NEVER Write/Edit" "$LEAD_FILE"
}

@test "Lead agent has create a NEW Dev agent recovery instruction" {
  grep -q "create a NEW Dev agent" "$LEAD_FILE"
}
