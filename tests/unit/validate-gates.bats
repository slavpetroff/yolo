#!/usr/bin/env bats
# validate-gates.bats — Unit tests for scripts/validate-gates.sh
# Validates verification gate artifacts per execute-protocol.md enforcement contract.

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/validate-gates.sh"
  PHASE_DIR="$TEST_WORKDIR/phase-test"
  mkdir -p "$PHASE_DIR"
}

# Helper: create .execution-state.json with a step set to skipped
mk_exec_state_with_skip() {
  local step_name="$1"
  jq -n --arg s "$step_name" \
    '{steps:{($s):{status:"skipped",started_at:"",completed_at:"",artifact:"",reason:"skipped by flag"}}}' \
    > "$PHASE_DIR/.execution-state.json"
}

# Helper: create .qa-gate-results.jsonl with given level and result
create_gate_results() {
  local level="$1" result="$2"
  echo "{\"gl\":\"$level\",\"r\":\"$result\",\"dt\":\"2026-02-17\"}" > "$PHASE_DIR/.qa-gate-results.jsonl"
}

@test "critique gate passes when phase dir exists" {
  run bash "$SUT" --step critique --phase-dir "$PHASE_DIR"
  assert_success
  local gate
  gate=$(echo "$output" | jq -r '.gate')
  [ "$gate" = "pass" ]
}

@test "architecture gate passes with critique.jsonl" {
  echo '{"id":"C1","cat":"gap","sev":"minor","q":"test","ctx":"","sug":"","st":"open"}' > "$PHASE_DIR/critique.jsonl"
  run bash "$SUT" --step architecture --phase-dir "$PHASE_DIR"
  assert_success
}

@test "architecture gate passes when critique skipped" {
  mk_exec_state_with_skip "critique"
  run bash "$SUT" --step architecture --phase-dir "$PHASE_DIR"
  assert_success
}

@test "architecture gate fails without critique.jsonl or skip" {
  run bash "$SUT" --step architecture --phase-dir "$PHASE_DIR"
  assert_failure
  local missing
  missing=$(echo "$output" | jq -r '.missing[0]')
  [ "$missing" = "critique.jsonl" ]
}

@test "design_review gate passes with plan.jsonl" {
  cat > "$PHASE_DIR/01-01.plan.jsonl" <<'JSONL'
{"p":"01","n":"01","t":"Test","w":1,"d":[],"mh":{},"obj":"test"}
{"id":"T1","tp":"auto","a":"test","f":["src/a.sh"],"v":"ok","done":"ok","spec":"do stuff"}
JSONL
  run bash "$SUT" --step design_review --phase-dir "$PHASE_DIR"
  assert_success
}

@test "design_review gate fails without plan files" {
  run bash "$SUT" --step design_review --phase-dir "$PHASE_DIR"
  assert_failure
}

@test "qa gate passes with approved code-review" {
  echo '{"r":"approve","plan":"01-01","cycle":1,"dt":"2026-02-16"}' > "$PHASE_DIR/code-review.jsonl"
  run bash "$SUT" --step qa --phase-dir "$PHASE_DIR"
  assert_success
}

@test "qa gate fails with changes_requested code-review" {
  echo '{"r":"changes_requested","plan":"01-01","cycle":1,"dt":"2026-02-16"}' > "$PHASE_DIR/code-review.jsonl"
  run bash "$SUT" --step qa --phase-dir "$PHASE_DIR"
  assert_failure
}

@test "unknown step name exits with error" {
  run bash "$SUT" --step nonexistent --phase-dir "$PHASE_DIR"
  assert_failure
  assert_output --partial "Unknown step"
}

@test "security gate passes when qa step skipped" {
  mk_exec_state_with_skip "qa"
  run bash "$SUT" --step security --phase-dir "$PHASE_DIR"
  assert_success
}

# --- 04-10 T2/T3: post_task_qa and post_plan_qa gate validation (7 tests) ---

@test "post_task_qa gate passes when .qa-gate-results.jsonl has post-task entry" {
  create_gate_results "post-task" "PASS"
  run bash "$SUT" --step post_task_qa --phase-dir "$PHASE_DIR"
  assert_success
}

@test "post_task_qa gate fails when .qa-gate-results.jsonl missing" {
  # No .qa-gate-results.jsonl file
  run bash "$SUT" --step post_task_qa --phase-dir "$PHASE_DIR"
  assert_failure
  [[ "$output" =~ ".qa-gate-results.jsonl" ]] || echo "$output" | jq -r '.missing[0]' | grep -q "qa-gate-results"
}

@test "post_task_qa gate fails when file exists but no post-task entries" {
  # Create file with only post-plan entry, no post-task
  create_gate_results "post-plan" "PASS"
  run bash "$SUT" --step post_task_qa --phase-dir "$PHASE_DIR"
  assert_failure
}

@test "post_task_qa gate passes when step is skipped" {
  mk_exec_state_with_skip "post_task_qa"
  run bash "$SUT" --step post_task_qa --phase-dir "$PHASE_DIR"
  assert_success
}

@test "post_plan_qa gate passes when .qa-gate-results.jsonl has post-plan entry" {
  create_gate_results "post-plan" "PASS"
  run bash "$SUT" --step post_plan_qa --phase-dir "$PHASE_DIR"
  assert_success
}

@test "post_plan_qa gate fails when .qa-gate-results.jsonl missing" {
  run bash "$SUT" --step post_plan_qa --phase-dir "$PHASE_DIR"
  assert_failure
}

@test "post_plan_qa gate passes when step is skipped" {
  mk_exec_state_with_skip "post_plan_qa"
  run bash "$SUT" --step post_plan_qa --phase-dir "$PHASE_DIR"
  assert_success
}
