#!/usr/bin/env bats
# validate-dept-spawn.bats — Unit tests for scripts/validate-dept-spawn.sh
# SubagentStart hook: validates department agent spawn based on config.
# SubagentStart hook — CANNOT block (advisory only). Outputs stderr warnings.

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/validate-dept-spawn.sh"
}

# Helper: run validate-dept-spawn with agent name via stdin
run_validate() {
  local agent="$1"
  run bash -c "echo '{\"agent_name\":\"$agent\"}' | bash '$SUT'"
}

# Helper: create config with custom settings
mk_config() {
  local backend="${1:-true}"
  local frontend="${2:-false}"
  local uiux="${3:-false}"
  local workflow="${4:-backend_only}"
  mkdir -p "$TEST_WORKDIR/.yolo-planning"
  jq -n \
    --argjson be "$backend" \
    --argjson fe "$frontend" \
    --argjson ux "$uiux" \
    --arg wf "$workflow" \
    '{departments:{backend:$be,frontend:$fe,uiux:$ux},department_workflow:$wf}' \
    > "$TEST_WORKDIR/.yolo-planning/config.json"
}

# --- Frontend agent validation ---

@test "frontend agent allowed when departments.frontend=true" {
  mk_config true true false parallel
  run_validate "yolo-fe-dev"
  assert_success
}

@test "frontend agent blocked when departments.frontend=false" {
  mk_config true false false backend_only
  run_validate "yolo-fe-dev"
  assert_success
  assert_output --partial "WARNING"
}

@test "frontend agent blocked when workflow=backend_only" {
  mk_config true true false backend_only
  run_validate "yolo-fe-dev"
  assert_success
  assert_output --partial "WARNING"
}

@test "frontend lead allowed when frontend=true and parallel workflow" {
  mk_config true true false parallel
  run_validate "yolo-fe-lead"
  assert_success
}

@test "frontend lead blocked when frontend=false" {
  mk_config true false false parallel
  run_validate "yolo-fe-lead"
  assert_success
  assert_output --partial "WARNING"
}

# --- UI/UX agent validation ---

@test "uiux agent allowed when departments.uiux=true" {
  mk_config true false true parallel
  run_validate "yolo-ux-dev"
  assert_success
}

@test "uiux agent blocked when departments.uiux=false" {
  mk_config true false false backend_only
  run_validate "yolo-ux-dev"
  assert_success
  assert_output --partial "WARNING"
}

@test "uiux agent blocked when workflow=backend_only" {
  mk_config true false true backend_only
  run_validate "yolo-ux-dev"
  assert_success
  assert_output --partial "WARNING"
}

@test "uiux lead allowed when uiux=true and sequential workflow" {
  mk_config true false true sequential
  run_validate "yolo-ux-lead"
  assert_success
}

@test "uiux lead blocked when uiux=false" {
  mk_config true false false sequential
  run_validate "yolo-ux-lead"
  assert_success
  assert_output --partial "WARNING"
}

# --- Owner agent validation ---

@test "owner allowed when frontend=true (multi-dept enabled)" {
  mk_config true true false parallel
  run_validate "yolo-owner"
  assert_success
}

@test "owner allowed when uiux=true (multi-dept enabled)" {
  mk_config true false true sequential
  run_validate "yolo-owner"
  assert_success
}

@test "owner allowed when both frontend and uiux enabled" {
  mk_config true true true parallel
  run_validate "yolo-owner"
  assert_success
}

@test "owner blocked when frontend=false and uiux=false" {
  mk_config true false false backend_only
  run_validate "yolo-owner"
  assert_success
  assert_output --partial "WARNING"
}

@test "owner blocked when workflow=backend_only" {
  mk_config true true false backend_only
  run_validate "yolo-owner"
  assert_success
  assert_output --partial "WARNING"
}

# --- Backend agents ---

@test "backend agent always allowed" {
  mk_config true false false backend_only
  run_validate "yolo-dev"
  assert_success
}

@test "backend lead always allowed" {
  mk_config true false false backend_only
  run_validate "yolo-lead"
  assert_success
}

@test "backend architect always allowed" {
  mk_config true false false backend_only
  run_validate "yolo-architect"
  assert_success
}

@test "backend qa always allowed" {
  mk_config true false false backend_only
  run_validate "yolo-qa"
  assert_success
}

# --- Shared agents ---

@test "shared agent scout always allowed" {
  mk_config true false false backend_only
  run_validate "yolo-scout"
  assert_success
}

@test "shared agent critic always allowed" {
  mk_config true false false backend_only
  run_validate "yolo-critic"
  assert_success
}

@test "shared agent debugger always allowed" {
  mk_config true false false backend_only
  run_validate "yolo-debugger"
  assert_success
}

@test "shared agent security always allowed" {
  mk_config true false false backend_only
  run_validate "yolo-security"
  assert_success
}

# --- Missing config file ---

@test "missing config file: fail-open (allow spawn)" {
  # No config file
  run_validate "yolo-fe-dev"
  assert_success
}

@test "missing config file: owner allowed" {
  run_validate "yolo-owner"
  assert_success
}

# --- Malformed config ---

@test "malformed JSON: uses defaults (frontend=false)" {
  mkdir -p "$TEST_WORKDIR/.yolo-planning"
  echo "{invalid json" > "$TEST_WORKDIR/.yolo-planning/config.json"
  run_validate "yolo-fe-dev"
  # Script falls back to defaults: false|false|backend_only
  assert_success
  assert_output --partial "WARNING"
}

@test "missing departments key: uses defaults (frontend=false)" {
  mkdir -p "$TEST_WORKDIR/.yolo-planning"
  echo '{"department_workflow":"parallel"}' > "$TEST_WORKDIR/.yolo-planning/config.json"
  run_validate "yolo-fe-dev"
  assert_success
  assert_output --partial "WARNING"
}

# --- Non-yolo agents ---

@test "non-yolo agent always allowed" {
  mk_config true false false backend_only
  run_validate "vbw-lead"
  assert_success
}

@test "non-yolo agent with no name always allowed" {
  mk_config true false false backend_only
  run bash -c "echo '{}' | bash '$SUT'"
  assert_success
}

# --- Input edge cases ---

@test "empty stdin: allow spawn" {
  mk_config true false false backend_only
  run bash -c "echo '' | bash '$SUT'"
  assert_success
}

@test "no agent_name field: allow spawn" {
  mk_config true false false backend_only
  run bash -c "echo '{\"other_field\":\"value\"}' | bash '$SUT'"
  assert_success
}

@test "agent_name from tool_input.name: validated correctly" {
  mk_config true false false backend_only
  run bash -c "echo '{\"tool_input\":{\"name\":\"yolo-fe-dev\"}}' | bash '$SUT'"
  assert_success
  assert_output --partial "WARNING"
}

# --- Environment variable fallback ---

@test "agent name from TOOL_INPUT_agent_name env var" {
  mk_config true false false backend_only
  TOOL_INPUT_agent_name="yolo-fe-dev" run bash -c "echo '{}' | bash '$SUT'"
  assert_success
  assert_output --partial "WARNING"
}
