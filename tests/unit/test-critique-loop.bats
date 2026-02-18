#!/usr/bin/env bats
# test-critique-loop.bats — Unit tests for scripts/critique-loop.sh
# Tests: 3-round hard cap, early exit on high confidence, config reading, default values.

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/critique-loop.sh"
}

# Helper: create config with critique settings
mk_critique_config() {
  local max_rounds="${1:-3}" threshold="${2:-85}"
  mkdir -p "$TEST_WORKDIR/.yolo-planning"
  jq -n --argjson mr "$max_rounds" --argjson ct "$threshold" \
    '{critique:{max_rounds:$mr,confidence_threshold:$ct}}' \
    > "$TEST_WORKDIR/config.json"
}

# Helper: create critique.jsonl with entries for specific rounds and confidence
mk_critique_jsonl() {
  local phase_dir="$1"
  shift
  # Remaining args: "round:confidence:count" triplets
  > "$phase_dir/critique.jsonl"
  while [[ $# -gt 0 ]]; do
    IFS=':' read -r round conf count <<< "$1"
    for ((i = 0; i < count; i++)); do
      jq -n --argjson rd "$round" --argjson cf "$conf" \
        '{id:("F" + ($rd | tostring) + "-" + ('"$i"' | tostring)),rd:$rd,cf:$cf,sev:"medium",q:"test finding"}' \
        >> "$phase_dir/critique.jsonl"
    done
    shift
  done
}

# Helper: run critique-loop with standard flags
run_critique() {
  local phase_dir="${1:-$TEST_WORKDIR/phase}"
  local config="${2:-$TEST_WORKDIR/config.json}"
  local role="${3:-critic}"
  run bash "$SUT" --phase-dir "$phase_dir" --config "$config" --role "$role"
}

# --- 3-round hard cap ---

@test "3-round hard cap: runs all 3 rounds when confidence stays low" {
  mk_critique_config 3 85
  local phase_dir="$TEST_WORKDIR/phase"
  mkdir -p "$phase_dir"
  # Create critique.jsonl with low confidence across 3 rounds
  mk_critique_jsonl "$phase_dir" "1:50:2" "2:60:2" "3:70:2"
  run_critique "$phase_dir"
  assert_success
  local rounds_used
  rounds_used=$(echo "$output" | jq '.rounds_used')
  assert_equal "$rounds_used" "3"
  local early_exit
  early_exit=$(echo "$output" | jq '.early_exit')
  assert_equal "$early_exit" "false"
}

# --- Early exit round 1 ---

@test "early exit on round 1: confidence >= threshold" {
  mk_critique_config 3 85
  local phase_dir="$TEST_WORKDIR/phase"
  mkdir -p "$phase_dir"
  mk_critique_jsonl "$phase_dir" "1:90:1"
  run_critique "$phase_dir"
  assert_success
  local rounds_used
  rounds_used=$(echo "$output" | jq '.rounds_used')
  assert_equal "$rounds_used" "1"
  local early_exit
  early_exit=$(echo "$output" | jq '.early_exit')
  assert_equal "$early_exit" "true"
}

# --- Early exit round 2 ---

@test "early exit on round 2: low round 1 then high round 2" {
  mk_critique_config 3 85
  local phase_dir="$TEST_WORKDIR/phase"
  mkdir -p "$phase_dir"
  mk_critique_jsonl "$phase_dir" "1:60:2" "2:88:1"
  run_critique "$phase_dir"
  assert_success
  local rounds_used
  rounds_used=$(echo "$output" | jq '.rounds_used')
  assert_equal "$rounds_used" "2"
  local early_exit
  early_exit=$(echo "$output" | jq '.early_exit')
  assert_equal "$early_exit" "true"
}

# --- Config reading ---

@test "reads max_rounds from config" {
  mk_critique_config 2 85
  local phase_dir="$TEST_WORKDIR/phase"
  mkdir -p "$phase_dir"
  mk_critique_jsonl "$phase_dir" "1:50:1" "2:50:1"
  run_critique "$phase_dir"
  assert_success
  local rounds_used
  rounds_used=$(echo "$output" | jq '.rounds_used')
  assert_equal "$rounds_used" "2"
}

@test "reads confidence_threshold from config" {
  mk_critique_config 3 50
  local phase_dir="$TEST_WORKDIR/phase"
  mkdir -p "$phase_dir"
  # confidence 60 exceeds threshold 50 — should exit round 1
  mk_critique_jsonl "$phase_dir" "1:60:1"
  run_critique "$phase_dir"
  assert_success
  local early_exit
  early_exit=$(echo "$output" | jq '.early_exit')
  assert_equal "$early_exit" "true"
}

# --- Default values when config absent ---

@test "defaults to 3 rounds and 85 threshold when config missing" {
  local phase_dir="$TEST_WORKDIR/phase"
  mkdir -p "$phase_dir"
  mk_critique_jsonl "$phase_dir" "1:50:1" "2:60:1" "3:70:1"
  run_critique "$phase_dir" "$TEST_WORKDIR/nonexistent.json"
  assert_success
  local rounds_used
  rounds_used=$(echo "$output" | jq '.rounds_used')
  assert_equal "$rounds_used" "3"
  local early_exit
  early_exit=$(echo "$output" | jq '.early_exit')
  assert_equal "$early_exit" "false"
}

@test "defaults to 3 rounds when critique config key absent" {
  mkdir -p "$TEST_WORKDIR"
  echo '{}' > "$TEST_WORKDIR/config.json"
  local phase_dir="$TEST_WORKDIR/phase"
  mkdir -p "$phase_dir"
  mk_critique_jsonl "$phase_dir" "1:50:1" "2:50:1" "3:50:1"
  run_critique "$phase_dir" "$TEST_WORKDIR/config.json"
  assert_success
  local rounds_used
  rounds_used=$(echo "$output" | jq '.rounds_used')
  assert_equal "$rounds_used" "3"
}

# --- Invalid role ---

@test "invalid role exits with error" {
  mk_critique_config 3 85
  local phase_dir="$TEST_WORKDIR/phase"
  mkdir -p "$phase_dir"
  run_critique "$phase_dir" "$TEST_WORKDIR/config.json" "invalid-role"
  assert_failure
}

# --- Missing flags ---

@test "missing required flags exits with error" {
  run bash "$SUT"
  assert_failure
}

# --- Hard cap enforcement: max_rounds > 3 capped to 3 ---

@test "max_rounds > 3 in config is capped to 3" {
  mk_critique_config 10 85
  local phase_dir="$TEST_WORKDIR/phase"
  mkdir -p "$phase_dir"
  mk_critique_jsonl "$phase_dir" "1:50:1" "2:50:1" "3:50:1"
  run_critique "$phase_dir"
  assert_success
  local rounds_used
  rounds_used=$(echo "$output" | jq '.rounds_used')
  assert_equal "$rounds_used" "3"
}
