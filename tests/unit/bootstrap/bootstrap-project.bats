#!/usr/bin/env bats
# bootstrap-project.bats — Unit tests for scripts/bootstrap/bootstrap-project.sh
# Generates PROJECT.md with project name, description, and core value.

setup() {
  load '../../test_helper/common'
  load '../../test_helper/fixtures'
  load '../../test_helper/mock_stdin'
  mk_test_workdir
  SUT="$BOOTSTRAP_DIR/bootstrap-project.sh"
}

# --- Argument validation ---

@test "exits 1 with usage when fewer than 3 args" {
  run bash "$SUT"
  assert_failure
  assert_output --partial "Usage:"

  run bash "$SUT" "$TEST_WORKDIR/PROJECT.md"
  assert_failure
  assert_output --partial "Usage:"

  run bash "$SUT" "$TEST_WORKDIR/PROJECT.md" "MyProject"
  assert_failure
  assert_output --partial "Usage:"
}

@test "exits 0 with correct 3 args" {
  run bash "$SUT" "$TEST_WORKDIR/PROJECT.md" "TestProject" "A test project"
  assert_success
}

# --- File generation ---

@test "generates PROJECT.md at specified output path" {
  run bash "$SUT" "$TEST_WORKDIR/PROJECT.md" "TestProject" "A test project"
  assert_success
  assert_file_exist "$TEST_WORKDIR/PROJECT.md"
}

@test "creates parent directories if they do not exist" {
  local nested="$TEST_WORKDIR/deep/nested/dir/PROJECT.md"
  run bash "$SUT" "$nested" "TestProject" "A test project"
  assert_success
  assert_file_exist "$nested"
}

# --- Content correctness ---

@test "PROJECT.md contains project name as heading and description" {
  bash "$SUT" "$TEST_WORKDIR/PROJECT.md" "MyApp" "Build a CLI tool"
  run cat "$TEST_WORKDIR/PROJECT.md"
  assert_output --partial "# MyApp"
  assert_output --partial "Build a CLI tool"
  assert_output --partial "**Core value:** Build a CLI tool"
  assert_output --partial "## Requirements"
  assert_output --partial "## Constraints"
  assert_output --partial "## Key Decisions"
}

# --- Idempotency ---

@test "overwrites existing PROJECT.md on re-run" {
  bash "$SUT" "$TEST_WORKDIR/PROJECT.md" "FirstName" "First description"
  bash "$SUT" "$TEST_WORKDIR/PROJECT.md" "SecondName" "Second description"
  run cat "$TEST_WORKDIR/PROJECT.md"
  assert_output --partial "# SecondName"
  assert_output --partial "Second description"
  refute_output --partial "FirstName"
}
