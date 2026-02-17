#!/usr/bin/env bats
# qa-gate-post-plan.bats — RED phase tests for scripts/qa-gate-post-plan.sh
# Plans 04-07 T1 (post-plan QA gate) + 04-10 T1 (config toggle)

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/qa-gate-post-plan.sh"
  PHASE_DIR="$TEST_WORKDIR/phase-test"
  mkdir -p "$PHASE_DIR"
  # Mock bin directory prepended to PATH for mock scripts
  MOCK_DIR="$TEST_WORKDIR/mock-bin"
  mkdir -p "$MOCK_DIR"
  export PATH="$MOCK_DIR:$PATH"
}

# Helper: create a valid plan.jsonl + summary.jsonl pair
create_plan_and_summary() {
  local plan_id="${1:-04-07}"
  # Write plan header + task lines
  cat > "$PHASE_DIR/${plan_id}.plan.jsonl" <<JSONL
{"p":"04","n":"${plan_id}","t":"Test Plan","w":1,"d":[],"mh":{},"obj":"test plan gate"}
{"id":"T1","tp":"auto","a":"dev","f":["scripts/qa-gate-post-plan.sh"],"v":"ok","done":"ok","spec":"implement gate"}
JSONL
  # Write summary with s:complete
  cat > "$PHASE_DIR/${plan_id}.summary.jsonl" <<JSONL
{"p":"04","n":"${plan_id}","s":"complete","fm":["scripts/qa-gate-post-plan.sh"],"commits":["abc1234"],"desc":"Implemented post-plan gate"}
JSONL
}

# Helper: create mock test-summary.sh
mk_mock_test_summary() {
  local output_text="$1" exit_code="${2:-0}"
  cat > "$MOCK_DIR/test-summary.sh" <<SCRIPT
#!/usr/bin/env bash
echo "$output_text"
exit $exit_code
SCRIPT
  chmod +x "$MOCK_DIR/test-summary.sh"
}

# Helper: create mock resolve-qa-config.sh
mk_mock_qa_config() {
  local json="$1"
  cat > "$MOCK_DIR/resolve-qa-config.sh" <<SCRIPT
#!/usr/bin/env bash
echo '$json'
SCRIPT
  chmod +x "$MOCK_DIR/resolve-qa-config.sh"
}

# Helper: create mock validate-gates.sh
mk_mock_validate_gates() {
  local output_text="$1" exit_code="${2:-0}"
  cat > "$MOCK_DIR/validate-gates.sh" <<SCRIPT
#!/usr/bin/env bash
echo "$output_text"
exit $exit_code
SCRIPT
  chmod +x "$MOCK_DIR/validate-gates.sh"
}

# --- 04-07 T1: Post-plan QA gate (7 tests) ---

@test "passes when summary exists with s:complete and tests pass" {
  create_plan_and_summary "04-07"
  mk_mock_test_summary "PASS (5 tests)" 0
  run bash "$SUT" --phase-dir "$PHASE_DIR" --plan 04-07
  assert_success
  local gate
  gate=$(echo "$output" | jq -r '.gate')
  [ "$gate" = "pass" ]
}

@test "fails when summary.jsonl missing" {
  # Create plan but no summary
  cat > "$PHASE_DIR/04-07.plan.jsonl" <<'JSONL'
{"p":"04","n":"04-07","t":"Test Plan","w":1,"d":[],"mh":{},"obj":"test"}
{"id":"T1","tp":"auto","a":"dev","f":["scripts/a.sh"],"v":"ok","done":"ok","spec":"do stuff"}
JSONL
  run bash "$SUT" --phase-dir "$PHASE_DIR" --plan 04-07
  assert_failure
  [[ "$output" =~ "summary" ]] || [[ "$output" == *"missing"* ]] || echo "$output" | jq -r '.r' | grep -qi "fail"
}

@test "fails when summary has s:partial" {
  cat > "$PHASE_DIR/04-07.plan.jsonl" <<'JSONL'
{"p":"04","n":"04-07","t":"Test Plan","w":1,"d":[],"mh":{},"obj":"test"}
{"id":"T1","tp":"auto","a":"dev","f":["scripts/a.sh"],"v":"ok","done":"ok","spec":"do stuff"}
JSONL
  cat > "$PHASE_DIR/04-07.summary.jsonl" <<'JSONL'
{"p":"04","n":"04-07","s":"partial","fm":[],"commits":[],"desc":"Incomplete"}
JSONL
  run bash "$SUT" --phase-dir "$PHASE_DIR" --plan 04-07
  assert_failure
}

