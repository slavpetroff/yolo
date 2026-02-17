#!/usr/bin/env bats
# git-commit-serialized.bats — Behavioral tests for scripts/git-commit-serialized.sh
# flock-based serialized git commit wrapper with exponential backoff
# RED phase: script does not exist yet, all tests must FAIL

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/git-commit-serialized.sh"

  # Create a git repo for commit tests
  mk_git_repo
}

# --- Existence and executability ---

@test "git-commit-serialized.sh exists and is executable" {
  assert_file_executable "$SUT"
}

# --- Happy path: creates commit when no contention ---

@test "creates commit successfully with staged changes" {
  echo "new content" > "$TEST_WORKDIR/test-file.txt"
  git -C "$TEST_WORKDIR" add test-file.txt

  run bash "$SUT" -m "feat(test): add test file"
  assert_success
}

# --- Outputs commit hash on stdout ---

@test "outputs short commit hash on stdout" {
  echo "new content" > "$TEST_WORKDIR/test-file.txt"
  git -C "$TEST_WORKDIR" add test-file.txt

  run bash "$SUT" -m "feat(test): add test file"
  assert_success

  # Output should be a short hex hash (7+ chars)
  local hash_pattern='^[0-9a-f]{7,}$'
  [[ "$output" =~ $hash_pattern ]]
}

# --- Lock file usage ---

@test "lock file directory cleaned up after successful commit" {
  echo "new content" > "$TEST_WORKDIR/test-file.txt"
  git -C "$TEST_WORKDIR" add test-file.txt

  run bash "$SUT" -m "feat(test): add test file"
  assert_success

  # After commit, the mkdir-based lock directory should be removed
  local lock_dir="$TEST_WORKDIR/.git/yolo-commit.lock.d"
  [ ! -d "$lock_dir" ]
}

# --- Failure: nothing staged outputs error message ---

@test "exits non-zero with error when nothing staged" {
  # No files staged, commit should fail
  run bash "$SUT" -m "feat(test): empty commit"
  assert_failure
  # Should output an error message, not "No such file or directory"
  refute_output --partial "No such file or directory"
}

# --- Passes through git commit arguments ---

@test "passes arguments through to git commit" {
  echo "new content" > "$TEST_WORKDIR/test-file.txt"
  git -C "$TEST_WORKDIR" add test-file.txt

  run bash "$SUT" -m "test(args): verify passthrough"
  assert_success

  # Verify the commit message was used
  local last_msg
  last_msg=$(git -C "$TEST_WORKDIR" log -1 --format=%s)
  [ "$last_msg" = "test(args): verify passthrough" ]
}
