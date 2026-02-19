#!/usr/bin/env bats
# release-task.bats — Unit tests for scripts/db/release-task.sh

setup() {
  load '../../test_helper/common'
  load '../../test_helper/db_helper'
  SUT="$SCRIPTS_DIR/db/release-task.sh"
  mk_test_db

  db_insert_plan "09" "09-01" "Auth module"
  db_insert_task "09-01" "T1" "Create auth middleware" "in_progress" "[]" "dev-01"
  db_insert_task "09-01" "T2" "Add JWT validation" "pending"
  db_insert_task "09-01" "T3" "Write auth tests" "complete"
}

@test "releases in_progress task back to pending" {
  run bash "$SUT" --plan "09-01" --task "T1" --db "$TEST_DB"
  assert_success
  assert_output --partial "released T1 back to pending"
}

@test "sets status to pending after release" {
  bash "$SUT" --plan "09-01" --task "T1" --db "$TEST_DB"
  local status
  status=$(db_task_status "09-01" "T1")
  [ "$status" = "pending" ]
}

@test "clears assigned_to after release" {
  bash "$SUT" --plan "09-01" --task "T1" --db "$TEST_DB"
  local assigned
  assigned=$(db_task_assigned "09-01" "T1")
  [ -z "$assigned" ]
}

@test "rejects pending task (not in_progress)" {
  run bash "$SUT" --plan "09-01" --task "T2" --db "$TEST_DB"
  assert_failure
  assert_output --partial "not in_progress"
}

@test "rejects complete task" {
  run bash "$SUT" --plan "09-01" --task "T3" --db "$TEST_DB"
  assert_failure
  assert_output --partial "not in_progress"
}

@test "stores retry reason in gaps table" {
  run bash "$SUT" --plan "09-01" --task "T1" --reason "Agent crashed during execution" --db "$TEST_DB"
  assert_success
  local gap_count
  gap_count=$(sqlite3 "$TEST_DB" "SELECT count(*) FROM gaps WHERE res='Agent crashed during execution';")
  [ "$gap_count" -eq 1 ]
}

@test "retry reason includes correct severity" {
  bash "$SUT" --plan "09-01" --task "T1" --reason "Test failure" --db "$TEST_DB"
  local sev
  sev=$(sqlite3 "$TEST_DB" "SELECT sev FROM gaps ORDER BY rowid DESC LIMIT 1;")
  [ "$sev" = "info" ]
}

@test "exits 1 without required args" {
  run bash "$SUT" --db "$TEST_DB"
  assert_failure
  assert_output --partial "usage:"
}
