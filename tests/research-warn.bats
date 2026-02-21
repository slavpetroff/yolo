#!/usr/bin/env bats
# Migrated: research_warn gate type was never ported to Rust.
# Tests now verify: hard-gate unknown type handling, config flag presence,
# and RESEARCH.md template structure.

load test_helper

setup() {
  setup_temp_dir
  create_test_config
}

teardown() {
  teardown_temp_dir
}

@test "hard-gate: unknown gate type returns error result" {
  cd "$TEST_TEMP_DIR"
  jq '.v2_hard_gates = true' .yolo-planning/config.json > .yolo-planning/config.json.tmp \
    && mv .yolo-planning/config.json.tmp .yolo-planning/config.json
  run "$YOLO_BIN" hard-gate research_warn 1 1 1 dummy-contract.json
  [ "$status" -ne 0 ]
  echo "$output" | jq -e '.gate == "research_warn"'
  echo "$output" | jq -e '.result == "fail"'
}

@test "hard-gate: skip when v2_hard_gates=false" {
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" hard-gate research_warn 1 1 1 dummy-contract.json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result == "skip"'
  echo "$output" | jq -e '.evidence == "v2_hard_gates=false"'
}

@test "config: v3_plan_research_persist flag exists in defaults" {
  run jq -e 'has("v3_plan_research_persist")' "$CONFIG_DIR/defaults.json"
  [ "$status" -eq 0 ]
}

@test "RESEARCH.md template exists with required sections" {
  [ -f "$PROJECT_ROOT/templates/RESEARCH.md" ]
  grep -q "^## Findings" "$PROJECT_ROOT/templates/RESEARCH.md"
  grep -q "^## Relevant Patterns" "$PROJECT_ROOT/templates/RESEARCH.md"
  grep -q "^## Risks" "$PROJECT_ROOT/templates/RESEARCH.md"
  grep -q "^## Recommendations" "$PROJECT_ROOT/templates/RESEARCH.md"
}
