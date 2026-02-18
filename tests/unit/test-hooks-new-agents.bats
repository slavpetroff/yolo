#!/usr/bin/env bats
# test-hooks-new-agents.bats — Verify SubagentStart matchers and
# validate-dept-spawn acceptance for Phase 1-5 agents:
# yolo-analyze, yolo-po, yolo-questionary, yolo-roadmap, yolo-integration-gate

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

# --- SubagentStart matcher coverage (hooks.json regex) ---

@test "hooks.json SubagentStart matcher includes yolo-po" {
  run jq -r '.hooks.SubagentStart[0].matcher' "$HOOKS_JSON"
  assert_success
  assert_output --partial "yolo-po"
}

@test "hooks.json SubagentStart matcher includes yolo-questionary" {
  run jq -r '.hooks.SubagentStart[0].matcher' "$HOOKS_JSON"
  assert_success
  assert_output --partial "yolo-questionary"
}

@test "hooks.json SubagentStart matcher includes yolo-roadmap" {
  run jq -r '.hooks.SubagentStart[0].matcher' "$HOOKS_JSON"
  assert_success
  assert_output --partial "yolo-roadmap"
}

@test "hooks.json SubagentStart matcher includes yolo-analyze" {
  run jq -r '.hooks.SubagentStart[0].matcher' "$HOOKS_JSON"
  assert_success
  assert_output --partial "yolo-analyze"
}

@test "hooks.json SubagentStart matcher includes yolo-integration-gate" {
  run jq -r '.hooks.SubagentStart[0].matcher' "$HOOKS_JSON"
  assert_success
  assert_output --partial "yolo-integration-gate"
}

# --- validate-dept-spawn accepts new shared/PO agents ---

@test "yolo-analyze accepted without warning (backend_only)" {
  mk_config true false false backend_only
  run_validate "yolo-analyze"
  assert_success
  refute_output --partial "WARNING"
}

@test "yolo-po accepted without warning (backend_only)" {
  mk_config true false false backend_only
  run_validate "yolo-po"
  assert_success
  refute_output --partial "WARNING"
}

@test "yolo-questionary accepted without warning (backend_only)" {
  mk_config true false false backend_only
  run_validate "yolo-questionary"
  assert_success
  refute_output --partial "WARNING"
}

@test "yolo-roadmap accepted without warning (backend_only)" {
  mk_config true false false backend_only
  run_validate "yolo-roadmap"
  assert_success
  refute_output --partial "WARNING"
}

@test "yolo-integration-gate accepted without warning (backend_only)" {
  mk_config true false false backend_only
  run_validate "yolo-integration-gate"
  assert_success
  refute_output --partial "WARNING"
}

# --- New agents work regardless of department config ---

@test "yolo-analyze accepted when all depts disabled" {
  mk_config true false false backend_only
  run_validate "yolo-analyze"
  assert_success
  refute_output --partial "WARNING"
}

@test "yolo-po accepted when all depts enabled" {
  mk_config true true true parallel
  run_validate "yolo-po"
  assert_success
  refute_output --partial "WARNING"
}

@test "yolo-integration-gate accepted with no config file" {
  # No config file created
  run_validate "yolo-integration-gate"
  assert_success
  refute_output --partial "WARNING"
}

# --- Env var fallback for new agents ---

@test "yolo-analyze via TOOL_INPUT_agent_name env var" {
  mk_config true false false backend_only
  TOOL_INPUT_agent_name="yolo-analyze" run bash -c "echo '{}' | bash '$SUT'"
  assert_success
  refute_output --partial "WARNING"
}

@test "yolo-po via tool_input.name JSON field" {
  mk_config true false false backend_only
  run bash -c "echo '{\"tool_input\":{\"name\":\"yolo-po\"}}' | bash '$SUT'"
  assert_success
  refute_output --partial "WARNING"
}
