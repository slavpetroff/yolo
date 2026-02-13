#!/usr/bin/env bats
# bootstrap-state.bats — Unit tests for scripts/bootstrap/bootstrap-state.sh
# Generates STATE.md with project name, milestone, and phase status.

setup() {
  load '../../test_helper/common'
  load '../../test_helper/fixtures'
  load '../../test_helper/mock_stdin'
  mk_test_workdir
  SUT="$BOOTSTRAP_DIR/bootstrap-state.sh"
}

# --- Argument validation ---

@test "exits 1 with usage when fewer than 4 args" {
  run bash "$SUT"
  assert_failure
  assert_output --partial "Usage:"

  run bash "$SUT" "$TEST_WORKDIR/STATE.md" "Project" "Milestone"
  assert_failure
  assert_output --partial "Usage:"
}

@test "exits 0 with correct 4 args" {
  run bash "$SUT" "$TEST_WORKDIR/STATE.md" "TestProject" "v1.0" "3"
  assert_success
}

# --- File generation ---

@test "generates STATE.md at specified output path" {
  run bash "$SUT" "$TEST_WORKDIR/STATE.md" "TestProject" "v1.0" "3"
  assert_success
  assert_file_exist "$TEST_WORKDIR/STATE.md"
}

@test "creates parent directories if they do not exist" {
  local nested="$TEST_WORKDIR/deep/nested/STATE.md"
  run bash "$SUT" "$nested" "TestProject" "v1.0" "2"
  assert_success
  assert_file_exist "$nested"
}

# --- Content correctness ---

@test "STATE.md contains project, milestone, phases, and key sections" {
  bash "$SUT" "$TEST_WORKDIR/STATE.md" "MyApp" "Init" "3"
  run cat "$TEST_WORKDIR/STATE.md"
  assert_output --partial "**Project:** MyApp"
  assert_output --partial "**Milestone:** Init"
  assert_output --partial "**Current Phase:** Phase 1"
  assert_output --partial "**Status:** Pending planning"
  assert_output --partial "**Progress:** 0%"
  assert_output --partial "**Phase 1:** Pending planning"
  assert_output --partial "**Phase 2:** Pending"
  assert_output --partial "**Phase 3:** Pending"
  assert_output --partial "## Key Decisions"
  assert_output --partial "## Recent Activity"
  assert_output --partial "Created Init milestone (3 phases)"
}

@test "phase 1 shows Pending planning, others show Pending" {
  bash "$SUT" "$TEST_WORKDIR/STATE.md" "Proj" "MS" "4"
  run cat "$TEST_WORKDIR/STATE.md"
  assert_output --partial "**Phase 1:** Pending planning"
  assert_output --partial "**Phase 2:** Pending"
  assert_output --partial "**Phase 3:** Pending"
  assert_output --partial "**Phase 4:** Pending"
}
