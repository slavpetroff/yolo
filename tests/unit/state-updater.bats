#!/usr/bin/env bats
# state-updater.bats — Unit tests for scripts/state-updater.sh
# PostToolUse on Write|Edit: updates STATE.md, state.json, ROADMAP.md, .execution-state.json

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  load '../test_helper/mock_stdin'
  mk_test_workdir
  mk_planning_dir
  SUT="$SCRIPTS_DIR/state-updater.sh"
}

# Helper: run state-updater with JSON input from TEST_WORKDIR
run_updater() {
  local file_path="$1"
  run bash -c "cd '$TEST_WORKDIR' && echo '{\"tool_input\":{\"file_path\":\"$file_path\"}}' | bash '$SUT'"
}

# Helper: create phase dir with only plan files (no summaries)
# macOS seq counts down when end < start, so mk_phase with summaries=0 is unreliable
mk_phase_plans_only() {
  local num="$1" slug="$2" plans="$3"
  local dir="$TEST_WORKDIR/.yolo-planning/phases/$(printf '%02d' "$num")-${slug}"
  mkdir -p "$dir"
  local i=1
  while [ "$i" -le "$plans" ]; do
    cp "$FIXTURES_DIR/plans/valid-plan.jsonl" "$dir/$(printf '%02d-%02d' "$num" "$i").plan.jsonl"
    i=$((i + 1))
  done
  echo "$dir"
}

# Helper: create phase dir with plan AND summary files
mk_phase_complete() {
  local num="$1" slug="$2" plans="$3"
  local dir="$TEST_WORKDIR/.yolo-planning/phases/$(printf '%02d' "$num")-${slug}"
  mkdir -p "$dir"
  local i=1
  while [ "$i" -le "$plans" ]; do
    cp "$FIXTURES_DIR/plans/valid-plan.jsonl" "$dir/$(printf '%02d-%02d' "$num" "$i").plan.jsonl"
    cp "$FIXTURES_DIR/summaries/valid-summary.jsonl" "$dir/$(printf '%02d-%02d' "$num" "$i").summary.jsonl"
    i=$((i + 1))
  done
  echo "$dir"
}

# --- Plan trigger: updates STATE.md plan count ---

@test "plan write updates STATE.md plan count" {
  mk_state_md 1 2
  local dir
  dir=$(mk_phase_plans_only 1 setup 1)

  local plan_file="$dir/01-01.plan.jsonl"
  run_updater "$plan_file"
  assert_success

  run grep "^Plans:" "$TEST_WORKDIR/.yolo-planning/STATE.md"
  assert_output "Plans: 0/1"
}

# --- Plan trigger: updates state.json ---

@test "plan write updates state.json phase and status" {
  mk_state_md 1 2
  mk_state_json 1 2 "planning"
  local dir
  dir=$(mk_phase_plans_only 1 setup 1)

  local plan_file="$dir/01-01.plan.jsonl"
  run_updater "$plan_file"
  assert_success

  run jq -r '.st' "$TEST_WORKDIR/.yolo-planning/state.json"
  assert_output "executing"
}

# --- Plan trigger: activates ready -> active ---

@test "plan write changes status from ready to active" {
  mk_state_md 1 2
  sed -i.bak 's/^Status: active/Status: ready/' "$TEST_WORKDIR/.yolo-planning/STATE.md"

  local dir
  dir=$(mk_phase_plans_only 1 setup 1)

  local plan_file="$dir/01-01.plan.jsonl"
  run_updater "$plan_file"
  assert_success

  run grep "^Status:" "$TEST_WORKDIR/.yolo-planning/STATE.md"
  assert_output "Status: active"
}

# --- Summary trigger: updates execution state ---

@test "summary write updates execution state status" {
  mk_state_md 1 2
  mk_state_json 1 2 "executing"
  mk_execution_state "01" "01-01"

  local dir
  dir=$(mk_phase_plans_only 1 setup 1)

  local summary_file="$dir/01-01.summary.jsonl"
  echo '{"p":"01","n":"01-01","s":"complete","fm":["src/foo.ts"]}' > "$summary_file"

  run_updater "$summary_file"
  assert_success

  run jq -r '.phases["01"]["01-01"].status' "$TEST_WORKDIR/.yolo-planning/.execution-state.json"
  assert_output "complete"
}

