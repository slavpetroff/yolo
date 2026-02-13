#!/usr/bin/env bats
# task-verify-enforcement.bats — Edge cases for task-verify.sh commit verification

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  load '../test_helper/mock_stdin'
  mk_test_workdir
  mk_planning_dir
  mk_git_repo
}

@test "blocks completion with zero commits in 2-hour window" {
  # We need ALL commits to be older than 2 hours. mk_git_repo creates a recent
  # initial commit, so we amend it to be old, then add another old commit.
  cd "$TEST_WORKDIR"
  local old_ts
  old_ts=$(date -v-3H +"%Y-%m-%dT%H:%M:%S" 2>/dev/null) || \
  old_ts=$(date -d "-3 hours" +"%Y-%m-%dT%H:%M:%S" 2>/dev/null)
  GIT_COMMITTER_DATE="$old_ts" GIT_AUTHOR_DATE="$old_ts" \
    git commit --amend --allow-empty -q -m "chore(init): initial commit"
  mk_recent_commit "chore(old): ancient work" 10800

  run_with_json '{"task_subject":"Implement new feature"}' "$SCRIPTS_DIR/task-verify.sh"
  assert_failure 2
  assert_output --partial "over 2 hours"
}

@test "blocks when commit subject has zero keyword overlap with task" {
  # Recent commit exists but has completely unrelated words
  mk_recent_commit "chore(99-99): refactor database migrations"

  run_with_json '{"task_subject":"Implement authentication module security"}' "$SCRIPTS_DIR/task-verify.sh"
  assert_failure 2
  assert_output --partial "matched 0"
}

@test "allows when 2+ keywords match recent commit" {
  mk_recent_commit "feat(01-01): implement authentication module"

  run_with_json '{"task_subject":"Implement authentication module for users"}' "$SCRIPTS_DIR/task-verify.sh"
  assert_success
}

@test "allows with empty task subject (fail-open)" {
  mk_recent_commit "feat(01-01): something"

  run_with_json '{"task_subject":""}' "$SCRIPTS_DIR/task-verify.sh"
  assert_success
}

@test "handles very long task subjects (100+ words)" {
  mk_recent_commit "feat(01-01): implement comprehensive authentication"

  # Build a 100+ word task subject that includes matching keywords
  local long_subject="Implement comprehensive authentication"
  for i in $(seq 1 100); do
    long_subject="$long_subject word${i}"
  done

  run_with_json "{\"task_subject\":\"$long_subject\"}" "$SCRIPTS_DIR/task-verify.sh"
  # Should succeed: "implement", "comprehensive", "authentication" all match
  # The script extracts max 8 keywords and needs MIN_MATCHES=2
  assert_success
}

@test "handles special characters in task subject (quotes, pipes, semicolons)" {
  mk_recent_commit "feat(01-01): implement authentication validation"

  # Task subject with special characters — the script uses tr to split on non-alnum,
  # so special chars become delimiters and keywords are still extracted
  run bash -c 'printf "{\"task_subject\":\"Implement authentication; validate | check \\\"security\\\"\"}" | bash '"'$SCRIPTS_DIR/task-verify.sh'"
  assert_success
}
