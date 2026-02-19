#!/usr/bin/env bats
# qa-gate-post-phase.bats — RED phase tests for scripts/qa-gate-post-phase.sh
# Plans 04-07 T2 (post-phase QA gate) + 04-10 T1 (config toggle)

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  mk_test_workdir
  # Consolidated dispatcher: qa-gate.sh --tier phase replaces qa-gate-post-phase.sh
  SUT="$SCRIPTS_DIR/qa-gate.sh"
  SUT_TIER_ARGS="--tier phase"
  PHASE_DIR="$TEST_WORKDIR/phase-test"
  mkdir -p "$PHASE_DIR"
  # Mock bin directory prepended to PATH for mock scripts
  MOCK_DIR="$TEST_WORKDIR/mock-bin"
  mkdir -p "$MOCK_DIR"
  export PATH="$MOCK_DIR:$PATH"
}

# Helper: create a plan + summary pair in PHASE_DIR
create_plan_with_summary() {
  local plan_id="$1" status="${2:-complete}"
  cat > "$PHASE_DIR/${plan_id}.plan.jsonl" <<JSONL
{"p":"04","n":"${plan_id}","t":"Test Plan ${plan_id}","w":1,"d":[],"mh":{},"obj":"test"}
{"id":"T1","tp":"auto","a":"dev","f":["scripts/a.sh"],"v":"ok","done":"ok","spec":"do stuff"}
JSONL
  cat > "$PHASE_DIR/${plan_id}.summary.jsonl" <<JSONL
{"p":"04","n":"${plan_id}","s":"${status}","fm":["scripts/a.sh"],"commits":["abc"],"desc":"Done"}
JSONL
}

