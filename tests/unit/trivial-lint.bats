#!/usr/bin/env bats
# trivial-lint.bats — Tests for scripts/trivial-lint.sh
# Plan 07-05 T5: Verify lightweight lint checks for trivial-path tasks

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/trivial-lint.sh"
}

# Helper: extract JSON field
get_field() {
  echo "$output" | jq -r ".$1"
}

# --- JSON file checks ---

@test "valid JSON file passes lint" {
  echo '{"key": "value"}' > "$TEST_WORKDIR/test.json"
  run bash "$SUT" --files "$TEST_WORKDIR/test.json"
  assert_success
  local status
  status=$(get_field status)
  [ "$status" = "pass" ]
}

@test "invalid JSON file fails lint" {
  echo '{broken json' > "$TEST_WORKDIR/bad.json"
  run bash "$SUT" --files "$TEST_WORKDIR/bad.json"
  assert_failure
  local status
  status=$(get_field status)
  [ "$status" = "fail" ]
  local issues
  issues=$(echo "$output" | jq '.issues | length')
  [ "$issues" -gt 0 ]
}

@test "valid JSONL file passes lint" {
  printf '{"a":1}\n{"b":2}\n' > "$TEST_WORKDIR/test.jsonl"
  run bash "$SUT" --files "$TEST_WORKDIR/test.jsonl"
  assert_success
  local status
  status=$(get_field status)
  [ "$status" = "pass" ]
}

@test "invalid JSONL file fails lint" {
  printf '{"a":1}\nbad line\n' > "$TEST_WORKDIR/bad.jsonl"
  run bash "$SUT" --files "$TEST_WORKDIR/bad.jsonl"
  assert_failure
  local status
  status=$(get_field status)
  [ "$status" = "fail" ]
}

# --- Markdown file checks ---

@test "valid markdown passes lint" {
  printf '# Heading\n\nContent here.\n' > "$TEST_WORKDIR/test.md"
  run bash "$SUT" --files "$TEST_WORKDIR/test.md"
  assert_success
  local status
  status=$(get_field status)
  [ "$status" = "pass" ]
}

@test "empty heading in markdown fails lint" {
  printf '# \n\nContent.\n' > "$TEST_WORKDIR/bad.md"
  run bash "$SUT" --files "$TEST_WORKDIR/bad.md"
  assert_failure
  local status
  status=$(get_field status)
  [ "$status" = "fail" ]
}

# --- Multiple files ---

@test "multiple valid files all pass" {
  echo '{"ok":true}' > "$TEST_WORKDIR/a.json"
  printf '# Title\n\nText.\n' > "$TEST_WORKDIR/b.md"
  run bash "$SUT" --files "$TEST_WORKDIR/a.json $TEST_WORKDIR/b.md"
  assert_success
  local pass_count
  pass_count=$(get_field checks_passed)
  [ "$pass_count" -eq 2 ]
}

@test "one bad file in mix causes overall fail" {
  echo '{"ok":true}' > "$TEST_WORKDIR/good.json"
  echo '{broken' > "$TEST_WORKDIR/bad.json"
  run bash "$SUT" --files "$TEST_WORKDIR/good.json $TEST_WORKDIR/bad.json"
  assert_failure
  local status pass_count fail_count
  status=$(get_field status)
  pass_count=$(get_field checks_passed)
  fail_count=$(get_field checks_failed)
  [ "$status" = "fail" ]
  [ "$pass_count" -eq 1 ]
  [ "$fail_count" -eq 1 ]
}

# --- Edge cases ---

@test "nonexistent file is silently skipped" {
  run bash "$SUT" --files "/nonexistent/file.json"
  assert_success
  local pass_count
  pass_count=$(get_field checks_passed)
  [ "$pass_count" -eq 0 ]
}

@test "unknown extension is skipped" {
  echo "some data" > "$TEST_WORKDIR/test.txt"
  run bash "$SUT" --files "$TEST_WORKDIR/test.txt"
  assert_success
  local pass_count
  pass_count=$(get_field checks_passed)
  [ "$pass_count" -eq 0 ]
}

@test "missing --files flag exits with error" {
  run bash "$SUT"
  assert_failure
}

@test "output is valid JSON" {
  echo '{"ok":true}' > "$TEST_WORKDIR/test.json"
  run bash "$SUT" --files "$TEST_WORKDIR/test.json"
  assert_success
  echo "$output" | jq empty
}
