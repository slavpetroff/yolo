#!/usr/bin/env bats
# Migrated: compile-context.sh -> yolo compile-context
#           hard-gate research_warn not ported; tests replaced with
#           hard-gate unknown type validation and compile-context RESEARCH.md inclusion.
# CWD-sensitive: yes

load test_helper

setup() {
  setup_temp_dir
  create_test_config
}

teardown() {
  teardown_temp_dir
}

@test "research-persistence: RESEARCH.md template has required sections" {
  RESEARCH_FILE="$TEST_TEMP_DIR/01-RESEARCH.md"
  cp "$PROJECT_ROOT/templates/RESEARCH.md" "$RESEARCH_FILE"

  [ -f "$RESEARCH_FILE" ]

  # All 4 required section headers must be present exactly once
  [ "$(grep -c "^## Findings$" "$RESEARCH_FILE")" -eq 1 ]
  [ "$(grep -c "^## Relevant Patterns$" "$RESEARCH_FILE")" -eq 1 ]
  [ "$(grep -c "^## Risks$" "$RESEARCH_FILE")" -eq 1 ]
  [ "$(grep -c "^## Recommendations$" "$RESEARCH_FILE")" -eq 1 ]
}

@test "hard-gate: JSON output has gate, result, evidence fields (v2_hard_gates=false)" {
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" hard-gate research_warn 1 1 1 dummy.json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'has("gate")'
  echo "$output" | jq -e 'has("result")'
  echo "$output" | jq -e 'has("evidence")'
}

@test "hard-gate: JSON output has gate, result, evidence fields (v2_hard_gates=true)" {
  cd "$TEST_TEMP_DIR"
  jq '.v2_hard_gates = true' .yolo-planning/config.json > .yolo-planning/config.json.tmp \
    && mv .yolo-planning/config.json.tmp .yolo-planning/config.json
  run "$YOLO_BIN" hard-gate contract_compliance 1 1 1 dummy.json
  echo "$output" | jq -e 'has("gate")'
  echo "$output" | jq -e 'has("result")'
  echo "$output" | jq -e 'has("evidence")'
}

@test "hard-gate: insufficient args returns error JSON" {
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" hard-gate
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.gate == "unknown"'
  echo "$output" | jq -e '.result == "error"'
}

@test "hard-gate: v2_hard_gates=false returns skip" {
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" hard-gate contract_compliance 1 1 1 dummy.json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result == "skip"'
  echo "$output" | jq -e '.evidence == "v2_hard_gates=false"'
}

@test "research-persistence: compile-context includes RESEARCH.md" {
  cd "$TEST_TEMP_DIR"
  TEMP_PHASES="$TEST_TEMP_DIR/.yolo-planning/phases"
  mkdir -p "$TEMP_PHASES/01-test-phase"

  # Create minimal ROADMAP.md with Phase 01 definition
  cat > "$TEST_TEMP_DIR/.yolo-planning/ROADMAP.md" <<'ROADMAP'
# Roadmap

## Phase 01: Test Phase
**Goal**: Test phase goal
**Success Criteria**: Test criteria
**Requirements**: Not available
ROADMAP

  # Use tracked template as fixture source
  cp "$PROJECT_ROOT/templates/RESEARCH.md" "$TEMP_PHASES/01-test-phase/01-RESEARCH.md"

  # Run compile-context for phase 01, role lead
  run "$YOLO_BIN" compile-context 01 lead "$TEMP_PHASES"
  [ "$status" -eq 0 ]

  # Verify output file was created
  CONTEXT_FILE="$TEMP_PHASES/.context-lead.md"
  # compile-context writes to phases_dir (the 3rd arg)
  [ -f "$CONTEXT_FILE" ] || CONTEXT_FILE="$TEMP_PHASES/01-test-phase/.context-lead.md"
  [ -f "$CONTEXT_FILE" ]
}

@test "research-persistence: v3_plan_research_persist flag defaults to false" {
  cd "$TEST_TEMP_DIR"
  jq -e '.v3_plan_research_persist == false' .yolo-planning/config.json
}