# Helper: create a plan without summary
create_plan_no_summary() {
  local plan_id="$1"
  cat > "$PHASE_DIR/${plan_id}.plan.jsonl" <<JSONL
{"p":"04","n":"${plan_id}","t":"Test Plan ${plan_id}","w":1,"d":[],"mh":{},"obj":"test"}
{"id":"T1","tp":"auto","a":"dev","f":["scripts/a.sh"],"v":"ok","done":"ok","spec":"do stuff"}
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

# Helper: create mock resolve-qa-config.sh
mk_mock_qa_config() {
  local json="$1"
  cat > "$MOCK_DIR/resolve-qa-config.sh" <<SCRIPT
#!/usr/bin/env bash
echo '$json'
SCRIPT
  chmod +x "$MOCK_DIR/resolve-qa-config.sh"
}

# --- 04-07 T2: Post-phase QA gate (7 tests) ---

@test "passes when all plans complete and gates pass" {
  create_plan_with_summary "04-01" "complete"
  create_plan_with_summary "04-02" "complete"
  mk_mock_validate_gates '{"gate":"pass","steps":{"fl":0}}' 0
  mk_mock_test_summary "PASS (20 tests)" 0
  run bash "$SUT" $SUT_TIER_ARGS --phase-dir "$PHASE_DIR"
  assert_success
  local gate
  gate=$(echo "$output" | jq -r '.gate')
  [ "$gate" = "pass" ]
}

@test "fails when some plans incomplete" {
  create_plan_with_summary "04-01" "complete"
  create_plan_no_summary "04-02"
  mk_mock_test_summary "PASS (10 tests)" 0
  run bash "$SUT" $SUT_TIER_ARGS --phase-dir "$PHASE_DIR"
  assert_failure
  local complete total
  complete=$(echo "$output" | jq -r '.plans.complete')
  total=$(echo "$output" | jq -r '.plans.total')
  [ "$complete" -lt "$total" ]
}

@test "fails when validate-gates reports failures" {
  create_plan_with_summary "04-01" "complete"
  mk_mock_validate_gates '{"gate":"fail","steps":{"fl":2}}' 1
  mk_mock_test_summary "PASS (5 tests)" 0
  run bash "$SUT" $SUT_TIER_ARGS --phase-dir "$PHASE_DIR"
  assert_failure
  local step_failures
  step_failures=$(echo "$output" | jq -r '.steps.fl')
  [ "$step_failures" -gt 0 ]
}

@test "fails when test suite fails" {
  create_plan_with_summary "04-01" "complete"
  mk_mock_validate_gates '{"gate":"pass"}' 0
  mk_mock_test_summary "FAIL (5/20 failed)" 1
  run bash "$SUT" $SUT_TIER_ARGS --phase-dir "$PHASE_DIR"
  assert_failure
}

@test "reports correct plan counts in JSON" {
  create_plan_with_summary "04-01" "complete"
  create_plan_with_summary "04-02" "complete"
  create_plan_no_summary "04-03"
  mk_mock_validate_gates '{"gate":"pass"}' 0
  mk_mock_test_summary "PASS (10 tests)" 0
  run bash "$SUT" $SUT_TIER_ARGS --phase-dir "$PHASE_DIR"
  local total complete
  total=$(echo "$output" | jq -r '.plans.total')
  complete=$(echo "$output" | jq -r '.plans.complete')
  [ "$total" = "3" ]
  [ "$complete" = "2" ]
}

@test "handles no plan files gracefully" {
  # Empty phase dir with no plans
  run bash "$SUT" $SUT_TIER_ARGS --phase-dir "$PHASE_DIR"
  # Should handle gracefully (not crash), either pass with 0 plans or warn
  local exit_ok=false
  if [ "$status" -eq 0 ] || [ "$status" -eq 1 ]; then
    exit_ok=true
  fi
  [ "$exit_ok" = "true" ]
}

@test "appends to .qa-gate-results.jsonl" {
  create_plan_with_summary "04-01" "complete"
  mk_mock_validate_gates '{"gate":"pass"}' 0
  mk_mock_test_summary "PASS (5 tests)" 0
  run bash "$SUT" $SUT_TIER_ARGS --phase-dir "$PHASE_DIR"
  [ -f "$PHASE_DIR/.qa-gate-results.jsonl" ]
  local line_count
  line_count=$(wc -l < "$PHASE_DIR/.qa-gate-results.jsonl" | tr -d ' ')
  [ "$line_count" -ge 1 ]
  head -1 "$PHASE_DIR/.qa-gate-results.jsonl" | jq empty
}

# --- 04-10 T1: Config toggle tests (4 tests) ---

@test "skips with gate:skipped JSON when config toggle is false" {
  mk_mock_qa_config '{"post_phase":false}'
  run bash "$SUT" $SUT_TIER_ARGS --phase-dir "$PHASE_DIR"
  assert_success
  local gate
  gate=$(echo "$output" | jq -r '.gate')
  [ "$gate" = "skipped" ]
}

@test "runs normally when config toggle is true" {
  mk_mock_qa_config '{"post_phase":true}'
  create_plan_with_summary "04-01" "complete"
  mk_mock_validate_gates '{"gate":"pass"}' 0
  mk_mock_test_summary "PASS (1 tests)" 0
  run bash "$SUT" $SUT_TIER_ARGS --phase-dir "$PHASE_DIR"
  local gate
  gate=$(echo "$output" | jq -r '.gate')
  [ "$gate" != "skipped" ]
}

@test "defaults to enabled when resolve-qa-config.sh missing" {
  rm -f "$MOCK_DIR/resolve-qa-config.sh"
  create_plan_with_summary "04-01" "complete"
  mk_mock_validate_gates '{"gate":"pass"}' 0
  mk_mock_test_summary "PASS (1 tests)" 0
  run bash "$SUT" $SUT_TIER_ARGS --phase-dir "$PHASE_DIR"
  local gate
  gate=$(echo "$output" | jq -r '.gate')
  [ "$gate" != "skipped" ]
}

@test "uses timeout from config when present" {
  mk_mock_qa_config '{"timeout_seconds":5,"post_phase":true}'
  create_plan_with_summary "04-01" "complete"
  mk_mock_validate_gates '{"gate":"pass"}' 0
  mk_mock_test_summary "PASS (1 tests)" 0
  run bash "$SUT" $SUT_TIER_ARGS --phase-dir "$PHASE_DIR"
  assert_success
}
