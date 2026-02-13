#!/usr/bin/env bats
# notification-log.bats — Unit tests for scripts/notification-log.sh
# Notification hook: logs notification metadata

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  load '../test_helper/mock_stdin'
  mk_test_workdir
  mk_planning_dir
  SUT="$SCRIPTS_DIR/notification-log.sh"
}

# --- 1. Exits 0 when .yolo-planning is missing ---

@test "exits 0 silently when .yolo-planning is missing" {
  rm -rf "$TEST_WORKDIR/.yolo-planning"
  run bash -c "cd '$TEST_WORKDIR' && echo '{\"notification_type\":\"info\",\"message\":\"test\"}' | bash '$SUT'"
  assert_success
}

# --- 2. Logs notification to .notification-log.jsonl ---

@test "appends notification entry to .notification-log.jsonl" {
  run bash -c "cd '$TEST_WORKDIR' && echo '{\"notification_type\":\"warning\",\"title\":\"Test Title\",\"message\":\"Test message\"}' | bash '$SUT'"
  assert_success
  assert_file_exists "$TEST_WORKDIR/.yolo-planning/.notification-log.jsonl"
  run jq -r '.type' "$TEST_WORKDIR/.yolo-planning/.notification-log.jsonl"
  assert_output "warning"
}

# --- 3. Captures title and message ---

@test "captures notification title and message" {
  run bash -c "cd '$TEST_WORKDIR' && echo '{\"notification_type\":\"info\",\"title\":\"Build Done\",\"message\":\"Phase 1 complete\"}' | bash '$SUT'"
  assert_success
  run jq -r '.title' "$TEST_WORKDIR/.yolo-planning/.notification-log.jsonl"
  assert_output "Build Done"
  run jq -r '.message' "$TEST_WORKDIR/.yolo-planning/.notification-log.jsonl"
  assert_output "Phase 1 complete"
}

# --- 4. Handles missing fields gracefully ---

@test "defaults to 'unknown' type when notification_type is missing" {
  run bash -c "cd '$TEST_WORKDIR' && echo '{}' | bash '$SUT'"
  assert_success
  assert_file_exists "$TEST_WORKDIR/.yolo-planning/.notification-log.jsonl"
  run jq -r '.type' "$TEST_WORKDIR/.yolo-planning/.notification-log.jsonl"
  assert_output "unknown"
}
