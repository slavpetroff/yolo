#!/usr/bin/env bats
# bootstrap-state-json.bats — Unit tests for scripts/bootstrap/bootstrap-state-json.sh
# Generates state.json for machine consumption.

setup() {
  load '../../test_helper/common'
  load '../../test_helper/fixtures'
  load '../../test_helper/mock_stdin'
  mk_test_workdir
  SUT="$BOOTSTRAP_DIR/bootstrap-state-json.sh"
}

# --- Argument validation ---

@test "exits 1 with usage when fewer than 3 args" {
  run bash "$SUT"
  assert_failure
  assert_output --partial "Usage:"

  run bash "$SUT" "$TEST_WORKDIR/state.json" "Milestone"
  assert_failure
  assert_output --partial "Usage:"
}

@test "exits 0 with correct 3 args" {
  run bash "$SUT" "$TEST_WORKDIR/state.json" "TestMilestone" "3"
  assert_success
}

# --- File generation ---

@test "generates state.json at specified output path" {
  run bash "$SUT" "$TEST_WORKDIR/state.json" "TestMilestone" "3"
  assert_success
  assert_file_exist "$TEST_WORKDIR/state.json"
}

@test "creates parent directories if they do not exist" {
  local nested="$TEST_WORKDIR/deep/nested/state.json"
  run bash "$SUT" "$nested" "TestMilestone" "2"
  assert_success
  assert_file_exist "$nested"
}

# --- Content correctness ---

@test "state.json contains correct fields and values" {
  bash "$SUT" "$TEST_WORKDIR/state.json" "Init Bootstrap" "4"
  run jq -r '.ms' "$TEST_WORKDIR/state.json"
  assert_output "Init Bootstrap"

  run jq -r '.ph' "$TEST_WORKDIR/state.json"
  assert_output "1"

  run jq -r '.tt' "$TEST_WORKDIR/state.json"
  assert_output "4"

  run jq -r '.st' "$TEST_WORKDIR/state.json"
  assert_output "planning"

  run jq -r '.step' "$TEST_WORKDIR/state.json"
  assert_output "none"

  run jq -r '.pr' "$TEST_WORKDIR/state.json"
  assert_output "0"

  run jq -r '.started' "$TEST_WORKDIR/state.json"
  assert_output "$(date +%Y-%m-%d)"
}

@test "state.json is valid JSON" {
  bash "$SUT" "$TEST_WORKDIR/state.json" "TestMilestone" "2"
  run jq empty "$TEST_WORKDIR/state.json"
  assert_success
}
