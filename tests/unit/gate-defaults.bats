#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="${BATS_TEST_DIRNAME}/../.."
}

# --- Gate defaults regression tests ---

@test "review_gate defaults to always" {
  run jq -r '.review_gate' "$PROJECT_ROOT/config/defaults.json"
  [ "$status" -eq 0 ]
  [ "$output" = "always" ]
}

@test "qa_gate defaults to always" {
  run jq -r '.qa_gate' "$PROJECT_ROOT/config/defaults.json"
  [ "$status" -eq 0 ]
  [ "$output" = "always" ]
}

@test "review_max_cycles is a positive integer" {
  run jq -e '.review_max_cycles | type == "number" and . > 0' "$PROJECT_ROOT/config/defaults.json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "qa_max_cycles is a positive integer" {
  run jq -e '.qa_max_cycles | type == "number" and . > 0' "$PROJECT_ROOT/config/defaults.json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}
