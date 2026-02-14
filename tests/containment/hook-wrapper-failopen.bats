#!/usr/bin/env bats
# hook-wrapper-failopen.bats — Proves hook-wrapper.sh only passes exit 2, converts other errors to exit 0

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  load '../test_helper/mock_stdin'
  mk_test_workdir
  mk_planning_dir

  # Build a fake plugin cache structure that hook-wrapper.sh can resolve
  export CLAUDE_CONFIG_DIR="$TEST_WORKDIR/.claude-test"
  FAKE_CACHE="$CLAUDE_CONFIG_DIR/plugins/cache/yolo-marketplace/yolo/1.0.0"
  mkdir -p "$FAKE_CACHE/scripts"

  # Clear the per-user version-dir cache so hook-wrapper resolves our fake cache
  rm -f "/tmp/yolo-vdir-$(id -u)"
}

teardown() {
  # Clean up the per-user version-dir cache to avoid polluting other tests
  rm -f "/tmp/yolo-vdir-$(id -u)"
}

@test "returns 0 when target script exits 1" {
  # Create a mock script that exits 1
  cat > "$CLAUDE_CONFIG_DIR/plugins/cache/yolo-marketplace/yolo/1.0.0/scripts/fail-one.sh" <<'SCRIPT'
#!/bin/bash
exit 1
SCRIPT
  chmod +x "$CLAUDE_CONFIG_DIR/plugins/cache/yolo-marketplace/yolo/1.0.0/scripts/fail-one.sh"

  run bash "$SCRIPTS_DIR/hook-wrapper.sh" "fail-one.sh"
  assert_success
}

@test "passes through exit 2 from target script" {
  # Create a mock script that exits 2
  cat > "$CLAUDE_CONFIG_DIR/plugins/cache/yolo-marketplace/yolo/1.0.0/scripts/fail-two.sh" <<'SCRIPT'
#!/bin/bash
exit 2
SCRIPT
  chmod +x "$CLAUDE_CONFIG_DIR/plugins/cache/yolo-marketplace/yolo/1.0.0/scripts/fail-two.sh"

  run bash "$SCRIPTS_DIR/hook-wrapper.sh" "fail-two.sh"
  assert_failure 2
}

@test "returns 0 when target script not found" {
  # Ask for a script that does not exist in the cache
  run bash "$SCRIPTS_DIR/hook-wrapper.sh" "nonexistent-script.sh"
  assert_success
}

@test "returns 0 when plugin cache directory missing" {
  # Point to a non-existent cache directory
  export CLAUDE_CONFIG_DIR="$TEST_WORKDIR/.no-such-claude-dir"

  run bash "$SCRIPTS_DIR/hook-wrapper.sh" "some-script.sh"
  assert_success
}

@test "returns 0 when script name is empty" {
  run bash "$SCRIPTS_DIR/hook-wrapper.sh" ""
  assert_success
}

@test "logs failure details to .hook-errors.log" {
  # Create a mock script that exits with error
  cat > "$CLAUDE_CONFIG_DIR/plugins/cache/yolo-marketplace/yolo/1.0.0/scripts/log-test.sh" <<'SCRIPT'
#!/bin/bash
exit 3
SCRIPT
  chmod +x "$CLAUDE_CONFIG_DIR/plugins/cache/yolo-marketplace/yolo/1.0.0/scripts/log-test.sh"

  run bash "$SCRIPTS_DIR/hook-wrapper.sh" "log-test.sh"
  assert_success

  # Verify the log file was written with failure details
  assert_file_exists "$TEST_WORKDIR/.yolo-planning/.hook-errors.log"
  run cat "$TEST_WORKDIR/.yolo-planning/.hook-errors.log"
  assert_output --partial "log-test.sh"
  assert_output --partial "exit=3"
}
