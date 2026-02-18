#!/usr/bin/env bats
# integration-gate.bats — Unit tests for scripts/integration-gate.sh
# Barrier convergence for cross-department integration validation.

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/integration-gate.sh"
  PHASE_DIR="$TEST_WORKDIR/.yolo-planning/phases/05-test"
  mkdir -p "$PHASE_DIR"

  # Config with all departments active
  CONFIG="$TEST_WORKDIR/config.json"
  cat > "$CONFIG" <<'EOF'
{"departments":{"backend":true,"frontend":true,"uiux":true}}
EOF
}

# Helper: mark a department as complete
mk_dept_complete() {
  local dept="$1"
  echo "{\"dept\":\"$dept\",\"status\":\"complete\",\"step\":\"signoff\"}" > "$PHASE_DIR/.dept-status-${dept}.json"
  touch "$PHASE_DIR/.handoff-${dept}-complete"
}

# Helper: mark all departments complete
mk_all_depts_complete() {
  mk_dept_complete backend
  mk_dept_complete frontend
  mk_dept_complete uiux
}

# --- Pass scenarios ---

@test "gate passes when all dept statuses complete and cross-checks pass" {
  mk_all_depts_complete
  # API contracts all agreed
  echo '{"endpoint":"/api/users","status":"agreed"}' > "$PHASE_DIR/api-contracts.jsonl"
  # Design handoff with no ready entries needing summary verification
  echo '{"component":"Button","status":"delivered"}' > "$PHASE_DIR/design-handoff.jsonl"
  # Test results all passing
  echo '{"plan":"05-01","dept":"backend","fl":0,"ps":5}' > "$PHASE_DIR/test-results.jsonl"

  run bash "$SUT" --phase-dir "$PHASE_DIR" --config "$CONFIG"
  assert_success
  # Verify output is valid JSON with gate=pass
  echo "$output" | jq -e '.gate == "pass"'
}

# --- Fail scenarios ---

@test "gate fails when a dept status file is missing" {
  mk_dept_complete backend
  mk_dept_complete frontend
  # uiux has no dept-status file
  run bash "$SUT" --phase-dir "$PHASE_DIR" --config "$CONFIG"
  assert_failure
  echo "$output" | jq -e '.departments.uiux == "pending"'
}

@test "gate fails when api-contracts.jsonl has proposed entries" {
  mk_all_depts_complete
  echo '{"endpoint":"/api/users","status":"proposed"}' > "$PHASE_DIR/api-contracts.jsonl"

  run bash "$SUT" --phase-dir "$PHASE_DIR" --config "$CONFIG"
  assert_success
  # Gate should report fail for api cross-check
  echo "$output" | jq -e '.cross_checks.api == "fail"'
  echo "$output" | jq -e '.gate == "fail"'
}

@test "gate fails when design-handoff.jsonl has ready entries but no summaries" {
  mk_all_depts_complete
  echo '{"component":"Button","status":"ready"}' > "$PHASE_DIR/design-handoff.jsonl"
  # No summary.jsonl files exist

  run bash "$SUT" --phase-dir "$PHASE_DIR" --config "$CONFIG"
  assert_success
  echo "$output" | jq -e '.cross_checks.design == "fail"'
}

# --- Timeout ---

@test "gate returns timeout JSON when departments not all complete" {
  mk_dept_complete backend
  # frontend and uiux not complete
  run bash "$SUT" --phase-dir "$PHASE_DIR" --config "$CONFIG" --timeout 120
  assert_failure
  echo "$output" | jq -e '.gate == "timeout"'
  echo "$output" | jq -e '.timeout_remaining == 120'
}

# --- Single-dept mode ---

@test "single-dept mode skips cross-dept checks" {
  # Config with only backend
  cat > "$CONFIG" <<'EOF'
{"departments":{"backend":true,"frontend":false,"uiux":false}}
EOF
  mk_dept_complete backend
  # api-contracts with proposed status should NOT cause fail in single-dept mode
  echo '{"endpoint":"/api/users","status":"proposed"}' > "$PHASE_DIR/api-contracts.jsonl"

  run bash "$SUT" --phase-dir "$PHASE_DIR" --config "$CONFIG"
  assert_success
  echo "$output" | jq -e '.gate == "pass"'
  # API check should be skipped in single-dept mode
  echo "$output" | jq -e '.cross_checks.api == "skip"'
}

# --- Schema validation ---

@test "gate output JSON has correct schema fields" {
  mk_all_depts_complete
  run bash "$SUT" --phase-dir "$PHASE_DIR" --config "$CONFIG"
  assert_success
  # Verify all required fields present
  echo "$output" | jq -e 'has("gate")'
  echo "$output" | jq -e 'has("departments")'
  echo "$output" | jq -e 'has("cross_checks")'
  echo "$output" | jq -e 'has("timeout_remaining")'
  echo "$output" | jq -e 'has("dt")'
}

# --- Test results failure ---

@test "gate fails when test-results.jsonl has failures" {
  mk_all_depts_complete
  echo '{"plan":"05-01","dept":"backend","fl":3,"ps":5}' > "$PHASE_DIR/test-results.jsonl"

  run bash "$SUT" --phase-dir "$PHASE_DIR" --config "$CONFIG"
  assert_success
  echo "$output" | jq -e '.cross_checks.tests == "fail"'
  echo "$output" | jq -e '.gate == "fail"'
}

# --- Error handling ---

@test "exits 1 when phase-dir does not exist" {
  run bash "$SUT" --phase-dir "/nonexistent/path" --config "$CONFIG"
  assert_failure
}

@test "exits 1 when config file does not exist" {
  run bash "$SUT" --phase-dir "$PHASE_DIR" --config "/nonexistent/config.json"
  assert_failure
}
