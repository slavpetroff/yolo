#!/usr/bin/env bats
# qa-gate-post-task.bats — RED phase tests for scripts/qa-gate-post-task.sh
# Plans 04-06 T1 (post-task QA gate) + 04-10 T1 (config toggle)

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/qa-gate-post-task.sh"
  PHASE_DIR="$TEST_WORKDIR/phase-test"
  mkdir -p "$PHASE_DIR"
  # Mock bin directory prepended to PATH for mock scripts
  MOCK_DIR="$TEST_WORKDIR/mock-bin"
  mkdir -p "$MOCK_DIR"
  export PATH="$MOCK_DIR:$PATH"
}

# Helper: create mock test-summary.sh that outputs given string and exits with given code
mk_mock_test_summary() {
  local output_text="$1" exit_code="${2:-0}"
  cat > "$MOCK_DIR/test-summary.sh" <<SCRIPT
#!/usr/bin/env bash
echo "$output_text"
exit $exit_code
SCRIPT
  chmod +x "$MOCK_DIR/test-summary.sh"
}

# Helper: create mock bats binary
mk_mock_bats() {
  cat > "$MOCK_DIR/bats" <<'SCRIPT'
#!/usr/bin/env bash
echo "mock bats"
exit 0
SCRIPT
  chmod +x "$MOCK_DIR/bats"
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

# --- 04-06 T1: Post-task QA gate (9 tests) ---

@test "exits 0 and outputs pass JSON when test-summary returns PASS" {
  mk_mock_test_summary "PASS (10 tests)" 0
  mk_mock_bats
  run bash "$SUT" --phase-dir "$PHASE_DIR" --plan 04-06 --task T1
  assert_success
  local gate result pass_count
  gate=$(echo "$output" | jq -r '.gate')
  result=$(echo "$output" | jq -r '.r')
  pass_count=$(echo "$output" | jq -r '.tst.ps')
  [ "$gate" = "pass" ]
  [ "$result" = "PASS" ]
  [ "$pass_count" = "10" ]
}

@test "exits 1 and outputs fail JSON when test-summary returns FAIL" {
  mk_mock_test_summary "FAIL (2/10 failed)" 1
  mk_mock_bats
  run bash "$SUT" --phase-dir "$PHASE_DIR" --plan 04-06 --task T1
  assert_failure
  local gate result fail_count
  gate=$(echo "$output" | jq -r '.gate')
  result=$(echo "$output" | jq -r '.r')
  fail_count=$(echo "$output" | jq -r '.tst.fl')
  [ "$gate" = "fail" ]
  [ "$result" = "FAIL" ]
  [ "$fail_count" = "2" ]
}

@test "exits 0 with warn when bats not installed" {
  # Remove mock bats and use a clean PATH without real bats
  rm -f "$MOCK_DIR/bats"
  mk_mock_test_summary "PASS (1 tests)" 0
  # Use a PATH that excludes bats locations
  local clean_path="$MOCK_DIR:/usr/bin:/bin"
  run env PATH="$clean_path" bash "$SUT" --phase-dir "$PHASE_DIR" --plan 04-06 --task T1
  assert_success
  local gate
  gate=$(echo "$output" | jq -r '.gate')
  [ "$gate" = "warn" ]
}

@test "exits 0 with warn when test-summary.sh missing" {
  # Don't create mock test-summary.sh; ensure it's not findable
  rm -f "$MOCK_DIR/test-summary.sh"
  mk_mock_bats
  run bash "$SUT" --phase-dir "$PHASE_DIR" --plan 04-06 --task T1
  assert_success
  local gate
  gate=$(echo "$output" | jq -r '.gate')
  [ "$gate" = "warn" ]
}

@test "produces valid JSON parseable by jq" {
  mk_mock_test_summary "PASS (5 tests)" 0
  mk_mock_bats
  run bash "$SUT" --phase-dir "$PHASE_DIR" --plan 04-06 --task T1
  # Output must be valid JSON
  echo "$output" | jq empty
}

@test "includes plan and task fields in output" {
  mk_mock_test_summary "PASS (3 tests)" 0
  mk_mock_bats
  run bash "$SUT" --phase-dir "$PHASE_DIR" --plan 04-06 --task T1
  local plan task
  plan=$(echo "$output" | jq -r '.plan')
  task=$(echo "$output" | jq -r '.task')
  [ "$plan" = "04-06" ]
  [ "$task" = "T1" ]
}

@test "appends result to .qa-gate-results.jsonl" {
  mk_mock_test_summary "PASS (2 tests)" 0
  mk_mock_bats
  run bash "$SUT" --phase-dir "$PHASE_DIR" --plan 04-06 --task T1
  assert_success
  # Verify results file was created and is jq-parseable
  [ -f "$PHASE_DIR/.qa-gate-results.jsonl" ]
  local line_count
  line_count=$(wc -l < "$PHASE_DIR/.qa-gate-results.jsonl" | tr -d ' ')
  [ "$line_count" -ge 1 ]
  head -1 "$PHASE_DIR/.qa-gate-results.jsonl" | jq empty
}

@test "handles timeout gracefully as warn" {
  # Mock test-summary.sh that sleeps forever
  cat > "$MOCK_DIR/test-summary.sh" <<'SCRIPT'
#!/usr/bin/env bash
sleep 60
echo "PASS (1 tests)"
SCRIPT
  chmod +x "$MOCK_DIR/test-summary.sh"
  mk_mock_bats
  run bash "$SUT" --phase-dir "$PHASE_DIR" --plan 04-06 --task T1 --timeout 1
  assert_success
  local gate
  gate=$(echo "$output" | jq -r '.gate')
  [ "$gate" = "warn" ]
}

@test "works without --plan and --task flags" {
  mk_mock_test_summary "PASS (1 tests)" 0
  mk_mock_bats
  run bash "$SUT" --phase-dir "$PHASE_DIR"
  assert_success
}

# --- 04-10 T1: Config toggle tests (4 tests) ---

@test "skips with gate:skipped JSON when config toggle is false" {
  mk_mock_qa_config '{"post_task":false}'
  run bash "$SUT" --phase-dir "$PHASE_DIR"
  assert_success
  local gate
  gate=$(echo "$output" | jq -r '.gate')
  [ "$gate" = "skipped" ]
}

@test "runs normally when config toggle is true" {
  mk_mock_qa_config '{"post_task":true}'
  mk_mock_test_summary "PASS (1 tests)" 0
  mk_mock_bats
  run bash "$SUT" --phase-dir "$PHASE_DIR" --plan 04-06 --task T1
  local gate
  gate=$(echo "$output" | jq -r '.gate')
  [ "$gate" != "skipped" ]
}

@test "defaults to enabled when resolve-qa-config.sh missing" {
  rm -f "$MOCK_DIR/resolve-qa-config.sh"
  mk_mock_test_summary "PASS (1 tests)" 0
  mk_mock_bats
  run bash "$SUT" --phase-dir "$PHASE_DIR" --plan 04-06 --task T1
  local gate
  gate=$(echo "$output" | jq -r '.gate')
  [ "$gate" != "skipped" ]
}

@test "uses timeout from config when present" {
  mk_mock_qa_config '{"timeout_seconds":5,"post_task":true}'
  mk_mock_test_summary "PASS (1 tests)" 0
  mk_mock_bats
  run bash "$SUT" --phase-dir "$PHASE_DIR" --plan 04-06 --task T1
  assert_success
}
