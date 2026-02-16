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
  assert_output "yolo-dev"
}

@test "creates .active-agent marker for yolo-lead agent" {
  run bash -c "cd '$TEST_WORKDIR' && echo '{\"agent_type\":\"yolo-lead\"}' | bash '$SUT'"
  assert_success
  run cat "$TEST_WORKDIR/.yolo-planning/.active-agent"
  assert_output "yolo-lead"
}

@test "creates .active-agent marker for yolo-qa agent" {
  run bash -c "cd '$TEST_WORKDIR' && echo '{\"agent_type\":\"yolo-qa\"}' | bash '$SUT'"
  assert_success
  run cat "$TEST_WORKDIR/.yolo-planning/.active-agent"
  assert_output "yolo-qa"
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

@test "preserves yolo- prefix for all recognized agent types" {
  for agent in yolo-lead yolo-dev yolo-qa yolo-scout yolo-debugger yolo-architect; do
    rm -f "$TEST_WORKDIR/.yolo-planning/.active-agent"
    run bash -c "cd '$TEST_WORKDIR' && echo '{\"agent_type\":\"$agent\"}' | bash '$SUT'"
    assert_success
    run cat "$TEST_WORKDIR/.yolo-planning/.active-agent"
    assert_output "$agent"
  done
}

# --- Department Lead detection: dept-status.sh integration ---

# Helper to set up agent-start with mock dept-status.sh
mk_agent_start_with_mock() {
  mkdir -p "$TEST_WORKDIR/scripts"
  cp "$SCRIPTS_DIR/agent-start.sh" "$TEST_WORKDIR/scripts/agent-start.sh"
  # Mock dept-status.sh that captures its args
  cat > "$TEST_WORKDIR/scripts/dept-status.sh" <<'MOCK'
#!/bin/bash
echo "$@" > "$(dirname "$0")/../.dept-status-call"
MOCK
  chmod +x "$TEST_WORKDIR/scripts/dept-status.sh"
  export LOCAL_SUT="$TEST_WORKDIR/scripts/agent-start.sh"
}

# Helper to set up execution state and phase dir for dept tracking tests
mk_dept_tracking_env() {
  local phase_num="${1:-1}" phase_name="${2:-test}"
  local phase_dir="$TEST_WORKDIR/.yolo-planning/phases/$(printf '%02d' "$phase_num")-${phase_name}"
  mkdir -p "$phase_dir"
  jq -n --argjson phase "$phase_num" --arg phase_name "$phase_name" \
    '{phase:$phase,phase_name:$phase_name}' \
    > "$TEST_WORKDIR/.yolo-planning/.execution-state.json"
}

@test "fe-lead triggers frontend dept-status write" {
  mk_dept_tracking_env 1 test
  mk_agent_start_with_mock
  run bash -c "cd '$TEST_WORKDIR' && echo '{\"agent_type\":\"yolo-fe-lead\"}' | bash '$LOCAL_SUT'"
  assert_success
  assert_file_exists "$TEST_WORKDIR/.dept-status-call"
  run cat "$TEST_WORKDIR/.dept-status-call"
  assert_output --partial "--dept frontend"
  assert_output --partial "--status running"
  assert_output --partial "--step planning"
}

@test "ux-lead triggers uiux dept-status write" {
  mk_dept_tracking_env 1 test
  mk_agent_start_with_mock
  run bash -c "cd '$TEST_WORKDIR' && echo '{\"agent_type\":\"yolo-ux-lead\"}' | bash '$LOCAL_SUT'"
  assert_success
  assert_file_exists "$TEST_WORKDIR/.dept-status-call"
  run cat "$TEST_WORKDIR/.dept-status-call"
  assert_output --partial "--dept uiux"
}

@test "lead triggers backend dept-status write" {
  mk_dept_tracking_env 1 test
  mk_agent_start_with_mock
  run bash -c "cd '$TEST_WORKDIR' && echo '{\"agent_type\":\"yolo-lead\"}' | bash '$LOCAL_SUT'"
  assert_success
  assert_file_exists "$TEST_WORKDIR/.dept-status-call"
  run cat "$TEST_WORKDIR/.dept-status-call"
  assert_output --partial "--dept backend"
}

@test "non-lead agents skip dept-status write" {
  mk_dept_tracking_env 1 test
  mk_agent_start_with_mock
  for agent in yolo-dev yolo-fe-senior yolo-ux-qa; do
    rm -f "$TEST_WORKDIR/.dept-status-call"
    run bash -c "cd '$TEST_WORKDIR' && echo '{\"agent_type\":\"$agent\"}' | bash '$LOCAL_SUT'"
    assert_success
    assert_file_not_exists "$TEST_WORKDIR/.dept-status-call"
  done
}

@test "missing dept-status.sh degrades gracefully" {
  mk_dept_tracking_env 1 test
  mkdir -p "$TEST_WORKDIR/scripts"
  cp "$SCRIPTS_DIR/agent-start.sh" "$TEST_WORKDIR/scripts/agent-start.sh"
  # Do NOT create mock dept-status.sh
  run bash -c "cd '$TEST_WORKDIR' && echo '{\"agent_type\":\"yolo-fe-lead\"}' | bash '$TEST_WORKDIR/scripts/agent-start.sh'"
  assert_success
  assert_file_not_exists "$TEST_WORKDIR/.dept-status-call"
}
