#!/usr/bin/env bats
# test-resolve-documenter-gate.bats — Unit tests for scripts/resolve-documenter-gate.sh
# Tests: always/never/on_request config values, trigger combinations, missing config.

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/resolve-documenter-gate.sh"
}

# Helper: create config with documenter value
mk_documenter_config() {
  local value="$1"
  jq -n --arg v "$value" '{documenter:$v}' > "$TEST_WORKDIR/config.json"
}

# Helper: run resolve-documenter-gate
run_gate() {
  local config="${1:-$TEST_WORKDIR/config.json}"
  local trigger="${2:-phase}"
  run bash "$SUT" --config "$config" --trigger "$trigger"
}

# --- documenter=always ---

@test "documenter=always: exits 0 with spawn=true" {
  mk_documenter_config "always"
  run_gate "$TEST_WORKDIR/config.json" "phase"
  assert_success
  local spawn
  spawn=$(echo "$output" | jq -r '.spawn')
  assert_equal "$spawn" "true"
}

@test "documenter=always with trigger=on_request: exits 0" {
  mk_documenter_config "always"
  run_gate "$TEST_WORKDIR/config.json" "on_request"
  assert_success
  local spawn
  spawn=$(echo "$output" | jq -r '.spawn')
  assert_equal "$spawn" "true"
}

# --- documenter=never ---

@test "documenter=never: exits 1 with spawn=false" {
  mk_documenter_config "never"
  run_gate "$TEST_WORKDIR/config.json" "phase"
  assert_failure
  local spawn
  spawn=$(echo "$output" | jq -r '.spawn')
  assert_equal "$spawn" "false"
}

@test "documenter=never with trigger=on_request: still exits 1" {
  mk_documenter_config "never"
  run_gate "$TEST_WORKDIR/config.json" "on_request"
  assert_failure
  local spawn
  spawn=$(echo "$output" | jq -r '.spawn')
  assert_equal "$spawn" "false"
}

# --- documenter=on_request ---

@test "documenter=on_request with trigger=on_request: exits 0" {
  mk_documenter_config "on_request"
  run_gate "$TEST_WORKDIR/config.json" "on_request"
  assert_success
  local spawn
  spawn=$(echo "$output" | jq -r '.spawn')
  assert_equal "$spawn" "true"
}

@test "documenter=on_request with trigger=phase: exits 1" {
  mk_documenter_config "on_request"
  run_gate "$TEST_WORKDIR/config.json" "phase"
  assert_failure
  local spawn
  spawn=$(echo "$output" | jq -r '.spawn')
  assert_equal "$spawn" "false"
}

# --- Missing config key: defaults to on_request ---

@test "missing documenter key: defaults to on_request behavior" {
  echo '{}' > "$TEST_WORKDIR/config.json"
  run_gate "$TEST_WORKDIR/config.json" "on_request"
  assert_success
  local spawn
  spawn=$(echo "$output" | jq -r '.spawn')
  assert_equal "$spawn" "true"
}

@test "missing documenter key with trigger=phase: defaults to no spawn" {
  echo '{}' > "$TEST_WORKDIR/config.json"
  run_gate "$TEST_WORKDIR/config.json" "phase"
  assert_failure
  local spawn
  spawn=$(echo "$output" | jq -r '.spawn')
  assert_equal "$spawn" "false"
}

# --- Missing config file ---

@test "missing config file: defaults to on_request behavior" {
  run_gate "$TEST_WORKDIR/nonexistent.json" "on_request"
  assert_success
  local spawn
  spawn=$(echo "$output" | jq -r '.spawn')
  assert_equal "$spawn" "true"
}

# --- Missing flags ---

@test "missing --config flag: exits with error" {
  run bash "$SUT" --trigger "phase"
  assert_failure
}

@test "missing --trigger flag: exits with error" {
  mk_documenter_config "always"
  run bash "$SUT" --config "$TEST_WORKDIR/config.json"
  assert_failure
}

# --- Invalid trigger ---

@test "invalid trigger value: exits 1" {
  mk_documenter_config "always"
  run_gate "$TEST_WORKDIR/config.json" "invalid"
  assert_failure
}

# --- JSON output format ---

@test "output is valid JSON with spawn and reason fields" {
  mk_documenter_config "always"
  run_gate "$TEST_WORKDIR/config.json" "phase"
  assert_success
  run jq -e '.spawn and .reason' <<< "$output"
  assert_success
}
