#!/usr/bin/env bats
# check-phase-status.bats — Unit tests for scripts/db/check-phase-status.sh

setup() {
  load '../../test_helper/common'
  load '../../test_helper/db_helper'
  SUT="$SCRIPTS_DIR/db/check-phase-status.sh"
  mk_test_db

  # Seed: phase 09, 2 plans, 5 tasks total
  db_insert_plan "09" "09-01" "Auth module"
  db_insert_task "09-01" "T1" "Create auth" "complete"
  db_insert_task "09-01" "T2" "Add JWT" "complete"
  db_insert_task "09-01" "T3" "Write tests" "in_progress"

  db_insert_plan "09" "09-02" "Logging"
  db_insert_task "09-02" "T1" "Create logger" "pending" "[]"
  db_insert_task "09-02" "T2" "Add transport" "pending" '["T1"]'

  # Mark 09-01 as complete in summaries
  db_insert_summary "09-01" "complete"
}

@test "correct total counts" {
  run bash "$SUT" "09" --db "$TEST_DB"
  assert_success
  assert_output --partial "plans: 1/2 complete"
  assert_output --partial "tasks: 2/5 complete (40%)"
}

@test "shows blocked count" {
  run bash "$SUT" "09" --db "$TEST_DB"
  assert_success
  assert_output --partial "blocked: 1"
}

@test "shows in_progress count" {
  run bash "$SUT" "09" --db "$TEST_DB"
  assert_success
  assert_output --partial "in_progress: 1"
}

@test "percentage calculation is correct" {
  run bash "$SUT" "09" --db "$TEST_DB"
  assert_success
  # 2 of 5 = 40%
  assert_output --partial "40%"
}

@test "JSON output mode" {
  run bash "$SUT" "09" --json --db "$TEST_DB"
  assert_success
  # Validate JSON structure
  echo "$output" | jq -e '.phase == "09"'
  echo "$output" | jq -e '.total_plans == 2'
  echo "$output" | jq -e '.completed_plans == 1'
  echo "$output" | jq -e '.total_tasks == 5'
  echo "$output" | jq -e '.completed_tasks == 2'
  echo "$output" | jq -e '.completion_pct == 40'
}

@test "JSON output includes per-plan breakdown" {
  run bash "$SUT" "09" --json --db "$TEST_DB"
  assert_success
  echo "$output" | jq -e '.plans | length == 2'
  echo "$output" | jq -e '.plans[0].plan == "09-01"'
}

@test "per-plan breakdown in TOON format" {
  run bash "$SUT" "09" --db "$TEST_DB"
  assert_success
  assert_output --partial "09-01: 2/3 (complete)"
  assert_output --partial "09-02: 0/2 (pending)"
}

@test "handles empty phase" {
  run bash "$SUT" "99" --db "$TEST_DB"
  assert_success
  assert_output --partial "plans: 0/0 complete"
  assert_output --partial "tasks: 0/0 complete (0%)"
}

@test "exits 1 without phase argument" {
  run bash "$SUT" --db "$TEST_DB"
  assert_failure
  assert_output --partial "usage:"
}
