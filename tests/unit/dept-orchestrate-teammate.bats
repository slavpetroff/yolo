#!/usr/bin/env bats
# dept-orchestrate-teammate.bats -- Unit tests for dept-orchestrate.sh team_mode routing
# Tests the teammate-mode extensions added in plan 02-02 T3.
# Complements tests/unit/dept-orchestrate.bats (existing wave structure tests).

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/dept-orchestrate.sh"
}

# Helper: create config with team_mode and optional agent_teams
mk_teammate_config() {
  local backend="${1:-true}" frontend="${2:-false}" uiux="${3:-false}" workflow="${4:-backend_only}" team_mode="${5:-task}"
  mkdir -p "$TEST_WORKDIR/.yolo-planning"
  local agent_teams="true"
  if [ "$team_mode" = "teammate" ]; then
    agent_teams="true"
    export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
  else
    agent_teams="true"
    unset CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS 2>/dev/null || true
  fi
  jq -n \
    --argjson be "$backend" \
    --argjson fe "$frontend" \
    --argjson ux "$uiux" \
    --arg wf "$workflow" \
    --arg tm "$team_mode" \
    --argjson at "$agent_teams" \
    '{departments:{backend:$be,frontend:$fe,uiux:$ux},department_workflow:$wf,team_mode:$tm,agent_teams:$at}' \
    > "$TEST_WORKDIR/.yolo-planning/config.json"
}

# Helper: run dept-orchestrate with config and phase dir
run_orchestrate() {
  local config="${1:-$TEST_WORKDIR/.yolo-planning/config.json}"
  local phase_dir="${2:-$TEST_WORKDIR/.yolo-planning/phases/02-test}"
  run bash "$SUT" "$config" "$phase_dir"
}

# --- Teammate mode tests ---

@test "teammate mode: output includes team_mode=teammate" {
  mk_teammate_config true false false backend_only teammate
  run_orchestrate
  assert_success

  local tm
  tm=$(echo "$output" | jq -r '.team_mode')
  assert_equal "$tm" "teammate"
}

@test "teammate mode: backend-only has spawn_strategy=spawnTeam" {
  mk_teammate_config true false false backend_only teammate
  run_orchestrate
  assert_success

  local strategy
  strategy=$(echo "$output" | jq -r '.waves[0].depts[0].spawn_strategy')
  assert_equal "$strategy" "spawnTeam"
}

@test "teammate mode: backend-only has team_name=yolo-backend" {
  mk_teammate_config true false false backend_only teammate
  run_orchestrate
  assert_success

  local tn
  tn=$(echo "$output" | jq -r '.waves[0].depts[0].team_name')
  assert_equal "$tn" "yolo-backend"
}

@test "teammate mode: parallel 3-dept has correct team_names" {
  mk_teammate_config true true true parallel teammate
  run_orchestrate
  assert_success

  # Wave 0: uiux
  local ux_tn
  ux_tn=$(echo "$output" | jq -r '.waves[0].depts[0].team_name')
  assert_equal "$ux_tn" "yolo-uiux"

  # Wave 1: frontend + backend
  local fe_tn be_tn
  fe_tn=$(echo "$output" | jq -r '[.waves[1].depts[] | select(.dept=="frontend")][0].team_name')
  be_tn=$(echo "$output" | jq -r '[.waves[1].depts[] | select(.dept=="backend")][0].team_name')
  assert_equal "$fe_tn" "yolo-frontend"
  assert_equal "$be_tn" "yolo-backend"
}

@test "teammate mode: all depts have spawn_strategy=spawnTeam" {
  mk_teammate_config true true true parallel teammate
  run_orchestrate
  assert_success

  # Count depts with spawn_strategy != spawnTeam (should be 0)
  local bad_count
  bad_count=$(echo "$output" | jq '[.waves[].depts[] | select(.spawn_strategy != "spawnTeam")] | length')
  assert_equal "$bad_count" "0"
}

# --- Task mode backward compatibility ---

@test "task mode: output includes team_mode=task" {
  mk_teammate_config true false false backend_only task
  run_orchestrate
  assert_success

  local tm
  tm=$(echo "$output" | jq -r '.team_mode')
  assert_equal "$tm" "task"
}

@test "task mode: depts have spawn_strategy=task" {
  mk_teammate_config true true true parallel task
  run_orchestrate
  assert_success

  local bad_count
  bad_count=$(echo "$output" | jq '[.waves[].depts[] | select(.spawn_strategy != "task")] | length')
  assert_equal "$bad_count" "0"
}

@test "task mode: no team_name field present" {
  mk_teammate_config true false false backend_only task
  run_orchestrate
  assert_success

  local tn
  tn=$(echo "$output" | jq -r '.waves[0].depts[0].team_name // "null"')
  assert_equal "$tn" "null"
}

# --- Edge case ---

@test "missing team_mode in config defaults to task behavior" {
  # Create config WITHOUT team_mode field (only departments + workflow)
  mkdir -p "$TEST_WORKDIR/.yolo-planning"
  jq -n '{departments:{backend:true,frontend:false,uiux:false},department_workflow:"backend_only"}' \
    > "$TEST_WORKDIR/.yolo-planning/config.json"
  unset CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS 2>/dev/null || true
  run_orchestrate
  assert_success

  local tm
  tm=$(echo "$output" | jq -r '.team_mode')
  assert_equal "$tm" "task"

  local strategy
  strategy=$(echo "$output" | jq -r '.waves[0].depts[0].spawn_strategy')
  assert_equal "$strategy" "task"
}
