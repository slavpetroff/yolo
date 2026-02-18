#!/usr/bin/env bats
# pre-integration-check.bats — Tests for scripts/pre-integration-check.sh
# Plan 07-05 T5: Verify pre-integration readiness checks

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/pre-integration-check.sh"

  # Create phase directory
  PHASE_DIR="$TEST_WORKDIR/phases/01-test"
  mkdir -p "$PHASE_DIR"

  # Create config with single department
  cat > "$TEST_WORKDIR/config.json" <<'JSON'
{
  "departments": {
    "backend": true,
    "frontend": false,
    "uiux": false
  }
}
JSON
}

# Helper: extract JSON field
get_field() {
  echo "$output" | jq -r ".$1"
}

# Helper: make a department ready (sentinel + test results)
make_dept_ready() {
  local dept="$1"
  touch "$PHASE_DIR/.handoff-${dept}-complete"
}

# --- Single department tests ---

@test "single dept ready when sentinel exists" {
  make_dept_ready "backend"
  run bash "$SUT" --phase-dir "$PHASE_DIR" --config "$TEST_WORKDIR/config.json"
  assert_success
  local status
  status=$(get_field status)
  [ "$status" = "ready" ]
}

@test "single dept not ready when sentinel missing" {
  run bash "$SUT" --phase-dir "$PHASE_DIR" --config "$TEST_WORKDIR/config.json"
  assert_failure
  local status
  status=$(get_field status)
  [ "$status" = "not_ready" ]
}

@test "blocking issues list sentinel when missing" {
  run bash "$SUT" --phase-dir "$PHASE_DIR" --config "$TEST_WORKDIR/config.json"
  assert_failure
  local issues
  issues=$(echo "$output" | jq '.blocking_issues | length')
  [ "$issues" -gt 0 ]
  echo "$output" | jq -r '.blocking_issues[0]' | grep -q "handoff sentinel"
}

# --- Multi-department tests ---

@test "multi dept all ready" {
  cat > "$TEST_WORKDIR/config.json" <<'JSON'
{
  "departments": {
    "backend": true,
    "frontend": true,
    "uiux": false
  }
}
JSON
  make_dept_ready "backend"
  make_dept_ready "frontend"
  # Add test results for both depts
  printf '{"plan":"01-01","dept":"backend","ps":5,"fl":0}\n{"plan":"01-01","dept":"frontend","ps":3,"fl":0}\n' > "$PHASE_DIR/test-results.jsonl"
  run bash "$SUT" --phase-dir "$PHASE_DIR" --config "$TEST_WORKDIR/config.json"
  assert_success
  local status
  status=$(get_field status)
  [ "$status" = "ready" ]
}

@test "multi dept one missing sentinel" {
  cat > "$TEST_WORKDIR/config.json" <<'JSON'
{
  "departments": {
    "backend": true,
    "frontend": true,
    "uiux": false
  }
}
JSON
  make_dept_ready "backend"
  # frontend sentinel missing
  printf '{"plan":"01-01","dept":"backend","ps":5,"fl":0}\n{"plan":"01-01","dept":"frontend","ps":3,"fl":0}\n' > "$PHASE_DIR/test-results.jsonl"
  run bash "$SUT" --phase-dir "$PHASE_DIR" --config "$TEST_WORKDIR/config.json"
  assert_failure
  local fe_status
  fe_status=$(echo "$output" | jq -r '.departments[] | select(.department == "frontend") | .status')
  [ "$fe_status" = "not_ready" ]
}

@test "multi dept missing test results blocks" {
  cat > "$TEST_WORKDIR/config.json" <<'JSON'
{
  "departments": {
    "backend": true,
    "frontend": true,
    "uiux": false
  }
}
JSON
  make_dept_ready "backend"
  make_dept_ready "frontend"
  # No test-results.jsonl at all
  run bash "$SUT" --phase-dir "$PHASE_DIR" --config "$TEST_WORKDIR/config.json"
  assert_failure
}

# --- Critical escalation tests ---

@test "open critical escalation blocks department" {
  make_dept_ready "backend"
  printf '{"id":"E1","st":"open","sev":"critical","dept":"backend","desc":"auth broken"}\n' > "$PHASE_DIR/escalation.jsonl"
  run bash "$SUT" --phase-dir "$PHASE_DIR" --config "$TEST_WORKDIR/config.json"
  assert_failure
  echo "$output" | jq -r '.blocking_issues[0]' | grep -q "critical escalation"
}

@test "resolved critical escalation does not block" {
  make_dept_ready "backend"
  printf '{"id":"E1","st":"resolved","sev":"critical","dept":"backend","desc":"auth fixed"}\n' > "$PHASE_DIR/escalation.jsonl"
  run bash "$SUT" --phase-dir "$PHASE_DIR" --config "$TEST_WORKDIR/config.json"
  assert_success
}

@test "open non-critical escalation does not block" {
  make_dept_ready "backend"
  printf '{"id":"E1","st":"open","sev":"major","dept":"backend","desc":"style issue"}\n' > "$PHASE_DIR/escalation.jsonl"
  run bash "$SUT" --phase-dir "$PHASE_DIR" --config "$TEST_WORKDIR/config.json"
  assert_success
}

# --- Edge cases ---

@test "missing --phase-dir flag exits with error" {
  run bash "$SUT"
  assert_failure
}

@test "nonexistent phase dir exits with error" {
  run bash "$SUT" --phase-dir "/nonexistent/dir"
  assert_failure
}

@test "no config defaults to backend only" {
  make_dept_ready "backend"
  run bash "$SUT" --phase-dir "$PHASE_DIR"
  assert_success
  local dept_count
  dept_count=$(echo "$output" | jq '.departments | length')
  [ "$dept_count" -eq 1 ]
}

@test "output is valid JSON" {
  make_dept_ready "backend"
  run bash "$SUT" --phase-dir "$PHASE_DIR" --config "$TEST_WORKDIR/config.json"
  assert_success
  echo "$output" | jq empty
}

@test "per-department status in output" {
  make_dept_ready "backend"
  run bash "$SUT" --phase-dir "$PHASE_DIR" --config "$TEST_WORKDIR/config.json"
  assert_success
  local dept
  dept=$(echo "$output" | jq -r '.departments[0].department')
  [ "$dept" = "backend" ]
}
