#!/usr/bin/env bats
# dept-orchestrate.bats — Unit tests for scripts/dept-orchestrate.sh
# Department orchestration: generates JSON spawn plan from resolve-departments.sh output.
# Schema: {team_mode, waves:[{id, depts:[{dept, spawn_strategy, team_name?}], gate}], timeout_minutes}

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/dept-orchestrate.sh"
}

# Helper: create config with custom settings
mk_config() {
  local backend="${1:-true}" frontend="${2:-false}" uiux="${3:-false}" workflow="${4:-backend_only}" team_mode="${5:-task}" agent_teams="${6:-false}"
  mkdir -p "$TEST_WORKDIR/.yolo-planning"
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

# --- Parallel 3-dept workflow ---

@test "parallel 3-dept: UX wave then FE+BE wave" {
  mk_config true true true parallel
  run_orchestrate
  assert_success

  local wave_count
  wave_count=$(echo "$output" | jq '.waves | length')
  assert_equal "$wave_count" "2"

  local tm
  tm=$(echo "$output" | jq -r '.team_mode')
  assert_equal "$tm" "task"

  local w0_dept w0_gate w0_ss w1_depts_fe w1_depts_be w1_gate
  w0_dept=$(echo "$output" | jq -r '.waves[0].depts[0].dept')
  w0_gate=$(echo "$output" | jq -r '.waves[0].gate')
  w0_ss=$(echo "$output" | jq -r '.waves[0].depts[0].spawn_strategy')
  w1_depts_fe=$(echo "$output" | jq -r '[.waves[1].depts[].dept] | contains(["frontend"])')
  w1_depts_be=$(echo "$output" | jq -r '[.waves[1].depts[].dept] | contains(["backend"])')
  w1_gate=$(echo "$output" | jq -r '.waves[1].gate')

  assert_equal "$w0_dept" "uiux"
  assert_equal "$w0_gate" "handoff-ux-complete"
  assert_equal "$w0_ss" "task"
  assert_equal "$w1_depts_fe" "true"
  assert_equal "$w1_depts_be" "true"
  assert_equal "$w1_gate" "all-depts-complete"

  local timeout
  timeout=$(echo "$output" | jq '.timeout_minutes')
  assert_equal "$timeout" "30"
}

# --- Parallel no-UX workflow ---

@test "parallel no-UX: single wave FE+BE" {
  mk_config true true false parallel
  run_orchestrate
  assert_success

  local wave_count
  wave_count=$(echo "$output" | jq '.waves | length')
  assert_equal "$wave_count" "1"

  local tm
  tm=$(echo "$output" | jq -r '.team_mode')
  assert_equal "$tm" "task"

  local has_fe has_be gate ss
  has_fe=$(echo "$output" | jq -r '[.waves[0].depts[].dept] | contains(["frontend"])')
  has_be=$(echo "$output" | jq -r '[.waves[0].depts[].dept] | contains(["backend"])')
  gate=$(echo "$output" | jq -r '.waves[0].gate')
  ss=$(echo "$output" | jq -r '.waves[0].depts[0].spawn_strategy')

  assert_equal "$has_fe" "true"
  assert_equal "$has_be" "true"
  assert_equal "$gate" "all-depts-complete"
  assert_equal "$ss" "task"
}

# --- Sequential 3-dept workflow ---

@test "sequential 3-dept: three waves" {
  mk_config true true true sequential
  run_orchestrate
  assert_success

  local wave_count
  wave_count=$(echo "$output" | jq '.waves | length')
  assert_equal "$wave_count" "3"

  local tm
  tm=$(echo "$output" | jq -r '.team_mode')
  assert_equal "$tm" "task"

  local w0_dept w0_gate w0_ss w1_dept w1_gate w2_dept w2_gate
  w0_dept=$(echo "$output" | jq -r '.waves[0].depts[0].dept')
  w0_gate=$(echo "$output" | jq -r '.waves[0].gate')
  w0_ss=$(echo "$output" | jq -r '.waves[0].depts[0].spawn_strategy')
  w1_dept=$(echo "$output" | jq -r '.waves[1].depts[0].dept')
  w1_gate=$(echo "$output" | jq -r '.waves[1].gate')
  w2_dept=$(echo "$output" | jq -r '.waves[2].depts[0].dept')
  w2_gate=$(echo "$output" | jq -r '.waves[2].gate')

  assert_equal "$w0_dept" "uiux"
  assert_equal "$w0_gate" "handoff-ux-complete"
  assert_equal "$w0_ss" "task"
  assert_equal "$w1_dept" "frontend"
  assert_equal "$w1_gate" "handoff-frontend-complete"
  assert_equal "$w2_dept" "backend"
  assert_equal "$w2_gate" "all-depts-complete"
}

# --- Backend-only workflow ---

@test "backend-only: single wave" {
  mk_config true false false backend_only
  run_orchestrate
  assert_success

  local wave_count
  wave_count=$(echo "$output" | jq '.waves | length')
  assert_equal "$wave_count" "1"

  local tm
  tm=$(echo "$output" | jq -r '.team_mode')
  assert_equal "$tm" "task"

  local dept gate ss
  dept=$(echo "$output" | jq -r '.waves[0].depts[0].dept')
  gate=$(echo "$output" | jq -r '.waves[0].gate')
  ss=$(echo "$output" | jq -r '.waves[0].depts[0].spawn_strategy')

  assert_equal "$dept" "backend"
  assert_equal "$gate" "all-depts-complete"
  assert_equal "$ss" "task"
}

# --- JSON validity ---

@test "output is valid JSON" {
  mk_config true true true parallel
  run_orchestrate
  assert_success

  # jq . must succeed (valid JSON)
  echo "$output" | jq . >/dev/null 2>&1
  assert_equal "$?" "0"

  # waves is array
  local waves_type
  waves_type=$(echo "$output" | jq -r '.waves | type')
  assert_equal "$waves_type" "array"

  # timeout_minutes is number
  local timeout_type
  timeout_type=$(echo "$output" | jq -r '.timeout_minutes | type')
  assert_equal "$timeout_type" "number"

  # team_mode is string
  local tm_type
  tm_type=$(echo "$output" | jq -r '.team_mode | type')
  assert_equal "$tm_type" "string"

  # depts items are objects (not strings)
  local dept_type
  dept_type=$(echo "$output" | jq -r '.waves[0].depts[0] | type')
  assert_equal "$dept_type" "object"
}

# --- Missing config defaults ---

@test "missing config: defaults to backend-only wave" {
  run_orchestrate "$TEST_WORKDIR/nonexistent.json" "$TEST_WORKDIR/phase"
  assert_success

  local wave_count dept tm ss
  wave_count=$(echo "$output" | jq '.waves | length')
  dept=$(echo "$output" | jq -r '.waves[0].depts[0].dept')
  tm=$(echo "$output" | jq -r '.team_mode')
  ss=$(echo "$output" | jq -r '.waves[0].depts[0].spawn_strategy')

  assert_equal "$wave_count" "1"
  assert_equal "$dept" "backend"
  assert_equal "$tm" "task"
  assert_equal "$ss" "task"
}

# --- Missing args ---

@test "missing args: exits 1 with usage" {
  run bash "$SUT"
  assert_failure
  assert_output --partial "Usage"
}

# --- Parallel UX-only (no FE) ---

@test "parallel UX-only (no FE): two waves" {
  mk_config true false true parallel
  run_orchestrate
  assert_success

  local wave_count
  wave_count=$(echo "$output" | jq '.waves | length')
  assert_equal "$wave_count" "2"

  local tm
  tm=$(echo "$output" | jq -r '.team_mode')
  assert_equal "$tm" "task"

  local w0_dept w1_dept w0_ss
  w0_dept=$(echo "$output" | jq -r '.waves[0].depts[0].dept')
  w1_dept=$(echo "$output" | jq -r '.waves[1].depts[0].dept')
  w0_ss=$(echo "$output" | jq -r '.waves[0].depts[0].spawn_strategy')

  assert_equal "$w0_dept" "uiux"
  assert_equal "$w1_dept" "backend"
  assert_equal "$w0_ss" "task"
}

# --- Teammate mode tests ---

@test "teammate mode parallel 3-dept: spawnTeam strategy with team names" {
  mk_config true true true parallel teammate true
  export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
  run_orchestrate
  assert_success

  local tm ss tn
  tm=$(echo "$output" | jq -r '.team_mode')
  assert_equal "$tm" "teammate"

  ss=$(echo "$output" | jq -r '.waves[0].depts[0].spawn_strategy')
  assert_equal "$ss" "spawnTeam"

  tn=$(echo "$output" | jq -r '.waves[0].depts[0].team_name')
  assert_equal "$tn" "yolo-uiux"

  local w1_be_ss w1_be_tn
  w1_be_ss=$(echo "$output" | jq -r '[.waves[1].depts[] | select(.dept=="backend")] | .[0].spawn_strategy')
  w1_be_tn=$(echo "$output" | jq -r '[.waves[1].depts[] | select(.dept=="backend")] | .[0].team_name')
  assert_equal "$w1_be_ss" "spawnTeam"
  assert_equal "$w1_be_tn" "yolo-backend"
}

@test "teammate mode backend-only: spawnTeam strategy" {
  mk_config true false false backend_only teammate true
  export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
  run_orchestrate
  assert_success

  local tm ss tn
  tm=$(echo "$output" | jq -r '.team_mode')
  assert_equal "$tm" "teammate"

  ss=$(echo "$output" | jq -r '.waves[0].depts[0].spawn_strategy')
  assert_equal "$ss" "spawnTeam"

  tn=$(echo "$output" | jq -r '.waves[0].depts[0].team_name')
  assert_equal "$tn" "yolo-backend"
}

@test "teammate requested but env var missing: falls back to task" {
  mk_config true true true parallel teammate true
  unset CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS
  run_orchestrate
  assert_success

  local tm ss
  tm=$(echo "$output" | jq -r '.team_mode')
  assert_equal "$tm" "task"

  ss=$(echo "$output" | jq -r '.waves[0].depts[0].spawn_strategy')
  assert_equal "$ss" "task"
}

@test "task mode: no team_name field in depts" {
  mk_config true false false backend_only
  run_orchestrate
  assert_success

  local tn
  tn=$(echo "$output" | jq -r '.waves[0].depts[0].team_name // "absent"')
  assert_equal "$tn" "absent"
}
