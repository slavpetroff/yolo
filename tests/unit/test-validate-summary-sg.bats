#!/usr/bin/env bats
# test-validate-summary-sg.bats — Unit tests for validate-summary.sh sg field handling
# Tests: valid sg, absent sg, empty array, invalid types, backward compat.

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  mk_test_workdir
  mk_planning_dir
  SUT="$SCRIPTS_DIR/validate-summary.sh"
  PHASE_DIR="$TEST_WORKDIR/.yolo-planning/phases/01-setup"
  mkdir -p "$PHASE_DIR"
}

# Helper: write a summary.jsonl with given sg value
mk_summary_with_sg() {
  local sg_fragment="$1"
  local file="$PHASE_DIR/01-01.summary.jsonl"
  if [[ -n "$sg_fragment" ]]; then
    echo "{\"p\":\"01\",\"s\":\"complete\",\"fm\":[\"a.sh\"],${sg_fragment}}" > "$file"
  else
    echo '{"p":"01","s":"complete","fm":["a.sh"]}' > "$file"
  fi
  echo "$file"
}

# --- Valid sg with suggestions ---

@test "valid sg with string array passes without warning" {
  local file
  file=$(mk_summary_with_sg '"sg":["Extract shared util","Rename for clarity"]')
  run bash -c "echo '{\"tool_input\":{\"file_path\":\"$file\"}}' | bash '$SUT'"
  assert_success
  refute_output --partial "hookSpecificOutput"
}

# --- Missing sg (optional) ---

@test "missing sg field passes (optional)" {
  local file
  file=$(mk_summary_with_sg "")
  run bash -c "echo '{\"tool_input\":{\"file_path\":\"$file\"}}' | bash '$SUT'"
  assert_success
  refute_output --partial "hookSpecificOutput"
}

# --- Empty sg array ---

@test "empty sg array passes" {
  local file
  file=$(mk_summary_with_sg '"sg":[]')
  run bash -c "echo '{\"tool_input\":{\"file_path\":\"$file\"}}' | bash '$SUT'"
  assert_success
  refute_output --partial "hookSpecificOutput"
}

# --- Invalid sg type (string not array) ---

@test "sg as string (not array) reports warning" {
  local file
  file=$(mk_summary_with_sg '"sg":"bad value"')
  run bash -c "echo '{\"tool_input\":{\"file_path\":\"$file\"}}' | bash '$SUT'"
  assert_success
  assert_output --partial "hookSpecificOutput"
  assert_output --partial "sg"
  assert_output --partial "array"
}

# --- Invalid sg element (number not string) ---

@test "sg with number element reports warning" {
  local file
  file=$(mk_summary_with_sg '"sg":[123]')
  run bash -c "echo '{\"tool_input\":{\"file_path\":\"$file\"}}' | bash '$SUT'"
  assert_success
  assert_output --partial "hookSpecificOutput"
  assert_output --partial "sg"
}

# --- sg with empty string element ---

@test "sg with empty string element reports warning" {
  local file
  file=$(mk_summary_with_sg '"sg":["good",""]')
  run bash -c "echo '{\"tool_input\":{\"file_path\":\"$file\"}}' | bash '$SUT'"
  assert_success
  assert_output --partial "hookSpecificOutput"
  assert_output --partial "sg"
}

# --- Backward compat: existing required fields still validated ---

@test "backward compat: missing p field still reported with sg present" {
  local file="$PHASE_DIR/01-01.summary.jsonl"
  echo '{"s":"complete","fm":["a.sh"],"sg":["suggestion"]}' > "$file"
  run bash -c "echo '{\"tool_input\":{\"file_path\":\"$file\"}}' | bash '$SUT'"
  assert_success
  assert_output --partial "Missing 'p'"
}
