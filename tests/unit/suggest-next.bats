#!/usr/bin/env bats
# suggest-next.bats — Unit tests for scripts/suggest-next.sh
# Next action suggestion based on project state.
# Usage: suggest-next.sh <command> [result]

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  load '../test_helper/mock_stdin'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/suggest-next.sh"
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

# Helper: run suggest-next from test workdir
run_suggest() {
  local cmd="$1"
  local result="${2:-}"
  if [ -n "$result" ]; then
    run bash -c "cd '$TEST_WORKDIR' && bash '$SUT' '$cmd' '$result'"
  else
    run bash -c "cd '$TEST_WORKDIR' && bash '$SUT' '$cmd'"
  fi
}

# --- After init ---

@test "after init: suggests /yolo:go" {
  run_suggest init
  assert_success
  assert_output --partial "/yolo:go"
  assert_output --partial "Define your project"
}

# --- After vibe with no project (fallback) ---

@test "fallback: suggests /yolo:go when no project exists" {
  run_suggest help
  assert_success
  assert_output --partial "/yolo:go"
}

# --- After plan ---

@test "after plan: suggests execute" {
  mk_planning_dir
  echo "real project" > "$TEST_WORKDIR/.yolo-planning/PROJECT.md"
  mk_phase_exact 1 "setup" 2 0
  run_suggest plan
  assert_success
  assert_output --partial "/yolo:go"
  assert_output --partial "Execute"
}

# --- After QA pass ---

@test "after qa pass with remaining phases: suggests continue" {
  mk_planning_dir
  echo "real project" > "$TEST_WORKDIR/.yolo-planning/PROJECT.md"
  mk_phase_exact 1 "setup" 1 1
  mk_phase_exact 2 "build" 0 0
  run_suggest qa pass
  assert_success
  assert_output --partial "/yolo:go"
}

# --- After QA fail ---

@test "after qa fail: suggests /yolo:fix" {
  mk_planning_dir
  echo "real project" > "$TEST_WORKDIR/.yolo-planning/PROJECT.md"
  mk_phase_exact 1 "setup" 1 1
  run_suggest qa fail
  assert_success
  assert_output --partial "/yolo:fix"
}

# --- After fix ---

@test "after fix: suggests /yolo:qa to verify" {
  mk_planning_dir
  echo "real project" > "$TEST_WORKDIR/.yolo-planning/PROJECT.md"
  run_suggest fix
  assert_success
  assert_output --partial "/yolo:qa"
  assert_output --partial "Verify the fix"
}

# --- After debug ---

@test "after debug: suggests /yolo:fix" {
  run_suggest debug
  assert_success
  assert_output --partial "/yolo:fix"
  assert_output --partial "Apply the fix"
}

# --- All done with zero deviations ---

@test "all done zero deviations: suggests archive" {
  mk_planning_dir
  echo "real project" > "$TEST_WORKDIR/.yolo-planning/PROJECT.md"
  mk_phase_exact 1 "setup" 1 1
  mk_phase_exact 2 "build" 1 1
  run_suggest vibe
  assert_success
  assert_output --partial "--archive"
  assert_output --partial "zero deviations"
}

# --- After archive ---

@test "after archive: suggests start new work" {
  run_suggest archive
  assert_success
  assert_output --partial "/yolo:go"
  assert_output --partial "Start new work"
}

# --- After config with project ---

@test "after config with existing project: suggests /yolo:status" {
  mk_planning_dir
  echo "real project" > "$TEST_WORKDIR/.yolo-planning/PROJECT.md"
  run_suggest config
  assert_success
  assert_output --partial "/yolo:status"
}

# --- Output always starts with Next Up ---

@test "output always starts with Next Up header" {
  run_suggest init
  assert_success
  assert_line --index 0 --partial "Next Up"
}

# --- After status with unbuilt phase ---

@test "after status with unbuilt phases: suggests continue" {
  mk_planning_dir
  echo "real project" > "$TEST_WORKDIR/.yolo-planning/PROJECT.md"
  mk_phase_exact 1 "setup" 1 1
  mk_phase_exact 2 "build" 1 0
  run_suggest status
  assert_success
  assert_output --partial "/yolo:go"
  assert_output --partial "Continue"
}
