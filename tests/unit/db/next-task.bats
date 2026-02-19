#!/usr/bin/env bats
# next-task.bats — Unit tests for scripts/db/next-task.sh

setup() {
  load '../../test_helper/common'
  load '../../test_helper/db_helper'
  SUT="$SCRIPTS_DIR/db/next-task.sh"
  mk_test_db

  # Seed: phase 09, plan 09-01 with 3 tasks: T1 (no deps), T2 (depends T1), T3 (depends T2)
  db_insert_plan "09" "09-01" "Auth module"
  db_insert_task "09-01" "T1" "Create auth middleware" "pending" "[]"
  db_insert_task "09-01" "T2" "Add JWT validation" "pending" '["T1"]'
  db_insert_task "09-01" "T3" "Write auth tests" "pending" '["T2"]'
}

@test "returns first unblocked pending task" {
  run bash "$SUT" --db "$TEST_DB"
  assert_success
  assert_output --partial "id: T1"
  assert_output --partial "plan: 09-01"
  assert_output --partial "action: Create auth middleware"
}

@test "skips blocked tasks (T2 depends on incomplete T1)" {
  run bash "$SUT" --db "$TEST_DB"
  assert_success
  # Should return T1, not T2 or T3
  assert_output --partial "id: T1"
  refute_output --partial "id: T2"
  refute_output --partial "id: T3"
}

@test "returns T2 after T1 is complete" {
  # Complete T1
  sqlite3 "$TEST_DB" "UPDATE tasks SET status='complete' WHERE task_id='T1';"
  run bash "$SUT" --db "$TEST_DB"
  assert_success
  assert_output --partial "id: T2"
}

@test "atomic claim sets status to in_progress" {
  run bash "$SUT" --db "$TEST_DB"
  assert_success
  # Verify T1 is now in_progress
  local status
  status=$(db_task_status "09-01" "T1")
  [ "$status" = "in_progress" ]
}

@test "atomic claim sets assigned_to" {
  run bash "$SUT" --db "$TEST_DB"
  assert_success
  local assigned
  assigned=$(db_task_assigned "09-01" "T1")
  [ -n "$assigned" ]
}

@test "empty output when all tasks complete" {
  sqlite3 "$TEST_DB" "UPDATE tasks SET status='complete';"
  run bash "$SUT" --db "$TEST_DB"
  assert_success
  assert_output ""
}

@test "empty output when all pending tasks are blocked" {
  # Claim T1 (in_progress, not complete) — T2 and T3 remain blocked
  sqlite3 "$TEST_DB" "UPDATE tasks SET status='in_progress' WHERE task_id='T1';"
  run bash "$SUT" --db "$TEST_DB"
  assert_success
  assert_output ""
}

@test "plan filter returns only tasks from specified plan" {
  db_insert_plan "09" "09-02" "Logging module"
  db_insert_task "09-02" "T1" "Create logger" "pending" "[]"
  # Claim 09-01 T1 first so it's not available
  sqlite3 "$TEST_DB" "UPDATE tasks SET status='in_progress' WHERE task_id='T1' AND plan_id=(SELECT rowid FROM plans WHERE plan_num='09-01');"
  run bash "$SUT" --plan "09-02" --db "$TEST_DB"
  assert_success
  assert_output --partial "plan: 09-02"
  assert_output --partial "action: Create logger"
}

@test "natural ordering: earlier phase/plan first" {
  db_insert_plan "08" "08-01" "Early phase plan"
  db_insert_task "08-01" "T1" "Early task" "pending" "[]"
  run bash "$SUT" --db "$TEST_DB"
  assert_success
  # Should pick 08-01 T1 before 09-01 T1
  assert_output --partial "plan: 08-01"
  assert_output --partial "action: Early task"
}
