#!/usr/bin/env bats
# task-verify.bats — Unit tests for scripts/task-verify.sh
# PostToolUse[TaskUpdate] hook (task-verify): exit 2 = block, exit 0 = allow

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  load '../test_helper/mock_stdin'
  mk_test_workdir
  mk_planning_dir
  mk_git_repo
  SUT="$SCRIPTS_DIR/task-verify.sh"
}

# --- Fail-open on edge cases ---

@test "exits 0 on empty stdin" {
  mk_recent_commit "feat(01-01): some work"
  run bash -c "echo -n '' | bash '$SUT'"
  assert_success
}

@test "exits 0 when task_subject is empty" {
  mk_recent_commit "feat(01-01): some work"
  run bash -c "echo '{\"task_subject\":\"\"}' | bash '$SUT'"
  assert_success
}

# --- Blocks: no recent commits ---

@test "blocks when only old commits exist" {
  mk_recent_commit "feat(01-01): implement authentication module" 7300
  run bash -c "echo '{\"task_subject\":\"Implement authentication module\"}' | bash '$SUT'"
  assert_failure 2
}

# --- Blocks: no keyword overlap ---

@test "blocks when recent commits have no keyword overlap with task" {
  mk_recent_commit "chore(01-01): update dependencies"
  run bash -c "echo '{\"task_subject\":\"Implement authentication module\"}' | bash '$SUT'"
  assert_failure 2
}

# --- Allows: sufficient keyword matches ---

@test "allows when >= 2 keywords match with > 2 keywords in subject" {
  mk_recent_commit "feat(01-01): implement authentication module"
  run bash -c "echo '{\"task_subject\":\"Implement authentication module\"}' | bash '$SUT'"
  assert_success
}

@test "allows when >= 1 keyword matches with <= 2 keywords in subject" {
  mk_recent_commit "feat(01-01): add validation logic"
  run bash -c "echo '{\"task_subject\":\"Add validation\"}' | bash '$SUT'"
  assert_success
}

# --- Keyword extraction: only words > 3 chars ---

@test "ignores short words and fails open when no keywords extracted" {
  # "Set up the new API" -> "only" words <= 3 chars -> no keywords -> fail-open
  mk_recent_commit "feat(01-01): configure the endpoint"
  run bash -c "echo '{\"task_subject\":\"Set up the new API\"}' | bash '$SUT'"
  assert_success
}

# --- Case insensitive matching ---

@test "matches keywords case-insensitively" {
  mk_recent_commit "feat(01-01): implement Authentication Module"
  run bash -c "echo '{\"task_subject\":\"IMPLEMENT AUTHENTICATION MODULE\"}' | bash '$SUT'"
  assert_success
}

# --- Old commits (> 2 hours) do not count ---

@test "blocks when only old commits exist even with keyword overlap" {
  mk_recent_commit "feat(01-01): implement authentication module" 7300
  run bash -c "echo '{\"task_subject\":\"Implement authentication module\"}' | bash '$SUT'"
  assert_failure 2
}

# --- Nested task JSON format (task.subject) ---

@test "reads task_subject from nested task.subject path" {
  mk_recent_commit "feat(01-01): implement authentication module"
  run bash -c "echo '{\"task\":{\"subject\":\"Implement authentication module\"}}' | bash '$SUT'"
  assert_success
}
