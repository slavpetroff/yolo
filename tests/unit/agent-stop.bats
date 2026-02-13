#!/usr/bin/env bats
# agent-stop.bats — Unit tests for scripts/agent-stop.sh
# SubagentStop hook: removes .active-agent marker

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  load '../test_helper/mock_stdin'
  mk_test_workdir
  mk_planning_dir
  SUT="$SCRIPTS_DIR/agent-stop.sh"
}

# --- Removes marker ---

@test "removes .active-agent marker when it exists" {
  mk_active_agent "dev"
  assert_file_exists "$TEST_WORKDIR/.yolo-planning/.active-agent"

  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT'"
  assert_success
  assert_file_not_exists "$TEST_WORKDIR/.yolo-planning/.active-agent"
}

# --- No marker present ---

@test "exits 0 when .active-agent does not exist" {
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT'"
  assert_success
}

# --- Missing planning dir ---

@test "exits 0 when .yolo-planning directory is missing" {
  rm -rf "$TEST_WORKDIR/.yolo-planning"
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT'"
  assert_success
}

# --- Idempotent ---

@test "multiple runs are idempotent" {
  mk_active_agent "qa"
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT'"
  assert_success
  assert_file_not_exists "$TEST_WORKDIR/.yolo-planning/.active-agent"

  # Second run should also succeed
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT'"
  assert_success
}
