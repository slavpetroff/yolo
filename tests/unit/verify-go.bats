#!/usr/bin/env bats
# verify-go.bats — Unit tests for scripts/verify-go.sh
# YOLO installation verification: checks 25 requirements

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  load '../test_helper/mock_stdin'
  SUT="$SCRIPTS_DIR/verify-go.sh"

  # The script uses ROOT relative to its own location.
  # It checks real project files, so we run it against the actual project.
  # Set CLAUDE_CONFIG_DIR to mock commands mirror for REQ-18/19
  export CLAUDE_CONFIG_DIR="$HOME/.claude"
}

# --- 1. Exits 0 when all checks pass ---

@test "exits 0 when all verification checks pass" {
  run bash "$SUT"
  assert_success
  assert_output --partial "All checks passed"
}

# --- 2. Reports total PASS count ---

@test "reports TOTAL with pass count" {
  run bash "$SUT"
  assert_success
  assert_output --partial "TOTAL:"
  assert_output --partial "PASS"
}

# --- 3. Checks all 6 groups ---

@test "verifies all 6 requirement groups" {
  run bash "$SUT"
  assert_success
  assert_output --partial "GROUP 1: Core Router"
  assert_output --partial "GROUP 2: Mode Implementation"
  assert_output --partial "GROUP 3: Execution Protocol"
  assert_output --partial "GROUP 4: Command Surface"
  assert_output --partial "GROUP 5: NL Parsing"
  assert_output --partial "GROUP 6: Flags"
}

# --- 4. Reports group-level results ---

@test "reports per-group pass/fail summary" {
  run bash "$SUT"
  assert_success
  assert_output --partial "ALL PASS"
}
