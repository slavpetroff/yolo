#!/usr/bin/env bats
# agent-start.bats — Unit tests for scripts/agent-start.sh
# SubagentStart hook: creates .active-agent marker for YOLO agents

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  load '../test_helper/mock_stdin'
  mk_test_workdir
  mk_planning_dir
  SUT="$SCRIPTS_DIR/agent-start.sh"
}

# --- Creates marker for YOLO agents ---

@test "creates .active-agent marker for yolo-dev agent" {
  run bash -c "cd '$TEST_WORKDIR' && echo '{\"agent_type\":\"yolo-dev\"}' | bash '$SUT'"
  assert_success
  assert_file_exists "$TEST_WORKDIR/.yolo-planning/.active-agent"
  run cat "$TEST_WORKDIR/.yolo-planning/.active-agent"
  assert_output "dev"
}

@test "creates .active-agent marker for yolo-lead agent" {
  run bash -c "cd '$TEST_WORKDIR' && echo '{\"agent_type\":\"yolo-lead\"}' | bash '$SUT'"
  assert_success
  run cat "$TEST_WORKDIR/.yolo-planning/.active-agent"
  assert_output "lead"
}

@test "creates .active-agent marker for yolo-qa agent" {
  run bash -c "cd '$TEST_WORKDIR' && echo '{\"agent_type\":\"yolo-qa\"}' | bash '$SUT'"
  assert_success
  run cat "$TEST_WORKDIR/.yolo-planning/.active-agent"
  assert_output "qa"
}

# --- Ignores non-YOLO agents ---

@test "ignores non-YOLO agent type" {
  run bash -c "cd '$TEST_WORKDIR' && echo '{\"agent_type\":\"gsd-dev\"}' | bash '$SUT'"
  assert_success
  assert_file_not_exists "$TEST_WORKDIR/.yolo-planning/.active-agent"
}

# --- Exits 0 when .yolo-planning missing ---

@test "exits 0 when .yolo-planning directory is missing" {
  rm -rf "$TEST_WORKDIR/.yolo-planning"
  run bash -c "cd '$TEST_WORKDIR' && echo '{\"agent_type\":\"yolo-dev\"}' | bash '$SUT'"
  assert_success
}

# --- Handles all recognized agent types ---

@test "strips yolo- prefix for all recognized agent types" {
  for agent in yolo-lead yolo-dev yolo-qa yolo-scout yolo-debugger yolo-architect; do
    rm -f "$TEST_WORKDIR/.yolo-planning/.active-agent"
    local expected="${agent#yolo-}"
    run bash -c "cd '$TEST_WORKDIR' && echo '{\"agent_type\":\"$agent\"}' | bash '$SUT'"
    assert_success
    run cat "$TEST_WORKDIR/.yolo-planning/.active-agent"
    assert_output "$expected"
  done
}
