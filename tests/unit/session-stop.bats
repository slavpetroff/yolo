#!/usr/bin/env bats
# session-stop.bats — Unit tests for scripts/session-stop.sh
# Stop hook: logs session metrics, cleans markers

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  load '../test_helper/mock_stdin'
  mk_test_workdir
  mk_planning_dir
  SUT="$SCRIPTS_DIR/session-stop.sh"
}

# Helper: run session-stop with JSON input
run_session_stop() {
  local json="$1"
  run bash -c "cd '$TEST_WORKDIR' && printf '%s' '$json' | bash '$SUT'"
}

# --- 1. Exits 0 when no planning dir ---

@test "exits 0 silently when .yolo-planning is missing" {
  rm -rf "$TEST_WORKDIR/.yolo-planning"
  run bash -c "cd '$TEST_WORKDIR' && echo '{}' | bash '$SUT'"
  assert_success
  [ -z "$output" ]
}

# --- 2. Appends session log entry ---

@test "appends JSON line to .session-log.jsonl" {
  run_session_stop '{"cost_usd":0.15,"duration_ms":30000,"tokens_in":5000,"tokens_out":2000,"model":"claude-sonnet"}'
  assert_success
  assert_file_exists "$TEST_WORKDIR/.yolo-planning/.session-log.jsonl"
  run jq -r '.model' "$TEST_WORKDIR/.yolo-planning/.session-log.jsonl"
  assert_output "claude-sonnet"
}

# --- 3. Handles missing fields gracefully ---

@test "handles empty JSON input without crashing" {
  run_session_stop '{}'
  assert_success
  assert_file_exists "$TEST_WORKDIR/.yolo-planning/.session-log.jsonl"
  run jq -r '.model' "$TEST_WORKDIR/.yolo-planning/.session-log.jsonl"
  assert_output "unknown"
}

# --- 4. Cleans .yolo-session marker ---

@test "removes .yolo-session marker on stop" {
  mk_yolo_session
  assert_file_exists "$TEST_WORKDIR/.yolo-planning/.yolo-session"
  run_session_stop '{}'
  assert_success
  assert_file_not_exists "$TEST_WORKDIR/.yolo-planning/.yolo-session"
}

# --- 5. Processes cost ledger and cleans up ---

@test "persists cost summary and cleans .cost-ledger.json" {
  echo '{"dev":250,"lead":100}' > "$TEST_WORKDIR/.yolo-planning/.cost-ledger.json"
  mk_active_agent "yolo-dev"
  run_session_stop '{"cost_usd":1.00,"duration_ms":60000,"tokens_in":10000,"tokens_out":5000,"model":"claude-opus"}'
  assert_success
  # Cost ledger should be cleaned up
  assert_file_not_exists "$TEST_WORKDIR/.yolo-planning/.cost-ledger.json"
  assert_file_not_exists "$TEST_WORKDIR/.yolo-planning/.active-agent"
  # Session log should have cost_summary entry
  run bash -c "grep 'cost_summary' '$TEST_WORKDIR/.yolo-planning/.session-log.jsonl'"
  assert_success
}

# --- 6. Always exits 0 ---

@test "always exits 0 even with malformed input" {
  run bash -c "cd '$TEST_WORKDIR' && echo 'not-json' | bash '$SUT'"
  assert_success
}
