#!/usr/bin/env bats
# compute-dev-count.bats — Behavioral tests for scripts/compute-dev-count.sh
# Formula: min(available_unblocked_tasks, 5)
# RED phase: script does not exist yet, all tests must FAIL

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/compute-dev-count.sh"
}

# --- Existence and executability ---

@test "compute-dev-count.sh exists and is executable" {
  assert_file_executable "$SUT"
}

# --- Happy path: values at and below cap ---

@test "--available 0 outputs 0" {
  run bash "$SUT" --available 0
  assert_success
  assert_output "0"
}

@test "--available 1 outputs 1" {
  run bash "$SUT" --available 1
  assert_success
  assert_output "1"
}

@test "--available 3 outputs 3" {
  run bash "$SUT" --available 3
  assert_success
  assert_output "3"
}

@test "--available 5 outputs 5 (at cap)" {
  run bash "$SUT" --available 5
  assert_success
  assert_output "5"
}

# --- Cap enforcement ---

@test "--available 10 outputs 5 (capped)" {
  run bash "$SUT" --available 10
  assert_success
  assert_output "5"
}

@test "--available 100 outputs 5 (large value capped)" {
  run bash "$SUT" --available 100
  assert_success
  assert_output "5"
}

# --- Error handling ---

@test "--available -1 exits 1 with ERROR message" {
  run bash "$SUT" --available -1
  assert_failure
  assert_output --partial "ERROR"
}

@test "no arguments exits 1 with usage message" {
  run bash "$SUT"
  assert_failure
  assert_output --partial "Usage"
}

@test "missing --available flag exits 1 with usage message" {
  run bash "$SUT" 5
  assert_failure
  assert_output --partial "Usage"
}

@test "non-numeric argument exits 1 with ERROR message" {
  run bash "$SUT" --available abc
  assert_failure
  assert_output --partial "ERROR"
}

@test "float argument exits 1 with ERROR message" {
  run bash "$SUT" --available 3.5
  assert_failure
  assert_output --partial "ERROR"
}