# --- Summary trigger: updates STATE.md progress ---

@test "summary write updates STATE.md progress" {
  mk_state_md 1 2
  mk_state_json 1 2 "executing"
  mk_execution_state "01" "01-01"

  local dir
  dir=$(mk_phase_plans_only 1 setup 1)

  local summary_file="$dir/01-01.summary.jsonl"
  echo '{"p":"01","n":"01-01","s":"complete","fm":["src/foo.ts"]}' > "$summary_file"

  run_updater "$summary_file"
  assert_success

  run grep "^Plans:" "$TEST_WORKDIR/.yolo-planning/STATE.md"
  assert_output "Plans: 1/1"
}

# --- Advances phase when all plans have summaries ---

@test "advances phase when current phase is complete" {
  mk_state_md 1 2
  mk_state_json 1 2 "executing"
  mk_execution_state "01" "01-01"

  # Phase 1: 1 plan + 1 summary (complete)
  local dir1
  dir1=$(mk_phase_complete 1 setup 1)
  # Overwrite with proper content
  echo '{"p":"01","n":"01-01","s":"complete","fm":["src/foo.ts"]}' > "$dir1/01-01.summary.jsonl"

  # Phase 2: 1 plan, 0 summaries (next phase)
  mk_phase_plans_only 2 build 1

  run_updater "$dir1/01-01.summary.jsonl"
  assert_success

  run grep "^Phase:" "$TEST_WORKDIR/.yolo-planning/STATE.md"
  assert_output --partial "2 of 2"
}

# --- Sets complete when all phases done ---

@test "sets status complete when all phases done" {
  mk_state_md 1 1
  mk_state_json 1 1 "executing"
  mk_execution_state "01" "01-01"

  local dir1
  dir1=$(mk_phase_complete 1 setup 1)
  echo '{"p":"01","n":"01-01","s":"complete","fm":["src/foo.ts"]}' > "$dir1/01-01.summary.jsonl"

  run_updater "$dir1/01-01.summary.jsonl"
  assert_success

  run grep "^Status:" "$TEST_WORKDIR/.yolo-planning/STATE.md"
  assert_output "Status: complete"
}

@test "sets state.json to complete when all phases done" {
  mk_state_md 1 1
  mk_state_json 1 1 "executing"
  mk_execution_state "01" "01-01"

  local dir1
  dir1=$(mk_phase_complete 1 setup 1)
  echo '{"p":"01","n":"01-01","s":"complete","fm":["src/foo.ts"]}' > "$dir1/01-01.summary.jsonl"

  run_updater "$dir1/01-01.summary.jsonl"
  assert_success

  run jq -r '.st' "$TEST_WORKDIR/.yolo-planning/state.json"
  assert_output "complete"
}

# --- Fail-open on missing STATE.md ---

@test "fail-open when STATE.md missing" {
  rm -f "$TEST_WORKDIR/.yolo-planning/STATE.md"
  local dir
  dir=$(mk_phase_plans_only 1 setup 1)

  local plan_file="$dir/01-01.plan.jsonl"
  run_updater "$plan_file"
  assert_success
}

# --- Fail-open on missing state.json ---

@test "fail-open when state.json missing" {
  mk_state_md 1 2
  local dir
  dir=$(mk_phase_plans_only 1 setup 1)

  local plan_file="$dir/01-01.plan.jsonl"
  run_updater "$plan_file"
  assert_success
}

# --- Git auto-commit ---

@test "auto-commits state artifacts after plan write" {
  mk_git_repo
  mk_planning_dir
  mk_state_md 1 2
  mk_state_json 1 2 "planning"

  local dir
  dir=$(mk_phase_plans_only 1 setup 1)

  # Stage planning dir so git tracks it
  git -C "$TEST_WORKDIR" add .yolo-planning/ && git -C "$TEST_WORKDIR" commit -q -m "chore(init): add planning dir"

  local plan_file="$dir/01-01.plan.jsonl"
  run_updater "$plan_file"
  assert_success

  # Verify a state commit was made
  run git -C "$TEST_WORKDIR" log --oneline -1
  assert_output --partial "chore(state):"
}

# --- Non-matching file path is ignored ---

@test "exits 0 for non-plan non-summary file" {
  run_updater "src/foo.ts"
  assert_success
}
