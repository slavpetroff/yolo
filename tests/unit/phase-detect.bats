#!/usr/bin/env bats
# phase-detect.bats — Unit tests for scripts/phase-detect.sh
# Phase detection + config loading. Outputs key=value pairs on stdout.

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  load '../test_helper/mock_stdin'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/phase-detect.sh"
}

# Helper: create phase dir with exact file counts (avoids macOS seq 1 0 bug)
mk_phase_exact() {
  local num="$1" slug="$2" plans="$3" summaries="$4"
  local dir="$TEST_WORKDIR/.yolo-planning/phases/$(printf '%02d' "$num")-${slug}"
  mkdir -p "$dir"
  local i
  for ((i = 1; i <= plans; i++)); do
    cp "$FIXTURES_DIR/plans/valid-plan.jsonl" "$dir/$(printf '%02d-%02d' "$num" "$i").plan.jsonl"
  done
  for ((i = 1; i <= summaries; i++)); do
    cp "$FIXTURES_DIR/summaries/valid-summary.jsonl" "$dir/$(printf '%02d-%02d' "$num" "$i").summary.jsonl"
  done
  echo "$dir"
}

# Helper: run phase-detect from test workdir
run_detect() {
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT'"
}

# Helper: extract a key from output
get_val() {
  local key="$1"
  echo "$output" | grep "^${key}=" | head -1 | sed "s/^${key}=//"
}

# --- No planning directory ---

@test "reports planning_dir_exists=false when no .yolo-planning" {
  run_detect
  assert_success
  assert_line "planning_dir_exists=false"
}

@test "reports project_exists=false when no .yolo-planning" {
  run_detect
  assert_success
  assert_line "project_exists=false"
}

@test "exits 0 when no planning directory" {
  run_detect
  assert_success
}

# --- Planning dir but no PROJECT.md ---

@test "reports project_exists=false when planning dir exists but no PROJECT.md" {
  mkdir -p "$TEST_WORKDIR/.yolo-planning/phases"
  run_detect
  assert_success
  assert_line "planning_dir_exists=true"
  assert_line "project_exists=false"
}

# --- Finds next unplanned phase ---

@test "finds next unplanned phase (needs_plan_and_execute)" {
  mk_planning_dir
  mk_phase_exact 1 "setup" 0 0
  run_detect
  assert_success
  assert_line "next_phase_state=needs_plan_and_execute"
  assert_line "next_phase_slug=01-setup"
}

# --- Finds next unexecuted phase ---

@test "finds next unexecuted phase (needs_execute)" {
  mk_planning_dir
  mk_phase_exact 1 "setup" 2 1
  run_detect
  assert_success
  assert_line "next_phase_state=needs_execute"
  assert_line "next_phase_plans=2"
  assert_line "next_phase_summaries=1"
}

# --- Reports all_done ---

@test "reports all_done when all phases have matching plans and summaries" {
  mk_planning_dir
  mk_phase_exact 1 "setup" 1 1
  mk_phase_exact 2 "build" 2 2
  run_detect
  assert_success
  assert_line "next_phase_state=all_done"
}

# --- Reads config values ---

@test "reads config values from config.json" {
  mk_planning_dir
  cp "$FIXTURES_DIR/config/quality-config.json" "$TEST_WORKDIR/.yolo-planning/config.json"
  run_detect
  assert_success
  assert_line "config_effort=thorough"
  assert_line "config_agent_teams=true"
  assert_line "config_max_tasks_per_plan=8"
  assert_line "config_security_audit=true"
  assert_line "config_approval_qa_fail=true"
}

# --- Uses defaults when no config ---

@test "uses default config values when config.json is missing" {
  mkdir -p "$TEST_WORKDIR/.yolo-planning/phases"
  # No config.json
  run_detect
  assert_success
  assert_line "config_effort=balanced"
  assert_line "config_autonomy=standard"
  assert_line "config_auto_commit=true"
  assert_line "config_agent_teams=false"
  assert_line "config_max_tasks_per_plan=5"
}

# --- Detects brownfield ---

@test "detects brownfield when git-tracked files exist" {
  mk_planning_dir
  mk_git_repo
  run_detect
  assert_success
  assert_line "brownfield=true"
}

@test "reports brownfield=false when no git-tracked files" {
  mk_planning_dir
  run_detect
  assert_success
  assert_line "brownfield=false"
}

# --- Reads state.json ---

@test "reads workflow state from state.json" {
  mk_planning_dir
  mk_state_json 1 2 "executing"
  run_detect
  assert_success
  assert_line "current_phase=1"
  assert_line "total_phases=2"
  assert_line "workflow_status=executing"
}

# --- Resolves active milestone ---

@test "resolves active milestone from ACTIVE file" {
  mk_planning_dir
  mkdir -p "$TEST_WORKDIR/.yolo-planning/milestones/my-milestone/phases"
  echo "my-milestone" > "$TEST_WORKDIR/.yolo-planning/ACTIVE"
  run_detect
  assert_success
  assert_line "active_milestone=my-milestone"
}

# --- Handles missing milestone dir ---

@test "handles missing milestone directory gracefully" {
  mk_planning_dir
  echo "nonexistent-milestone" > "$TEST_WORKDIR/.yolo-planning/ACTIVE"
  run_detect
  assert_success
  assert_line "active_milestone_error=true"
  assert_line "active_milestone=none"
}

# --- Counts JSONL and legacy MD plans ---

@test "counts both JSONL and legacy MD plan files" {
  mk_planning_dir
  local dir
  dir=$(mk_phase_exact 1 "setup" 1 0)
  # Add a legacy PLAN.md file too
  touch "$dir/01-02-PLAN.md"
  run_detect
  assert_success
  assert_line "next_phase_plans=2"
}

# --- Reports execution state ---

@test "reports execution state from .execution-state.json" {
  mk_planning_dir
  echo '{"status":"in_progress"}' > "$TEST_WORKDIR/.yolo-planning/.execution-state.json"
  run_detect
  assert_success
  assert_line "execution_state=in_progress"
}
