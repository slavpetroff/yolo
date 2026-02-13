#!/usr/bin/env bats
# prompt-preflight.bats — Unit tests for scripts/prompt-preflight.sh
# UserPromptSubmit hook: creates/removes .yolo-session marker based on /yolo: commands

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  load '../test_helper/mock_stdin'
  mk_test_workdir
  mk_planning_dir
  SUT="$SCRIPTS_DIR/prompt-preflight.sh"
}

# --- Session marker creation/removal ---

@test "creates .yolo-session marker for /yolo: command with GSD isolation" {
  mk_gsd_isolation

  run bash -c "cd '$TEST_WORKDIR' && echo '{\"prompt\":\"/yolo:status\"}' | bash '$SUT'"
  assert_success
  assert_file_exists "$TEST_WORKDIR/.yolo-planning/.yolo-session"
}

@test "removes .yolo-session marker for non-yolo command with GSD isolation" {
  mk_gsd_isolation
  mk_yolo_session
  assert_file_exists "$TEST_WORKDIR/.yolo-planning/.yolo-session"

  run bash -c "cd '$TEST_WORKDIR' && echo '{\"prompt\":\"help me refactor\"}' | bash '$SUT'"
  assert_success
  assert_file_not_exists "$TEST_WORKDIR/.yolo-planning/.yolo-session"
}

@test "does not create .yolo-session without GSD isolation flag" {
  # No .gsd-isolation file present
  run bash -c "cd '$TEST_WORKDIR' && echo '{\"prompt\":\"/yolo:go\"}' | bash '$SUT'"
  assert_success
  assert_file_not_exists "$TEST_WORKDIR/.yolo-planning/.yolo-session"
}

# --- Execute warning ---

@test "warns when --execute with no plans for current phase" {
  mk_state_json 1 2 "executing"
  # Create phase dir but with no plans
  mkdir -p "$TEST_WORKDIR/.yolo-planning/phases/01"

  run bash -c "cd '$TEST_WORKDIR' && echo '{\"prompt\":\"/yolo:go --execute\"}' | bash '$SUT'"
  assert_success
  assert_output --partial "hookSpecificOutput"
  assert_output --partial "No plans for phase"
}

@test "no warning when --execute with plans present" {
  mk_state_json 1 2 "executing"
  # Script resolves phase dir as phases/<padded-num> (no slug), so create at that path
  local dir="$TEST_WORKDIR/.yolo-planning/phases/01"
  mkdir -p "$dir"
  cp "$FIXTURES_DIR/plans/valid-plan.jsonl" "$dir/01-01.plan.jsonl"

  run bash -c "cd '$TEST_WORKDIR' && echo '{\"prompt\":\"/yolo:go --execute\"}' | bash '$SUT'"
  assert_success
  refute_output --partial "No plans for phase"
}

# --- Archive warning ---

@test "warns when --archive with incomplete phases in STATE.md" {
  mk_state_md 1 2
  # Add incomplete status entries
  echo "status: incomplete" >> "$TEST_WORKDIR/.yolo-planning/STATE.md"

  run bash -c "cd '$TEST_WORKDIR' && echo '{\"prompt\":\"/yolo:go --archive\"}' | bash '$SUT'"
  assert_success
  assert_output --partial "hookSpecificOutput"
  assert_output --partial "incomplete phase"
}

# --- Always exits 0 ---

@test "exits 0 when .yolo-planning dir is missing" {
  rm -rf "$TEST_WORKDIR/.yolo-planning"
  run bash -c "cd '$TEST_WORKDIR' && echo '{\"prompt\":\"/yolo:go\"}' | bash '$SUT'"
  assert_success
}

@test "exits 0 on empty prompt" {
  run bash -c "cd '$TEST_WORKDIR' && echo '{\"prompt\":\"\"}' | bash '$SUT'"
  assert_success
}