@test "verifies must_have artifacts exist" {
  # Create plan with mh.ar pointing to a file, then create that file
  cat > "$PHASE_DIR/04-07.plan.jsonl" <<JSONL
{"p":"04","n":"04-07","t":"Test Plan","w":1,"d":[],"mh":{"ar":["$PHASE_DIR/required-artifact.jsonl"]},"obj":"test"}
{"id":"T1","tp":"auto","a":"dev","f":["scripts/a.sh"],"v":"ok","done":"ok","spec":"do stuff"}
JSONL
  cat > "$PHASE_DIR/04-07.summary.jsonl" <<'JSONL'
{"p":"04","n":"04-07","s":"complete","fm":["scripts/a.sh"],"commits":["abc"],"desc":"Done"}
JSONL
  echo '{}' > "$PHASE_DIR/required-artifact.jsonl"
  mk_mock_test_summary "PASS (1 tests)" 0
  run bash "$SUT" --phase-dir "$PHASE_DIR" --plan 04-07
  assert_success
}

@test "reports must_have artifact missing" {
  cat > "$PHASE_DIR/04-07.plan.jsonl" <<JSONL
{"p":"04","n":"04-07","t":"Test Plan","w":1,"d":[],"mh":{"ar":["$PHASE_DIR/nonexistent-artifact.jsonl"]},"obj":"test"}
{"id":"T1","tp":"auto","a":"dev","f":["scripts/a.sh"],"v":"ok","done":"ok","spec":"do stuff"}
JSONL
  cat > "$PHASE_DIR/04-07.summary.jsonl" <<'JSONL'
{"p":"04","n":"04-07","s":"complete","fm":["scripts/a.sh"],"commits":["abc"],"desc":"Done"}
JSONL
  mk_mock_test_summary "PASS (1 tests)" 0
  run bash "$SUT" --phase-dir "$PHASE_DIR" --plan 04-07
  # Verify mh counts appear in output
  echo "$output" | jq -e '.mh' >/dev/null 2>&1 || [[ "$output" =~ "missing" ]]
}

@test "handles test failure by reporting fail" {
  create_plan_and_summary "04-07"
  mk_mock_test_summary "FAIL (3/10 failed)" 1
  run bash "$SUT" --phase-dir "$PHASE_DIR" --plan 04-07
  assert_failure
  local fail_count
  fail_count=$(echo "$output" | jq -r '.tst.fl')
  [ "$fail_count" -gt 0 ]
}

@test "appends result to .qa-gate-results.jsonl" {
  create_plan_and_summary "04-07"
  mk_mock_test_summary "PASS (2 tests)" 0
  run bash "$SUT" --phase-dir "$PHASE_DIR" --plan 04-07
  assert_success
  [ -f "$PHASE_DIR/.qa-gate-results.jsonl" ]
  local line_count
  line_count=$(wc -l < "$PHASE_DIR/.qa-gate-results.jsonl" | tr -d ' ')
  [ "$line_count" -ge 1 ]
  head -1 "$PHASE_DIR/.qa-gate-results.jsonl" | jq empty
}

# --- 04-10 T1: Config toggle tests (4 tests) ---

@test "skips with gate:skipped JSON when config toggle is false" {
  mk_mock_qa_config '{"post_plan":false}'
  run bash "$SUT" --phase-dir "$PHASE_DIR" --plan 04-07
  assert_success
  local gate
  gate=$(echo "$output" | jq -r '.gate')
  [ "$gate" = "skipped" ]
}

@test "runs normally when config toggle is true" {
  mk_mock_qa_config '{"post_plan":true}'
  create_plan_and_summary "04-07"
  mk_mock_test_summary "PASS (1 tests)" 0
  run bash "$SUT" --phase-dir "$PHASE_DIR" --plan 04-07
  local gate
  gate=$(echo "$output" | jq -r '.gate')
  [ "$gate" != "skipped" ]
}

@test "defaults to enabled when resolve-qa-config.sh missing" {
  rm -f "$MOCK_DIR/resolve-qa-config.sh"
  create_plan_and_summary "04-07"
  mk_mock_test_summary "PASS (1 tests)" 0
  run bash "$SUT" --phase-dir "$PHASE_DIR" --plan 04-07
  local gate
  gate=$(echo "$output" | jq -r '.gate')
  [ "$gate" != "skipped" ]
}

@test "uses timeout from config when present" {
  mk_mock_qa_config '{"timeout_seconds":5,"post_plan":true}'
  create_plan_and_summary "04-07"
  mk_mock_test_summary "PASS (1 tests)" 0
  run bash "$SUT" --phase-dir "$PHASE_DIR" --plan 04-07
  assert_success
}
