#!/usr/bin/env bats
# hook-wrapper.bats — Unit tests for scripts/hook-wrapper.sh
# Universal wrapper, ALWAYS exit 0

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  load '../test_helper/mock_stdin'
  mk_test_workdir
  mk_planning_dir
  SUT="$SCRIPTS_DIR/hook-wrapper.sh"

  # Create a mock plugin cache that hook-wrapper.sh can resolve
  MOCK_CACHE="$TEST_WORKDIR/mock-claude/plugins/cache/yolo-marketplace/yolo/1.0.0"
  mkdir -p "$MOCK_CACHE/scripts"

  # Point the vdir cache to our mock plugin dir
  VDIR_CACHE="/tmp/yolo-vdir-$(id -u)"
  # Save original if it exists
  [ -f "$VDIR_CACHE" ] && cp "$VDIR_CACHE" "$VDIR_CACHE.bak"
  printf '%s' "${MOCK_CACHE%/scripts}" > "$VDIR_CACHE"
  # Set CLAUDE_CONFIG_DIR so fallback resolution also works
  export CLAUDE_CONFIG_DIR="$TEST_WORKDIR/mock-claude"
}

teardown() {
  VDIR_CACHE="/tmp/yolo-vdir-$(id -u)"
  if [ -f "$VDIR_CACHE.bak" ]; then
    mv "$VDIR_CACHE.bak" "$VDIR_CACHE"
  else
    rm -f "$VDIR_CACHE"
  fi
}

# Helper: write a mock target script
mk_mock_script() {
  local name="$1" body="$2"
  printf '#!/bin/bash\n%s\n' "$body" > "$MOCK_CACHE/scripts/$name"
  chmod +x "$MOCK_CACHE/scripts/$name"
}

# --- Always exits 0 ---

@test "exits 0 when target script exits 0" {
  mk_mock_script "pass.sh" "exit 0"
  run bash -c "CLAUDE_CONFIG_DIR='$CLAUDE_CONFIG_DIR' bash '$SUT' pass.sh"
  assert_success
}

@test "exits 0 when target script exits 1" {
  mk_mock_script "fail-one.sh" "exit 1"
  run bash -c "cd '$TEST_WORKDIR' && CLAUDE_CONFIG_DIR='$CLAUDE_CONFIG_DIR' bash '$SUT' fail-one.sh"
  assert_success
}

@test "exits 0 when target script exits 2" {
  mk_mock_script "fail-two.sh" "exit 2"
  run bash -c "cd '$TEST_WORKDIR' && CLAUDE_CONFIG_DIR='$CLAUDE_CONFIG_DIR' bash '$SUT' fail-two.sh"
  assert_success
}

@test "exits 0 when target script does not exist" {
  run bash -c "CLAUDE_CONFIG_DIR='$CLAUDE_CONFIG_DIR' bash '$SUT' nonexistent.sh"
  assert_success
}

@test "exits 0 when no script name argument given" {
  run bash "$SUT"
  assert_success
}

# --- Failure logging ---

@test "logs failure to .hook-errors.log when target exits non-zero" {
  mk_mock_script "failing.sh" "exit 2"
  run bash -c "cd '$TEST_WORKDIR' && CLAUDE_CONFIG_DIR='$CLAUDE_CONFIG_DIR' bash '$SUT' failing.sh"
  assert_success
  assert_file_exists "$TEST_WORKDIR/.yolo-planning/.hook-errors.log"
  run grep "failing.sh exit=2" "$TEST_WORKDIR/.yolo-planning/.hook-errors.log"
  assert_success
}

# --- Log trimming ---

@test "trims log to 30 entries when over 50 lines" {
  mk_mock_script "trim-test.sh" "exit 1"

  # Pre-populate log with 51 entries
  local log="$TEST_WORKDIR/.yolo-planning/.hook-errors.log"
  for i in $(seq 1 51); do
    echo "2026-01-01T00:00:00Z old-script.sh exit=1" >> "$log"
  done

  run bash -c "cd '$TEST_WORKDIR' && CLAUDE_CONFIG_DIR='$CLAUDE_CONFIG_DIR' bash '$SUT' trim-test.sh"
  assert_success

  # After adding 1 entry (total 52), trim should reduce to ~30
  local lc
  lc=$(wc -l < "$log" | tr -d ' ')
  [ "$lc" -le 31 ]
}

# --- Stdin passthrough ---

@test "passes stdin through to target script" {
  mk_mock_script "echo-stdin.sh" 'INPUT=$(cat); [ "$INPUT" = "hello-from-stdin" ] && exit 0 || exit 1'
  run bash -c "echo 'hello-from-stdin' | CLAUDE_CONFIG_DIR='$CLAUDE_CONFIG_DIR' bash '$SUT' echo-stdin.sh"
  assert_success
}

# --- Argument passthrough ---

@test "passes extra arguments to target script" {
  mk_mock_script "check-args.sh" '[ "$1" = "arg1" ] && [ "$2" = "arg2" ] && exit 0 || exit 1'
  run bash -c "CLAUDE_CONFIG_DIR='$CLAUDE_CONFIG_DIR' bash '$SUT' check-args.sh arg1 arg2"
  assert_success
}

# --- No log when .yolo-planning missing ---

@test "does not crash when .yolo-planning dir is missing and target fails" {
  rm -rf "$TEST_WORKDIR/.yolo-planning"
  mk_mock_script "fail-nolog.sh" "exit 1"
  run bash -c "cd '$TEST_WORKDIR' && CLAUDE_CONFIG_DIR='$CLAUDE_CONFIG_DIR' bash '$SUT' fail-nolog.sh"
  assert_success
}
