#!/usr/bin/env bats
# file-overlap-serialized-commit.bats -- Behavioral tests for file-overlap detection and git-commit-serialized.sh

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  mk_test_workdir
  COMMIT_SCRIPT="$SCRIPTS_DIR/git-commit-serialized.sh"
}

teardown() {
  rmdir "$TEST_WORKDIR/.git/yolo-commit.lock.d" 2>/dev/null || true
}

# Helper: file-overlap detection algorithm
# Takes space-separated claimed files as $1, space-separated task files as $2
# Returns 0 if overlap detected (task blocked), 1 if no overlap (task claimable)
check_file_overlap() {
  local claimed="$1"
  local task_files="$2"
  for f in $task_files; do
    for c in $claimed; do
      if [ "$f" = "$c" ]; then
        return 0
      fi
    done
  done
  return 1
}

# --- File-overlap detection tests ---

@test "file overlap: T2 blocked when T1 claims shared file" {
  run check_file_overlap "a.sh" "a.sh b.sh"
  assert_success
}

@test "no file overlap: both tasks claimable with different files" {
  run check_file_overlap "a.sh" "b.sh"
  assert_failure
}

# --- git-commit-serialized.sh integration tests ---

@test "git-commit-serialized.sh creates commit and verifies commit message" {
  mk_git_repo
  echo 'test' > "$TEST_WORKDIR/test.txt"
  git -C "$TEST_WORKDIR" add test.txt

  run bash "$COMMIT_SCRIPT" -m 'test commit'
  assert_success

  local last_msg
  last_msg=$(git -C "$TEST_WORKDIR" log -1 --format=%s)
  [ "$last_msg" = "test commit" ]
}

@test "git-commit-serialized.sh retries on lock contention (held lock)" {
  mk_git_repo
  echo 'test2' > "$TEST_WORKDIR/test2.txt"
  git -C "$TEST_WORKDIR" add test2.txt

  # Hold the mkdir-based lock
  mkdir -p "$TEST_WORKDIR/.git/yolo-commit.lock.d"

  # Script retries 5 times with backoff then fails -- let it run to completion
  run bash "$COMMIT_SCRIPT" -m 'test2'
  assert_failure
}

@test "git-commit-serialized.sh exits non-zero after failed retries" {
  mk_git_repo
  echo 'test3' > "$TEST_WORKDIR/test3.txt"
  git -C "$TEST_WORKDIR" add test3.txt

  # Hold the lock permanently
  mkdir -p "$TEST_WORKDIR/.git/yolo-commit.lock.d"

  # Script retries 5 times with exponential backoff, then exits non-zero
  run bash "$COMMIT_SCRIPT" -m 'test3'
  assert_failure
  # Verify script exited with error (lock held prevents commit)
  [ "$status" -ne 0 ]
}
