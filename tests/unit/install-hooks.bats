#!/usr/bin/env bats
# install-hooks.bats — Unit tests for scripts/install-hooks.sh
# Hook installation utility: installs pre-push git hook

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  load '../test_helper/mock_stdin'
  mk_test_workdir
  mk_git_repo
  SUT="$SCRIPTS_DIR/install-hooks.sh"
}

# --- 1. Installs pre-push hook ---

@test "installs pre-push hook in .git/hooks/" {
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT'"
  assert_success
  assert_file_exists "$TEST_WORKDIR/.git/hooks/pre-push"
}

# --- 2. Hook is executable ---

@test "installed hook is executable" {
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT'"
  assert_success
  [ -x "$TEST_WORKDIR/.git/hooks/pre-push" ]
}

# --- 3. Hook contains YOLO marker ---

@test "installed hook contains YOLO marker" {
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT'"
  assert_success
  run grep "YOLO pre-push hook" "$TEST_WORKDIR/.git/hooks/pre-push"
  assert_success
}

# --- 4. Idempotent: does not overwrite existing YOLO hook ---

@test "does not overwrite existing YOLO hook" {
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT'"
  assert_success
  # Run again
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT' 2>&1"
  assert_success
  assert_output --partial "already installed"
}

# --- 5. Skips non-YOLO hooks ---

@test "skips pre-push hook that is not managed by YOLO" {
  mkdir -p "$TEST_WORKDIR/.git/hooks"
  echo '#!/bin/bash' > "$TEST_WORKDIR/.git/hooks/pre-push"
  echo 'echo "custom hook"' >> "$TEST_WORKDIR/.git/hooks/pre-push"
  chmod +x "$TEST_WORKDIR/.git/hooks/pre-push"
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT' 2>&1"
  assert_success
  assert_output --partial "not managed by YOLO"
  # Original content preserved
  run grep "custom hook" "$TEST_WORKDIR/.git/hooks/pre-push"
  assert_success
}

# --- 6. Exits silently outside git repo ---

@test "exits 0 silently when not in a git repo" {
  local nogit_dir
  nogit_dir=$(mktemp -d "$BATS_TEST_TMPDIR/yolo-nogit-XXXXXX")
  run bash -c "cd '$nogit_dir' && bash '$SUT'"
  assert_success
}
