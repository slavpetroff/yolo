#!/usr/bin/env bats
# test-summary.bats -- Unit tests for scripts/test-summary.sh

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/test-summary.sh"
}

@test "test-summary.sh exists and is executable" {
  assert_file_exists "$SUT"
  [ -x "$SUT" ]
}

@test "produces single-line PASS output when all tests pass" {
  # Create mock test directory with trivial passing .bats file
  mkdir -p "$TEST_WORKDIR/suite1"
  cat > "$TEST_WORKDIR/suite1/pass.bats" << 'BATS'
@test "trivial pass" { true; }
@test "another pass" { true; }
BATS
  export TESTS_DIR="$TEST_WORKDIR"
  run bash "$SUT"
  assert_success
  local line_count
  line_count=$(echo "$output" | wc -l | tr -d ' ')
  [ "$line_count" -eq 1 ]
  [[ "$output" =~ ^PASS\ \([0-9]+\ tests\)$ ]]
}

@test "exit code is 0 when all tests pass" {
  mkdir -p "$TEST_WORKDIR/suite1"
  cat > "$TEST_WORKDIR/suite1/pass.bats" << 'BATS'
@test "trivial pass" { true; }
BATS
  export TESTS_DIR="$TEST_WORKDIR"
  run bash "$SUT"
  assert_success
}

@test "PASS count reflects actual test count" {
  mkdir -p "$TEST_WORKDIR/suite1"
  mkdir -p "$TEST_WORKDIR/suite2"
  cat > "$TEST_WORKDIR/suite1/a.bats" << 'BATS'
@test "one" { true; }
@test "two" { true; }
BATS
  cat > "$TEST_WORKDIR/suite2/b.bats" << 'BATS'
@test "three" { true; }
BATS
  export TESTS_DIR="$TEST_WORKDIR"
  run bash "$SUT"
  assert_success
  local count
  count=$(echo "$output" | grep -oE '[0-9]+' | head -1)
  [ "$count" -eq 3 ]
}

@test "FAIL output includes failure details" {
  mkdir -p "$TEST_WORKDIR/suite1"
  cat > "$TEST_WORKDIR/suite1/fail.bats" << 'BATS'
@test "this passes" { true; }
@test "this fails" { false; }
BATS
  export TESTS_DIR="$TEST_WORKDIR"
  run bash "$SUT"
  assert_failure
  [[ "$output" =~ ^FAIL\ \(1/2\ failed\) ]]
  [[ "$output" =~ \[suite1\] ]]
}

@test "perf failures do not count toward total" {
  mkdir -p "$TEST_WORKDIR/perf"
  mkdir -p "$TEST_WORKDIR/unit"
  cat > "$TEST_WORKDIR/unit/pass.bats" << 'BATS'
@test "unit pass" { true; }
BATS
  cat > "$TEST_WORKDIR/perf/slow.bats" << 'BATS'
@test "perf fail" { false; }
BATS
  export TESTS_DIR="$TEST_WORKDIR"
  run bash "$SUT"
  assert_success
  [[ "$output" =~ ^PASS\ \(1\ tests\)$ ]]
}

@test "no test directories produces FAIL" {
  mkdir -p "$TEST_WORKDIR/empty_dir"
  export TESTS_DIR="$TEST_WORKDIR"
  run bash "$SUT"
  assert_failure
  [[ "$output" =~ "no test directories found" ]]
}

@test "script uses dynamic directory discovery" {
  run grep -E 'for dir in|for suite in' "$SUT"
  assert_success
}

@test "script uses bats --tap for TAP output" {
  run grep 'bats --tap' "$SUT"
  assert_success
}

@test "script excludes test_helper and fixtures directories" {
  run grep -E 'test_helper|fixtures' "$SUT"
  assert_success
}
