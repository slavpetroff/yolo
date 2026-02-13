#!/usr/bin/env bats
# yolo-statusline.bats — Unit tests for scripts/yolo-statusline.sh
# Status line rendering: 4-line dashboard

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  load '../test_helper/mock_stdin'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/yolo-statusline.sh"

  # Clean temp caches to force fresh computation
  rm -f /tmp/yolo-*-"$(id -u)"* 2>/dev/null

  # Stub curl to prevent network calls
  mkdir -p "$TEST_WORKDIR/bin"
  printf '#!/bin/bash\nexit 1\n' > "$TEST_WORKDIR/bin/curl"
  chmod +x "$TEST_WORKDIR/bin/curl"
  # Stub security to prevent keychain access
  printf '#!/bin/bash\nexit 1\n' > "$TEST_WORKDIR/bin/security"
  chmod +x "$TEST_WORKDIR/bin/security"
  # Stub pgrep to return 0 agents
  printf '#!/bin/bash\necho 1\n' > "$TEST_WORKDIR/bin/pgrep"
  chmod +x "$TEST_WORKDIR/bin/pgrep"
}

teardown() {
  rm -f /tmp/yolo-*-"$(id -u)"* 2>/dev/null
}

# Minimal status JSON for input
STATUS_INPUT='{"context_window":{"used_percentage":45,"remaining_percentage":55,"current_usage":{"input_tokens":50000,"output_tokens":10000,"cache_creation_input_tokens":5000,"cache_read_input_tokens":30000},"context_window_size":200000},"cost":{"total_cost_usd":0.50,"total_duration_ms":120000,"total_api_duration_ms":90000,"total_lines_added":100,"total_lines_removed":20},"model":{"display_name":"Claude Sonnet"},"version":"1.2.3"}'

# Helper: run statusline from TEST_WORKDIR
run_statusline() {
  local input="${1:-$STATUS_INPUT}"
  run bash -c "cd '$TEST_WORKDIR' && PATH='$TEST_WORKDIR/bin:$PATH' printf '%s' '$input' | bash '$SUT'"
}

# --- 1. Always exits 0 ---

@test "exits 0 with valid input" {
  run_statusline
  assert_success
}

# --- 2. Shows [YOLO] header ---

@test "output contains [YOLO] header" {
  run_statusline
  assert_success
  assert_output --partial "[YOLO]"
}

# --- 3. Shows context percentage ---

@test "output includes context usage percentage" {
  run_statusline
  assert_success
  assert_output --partial "45%"
}

# --- 4. Shows model name ---

@test "output includes model display name" {
  run_statusline
  assert_success
  assert_output --partial "Claude Sonnet"
}

# --- 5. Shows token info ---

@test "output includes token counts" {
  run_statusline
  assert_success
  assert_output --partial "in"
  assert_output --partial "out"
}

# --- 6. Shows no project when .yolo-planning missing ---

@test "shows 'no project' when .yolo-planning does not exist" {
  run_statusline
  assert_success
  assert_output --partial "no project"
}

# --- 7. Shows phase info with .yolo-planning ---

@test "shows phase info when state.json exists" {
  mk_planning_dir
  mk_state_json 2 5 "executing"
  run_statusline
  assert_success
  assert_output --partial "Phase"
}

# --- 8. Handles empty input gracefully ---

@test "exits 0 with minimal empty JSON input" {
  run_statusline '{}'
  assert_success
  assert_output --partial "[YOLO]"
}
