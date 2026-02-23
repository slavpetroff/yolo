#!/usr/bin/env bats

load test_helper

setup() {
  PROJECT_ROOT="${BATS_TEST_DIRNAME}/.."
}

# --- Feedback loop config validation ---

@test "config has review_max_cycles with default 3" {
  run jq -e '.review_max_cycles' "$PROJECT_ROOT/.yolo-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]
}

@test "config has qa_max_cycles with default 3" {
  run jq -e '.qa_max_cycles' "$PROJECT_ROOT/.yolo-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]
}

@test "defaults has review_max_cycles and qa_max_cycles" {
  run jq -e 'has("review_max_cycles") and has("qa_max_cycles")' "$PROJECT_ROOT/config/defaults.json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}
