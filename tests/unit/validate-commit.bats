#!/usr/bin/env bats
# validate-commit.bats — Unit tests for scripts/validate-commit.sh
# PostToolUse on Bash, non-blocking (always exit 0)

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  load '../test_helper/mock_stdin'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/validate-commit.sh"
}

# --- Always exits 0 ---

@test "exits 0 on valid conventional commit" {
  run bash -c "echo '{\"tool_input\":{\"command\":\"git commit -m \\\"feat(auth): add login flow\\\"\"}}' | bash '$SUT'"
  assert_success
  refute_output --partial "hookSpecificOutput"
}

@test "exits 0 on non-git-commit command" {
  run bash -c "echo '{\"tool_input\":{\"command\":\"ls -la\"}}' | bash '$SUT'"
  assert_success
  refute_output --partial "hookSpecificOutput"
}

@test "exits 0 on empty stdin" {
  run bash -c "echo -n '' | bash '$SUT'"
  assert_success
}

# --- Format validation ---

@test "reports invalid commit format missing scope" {
  run bash -c "echo '{\"tool_input\":{\"command\":\"git commit -m \\\"feat: missing scope\\\"\"}}' | bash '$SUT'"
  assert_success
  assert_output --partial "hookSpecificOutput"
  assert_output --partial "does not match format"
}

@test "reports invalid commit type" {
  run bash -c "echo '{\"tool_input\":{\"command\":\"git commit -m \\\"update(scope): bad type\\\"\"}}' | bash '$SUT'"
  assert_success
  assert_output --partial "hookSpecificOutput"
  assert_output --partial "does not match format"
}

@test "accepts all valid commit types" {
  for type in feat fix test refactor perf docs style chore; do
    run bash -c "echo '{\"tool_input\":{\"command\":\"git commit -m \\\"${type}(scope): description\\\"\"}}' | bash '$SUT'"
    assert_success
    refute_output --partial "hookSpecificOutput"
  done
}

# --- Heredoc skip ---

@test "skips heredoc-style commits" {
  run bash -c "printf '%s' '{\"tool_input\":{\"command\":\"git commit -m \\\"\\$(cat <<EOF\\nsome msg\\nEOF\\n)\\\"\"}}' | bash '$SUT'"
  assert_success
  refute_output --partial "hookSpecificOutput"
}

# --- Edge cases ---

@test "exits 0 when commit message cannot be extracted" {
  run bash -c "echo '{\"tool_input\":{\"command\":\"git commit --amend\"}}' | bash '$SUT'"
  assert_success
  refute_output --partial "hookSpecificOutput"
}
