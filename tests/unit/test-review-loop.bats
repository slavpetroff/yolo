#!/usr/bin/env bats
# test-review-loop.bats — Unit tests for scripts/review-loop.sh
# Tests: approve/changes_requested/escalation paths, config overrides, plan filtering.

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/review-loop.sh"
}

# Helper: create code-review.jsonl with verdict + optional findings
mk_code_review() {
  local phase_dir="$1" plan="$2" result="$3" cycle="${4:-1}"
  shift 4
  # Write verdict line
  jq -n --arg plan "$plan" --arg r "$result" --argjson cycle "$cycle" \
    --arg dt "2026-02-18" \
    '{plan:$plan,r:$r,cycle:$cycle,tdd:"pass",dt:$dt}' \
    > "$phase_dir/code-review.jsonl"
  # Append finding lines if any
  while [[ $# -gt 0 ]]; do
    jq -n --arg plan "$plan" --arg f "$1" --arg sev "${2:-minor}" --arg issue "${3:-test issue}" \
      '{plan:$plan,f:$f,sev:$sev,issue:$issue}' \
      >> "$phase_dir/code-review.jsonl"
    shift 3 || break
  done
}

# Helper: create config with review_loop settings
mk_review_config() {
  local max_cycles="${1:-2}"
  jq -n --argjson mc "$max_cycles" \
    '{review_loop:{max_cycles:$mc}}' \
    > "$TEST_WORKDIR/config.json"
}

# --- First cycle approve ---

@test "first cycle approve: exits 0 with result approve" {
  local phase_dir="$TEST_WORKDIR/phase"
  mkdir -p "$phase_dir"
  mk_code_review "$phase_dir" "01-01" "approve" 1
  run bash "$SUT" --phase-dir "$phase_dir" --plan-id "01-01"
  assert_success
  local result
  result=$(echo "$output" | jq -r '.result')
  assert_equal "$result" "approve"
  local cycles_used
  cycles_used=$(echo "$output" | jq '.cycles_used')
  assert_equal "$cycles_used" "1"
}

# --- First cycle changes_requested ---

@test "first cycle changes_requested: exits 0 with status, does not escalate" {
  local phase_dir="$TEST_WORKDIR/phase"
  mkdir -p "$phase_dir"
  mk_code_review "$phase_dir" "01-01" "changes_requested" 1 \
    "src/auth.ts" "major" "Missing error handling"
  run bash "$SUT" --phase-dir "$phase_dir" --plan-id "01-01"
  assert_success
  local status
  status=$(echo "$output" | jq -r '.status')
  assert_equal "$status" "changes_requested"
  local cycle
  cycle=$(echo "$output" | jq '.cycle')
  assert_equal "$cycle" "1"
}

# --- Second cycle approve ---

@test "second cycle approve: exits 0, cycles_used 2" {
  local phase_dir="$TEST_WORKDIR/phase"
  mkdir -p "$phase_dir"
  mk_code_review "$phase_dir" "01-01" "approve" 2
  run bash "$SUT" --phase-dir "$phase_dir" --plan-id "01-01"
  assert_success
  local result
  result=$(echo "$output" | jq -r '.result')
  assert_equal "$result" "approve"
  local cycles_used
  cycles_used=$(echo "$output" | jq '.cycles_used')
  assert_equal "$cycles_used" "2"
}

# --- Second cycle still changes_requested → escalated ---

@test "second cycle changes_requested: exits 1 with result escalated" {
  local phase_dir="$TEST_WORKDIR/phase"
  mkdir -p "$phase_dir"
  mk_code_review "$phase_dir" "01-01" "changes_requested" 2
  run bash "$SUT" --phase-dir "$phase_dir" --plan-id "01-01"
  assert_failure
  local result
  result=$(echo "$output" | jq -r '.result')
  assert_equal "$result" "escalated"
  local reason
  reason=$(echo "$output" | jq -r '.reason')
  assert_equal "$reason" "max cycles exceeded"
}

# --- Missing code-review.jsonl ---

@test "missing code-review.jsonl: exits 1 with error" {
  local phase_dir="$TEST_WORKDIR/phase"
  mkdir -p "$phase_dir"
  run bash "$SUT" --phase-dir "$phase_dir" --plan-id "01-01"
  assert_failure
  local result
  result=$(echo "$output" | jq -r '.result')
  assert_equal "$result" "pending"
}

# --- Custom max_cycles from config ---

@test "custom max_cycles from config: respects config override" {
  local phase_dir="$TEST_WORKDIR/phase"
  mkdir -p "$phase_dir"
  mk_review_config 3
  mk_code_review "$phase_dir" "01-01" "changes_requested" 2
  # With max_cycles=3, cycle 2 changes_requested should NOT escalate
  run bash "$SUT" --phase-dir "$phase_dir" --plan-id "01-01" --config "$TEST_WORKDIR/config.json"
  assert_success
  local status
  status=$(echo "$output" | jq -r '.status')
  assert_equal "$status" "changes_requested"
}

# --- Plan ID filtering ---

@test "plan ID filtering: only reads verdict for specified plan" {
  local phase_dir="$TEST_WORKDIR/phase"
  mkdir -p "$phase_dir"
  # Write verdicts for two different plans
  jq -n '{plan:"01-01",r:"changes_requested",cycle:2,tdd:"pass",dt:"2026-02-18"}' \
    > "$phase_dir/code-review.jsonl"
  jq -n '{plan:"01-02",r:"approve",cycle:1,tdd:"pass",dt:"2026-02-18"}' \
    >> "$phase_dir/code-review.jsonl"
  # Query for 01-02 should get approve
  run bash "$SUT" --phase-dir "$phase_dir" --plan-id "01-02"
  assert_success
  local result
  result=$(echo "$output" | jq -r '.result')
  assert_equal "$result" "approve"
}

# --- Missing required flags ---

@test "missing required flags: exits with error" {
  run bash "$SUT"
  assert_failure
}
