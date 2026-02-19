#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
}

teardown() {
  teardown_temp_dir
}

# ---------------------------------------------------------------------------
# worktree-create.sh tests
# ---------------------------------------------------------------------------

@test "worktree-create: exits 0 with no arguments" {
  run bash "$SCRIPTS_DIR/worktree-create.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "worktree-create: idempotent when worktree dir already exists" {
  mkdir -p "$TEST_TEMP_DIR/.vbw-worktrees/01-01"
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/worktree-create.sh" 01 01
  [ "$status" -eq 0 ]
  [[ "$output" == *".vbw-worktrees/01-01" ]]
}

@test "worktree-create: fail-open when not a git repo" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/worktree-create.sh" 01 01
  [ "$status" -eq 0 ]
}
