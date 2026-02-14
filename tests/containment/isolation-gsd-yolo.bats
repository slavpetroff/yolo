#!/usr/bin/env bats
# isolation-gsd-yolo.bats — Bidirectional GSD <-> YOLO context isolation containment tests

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  load '../test_helper/mock_stdin'
  mk_test_workdir
  mk_planning_dir
}

# --- security-filter.sh: .planning/ isolation ---

@test "security-filter blocks .planning/ when .active-agent exists" {
  mk_active_agent "dev"
  run_with_json '{"tool_input":{"file_path":".planning/intel/map.json"}}' "$SCRIPTS_DIR/security-filter.sh"
  assert_failure 2
  assert_output --partial "Blocked"
}

@test "security-filter blocks .planning/ when .yolo-session exists" {
  mk_yolo_session
  run_with_json '{"tool_input":{"file_path":".planning/intel/map.json"}}' "$SCRIPTS_DIR/security-filter.sh"
  assert_failure 2
  assert_output --partial "Blocked"
}

@test "security-filter allows .planning/ when neither marker exists" {
  # No .active-agent, no .yolo-session — GSD should be free to access its own dir
  run_with_json '{"tool_input":{"file_path":".planning/intel/map.json"}}' "$SCRIPTS_DIR/security-filter.sh"
  assert_success
}

@test "security-filter blocks .yolo-planning/ when gsd-isolation and no markers" {
  mk_gsd_isolation
  # Remove any markers that might exist
  rm -f "$TEST_WORKDIR/.yolo-planning/.active-agent" "$TEST_WORKDIR/.yolo-planning/.yolo-session"
  run_with_json '{"tool_input":{"file_path":".yolo-planning/state.json"}}' "$SCRIPTS_DIR/security-filter.sh"
  assert_failure 2
  assert_output --partial "Blocked"
}

@test "security-filter allows .yolo-planning/ when gsd-isolation and active-agent" {
  mk_gsd_isolation
  mk_active_agent "dev"
  run_with_json '{"tool_input":{"file_path":".yolo-planning/state.json"}}' "$SCRIPTS_DIR/security-filter.sh"
  assert_success
}

@test "security-filter allows .yolo-planning/ when gsd-isolation and yolo-session" {
  mk_gsd_isolation
  mk_yolo_session
  run_with_json '{"tool_input":{"file_path":".yolo-planning/state.json"}}' "$SCRIPTS_DIR/security-filter.sh"
  assert_success
}

# --- agent-start.sh: YOLO agent marker creation ---

@test "agent-start creates .active-agent for YOLO agents" {
  run_with_json '{"agent_type":"yolo-dev"}' "$SCRIPTS_DIR/agent-start.sh"
  assert_success
  assert_file_exists "$TEST_WORKDIR/.yolo-planning/.active-agent"
  # agent-start preserves the full yolo-* prefix
  run cat "$TEST_WORKDIR/.yolo-planning/.active-agent"
  assert_output "yolo-dev"
}

@test "agent-start ignores non-YOLO agents" {
  run_with_json '{"agent_type":"gsd-planner"}' "$SCRIPTS_DIR/agent-start.sh"
  assert_success
  assert_file_not_exists "$TEST_WORKDIR/.yolo-planning/.active-agent"
}

# --- agent-stop.sh: YOLO agent marker removal ---

@test "agent-stop removes .active-agent" {
  mk_active_agent "dev"
  assert_file_exists "$TEST_WORKDIR/.yolo-planning/.active-agent"
  run bash "$SCRIPTS_DIR/agent-stop.sh"
  assert_success
  assert_file_not_exists "$TEST_WORKDIR/.yolo-planning/.active-agent"
}

# --- prompt-preflight.sh: session marker management ---

@test "prompt-preflight creates .yolo-session on /yolo: commands" {
  mk_gsd_isolation
  run_with_json '{"prompt":"/yolo:status"}' "$SCRIPTS_DIR/prompt-preflight.sh"
  assert_success
  assert_file_exists "$TEST_WORKDIR/.yolo-planning/.yolo-session"
}

@test "prompt-preflight does NOT create .yolo-session on non-/yolo: commands" {
  mk_gsd_isolation
  # Ensure no session marker exists
  rm -f "$TEST_WORKDIR/.yolo-planning/.yolo-session"
  run_with_json '{"prompt":"help me write a function"}' "$SCRIPTS_DIR/prompt-preflight.sh"
  assert_success
  assert_file_not_exists "$TEST_WORKDIR/.yolo-planning/.yolo-session"
}

# --- session-stop.sh: session marker cleanup ---

@test "session-stop removes .yolo-session" {
  mk_yolo_session
  assert_file_exists "$TEST_WORKDIR/.yolo-planning/.yolo-session"
  run_with_json '{"cost_usd":0,"duration_ms":1000}' "$SCRIPTS_DIR/session-stop.sh"
  assert_success
  assert_file_not_exists "$TEST_WORKDIR/.yolo-planning/.yolo-session"
}
