#!/usr/bin/env bats
# next-review.bats — Unit tests for scripts/db/next-review.sh

setup() {
  load '../../test_helper/common'
  load '../../test_helper/db_helper'
  SUT="$SCRIPTS_DIR/db/next-review.sh"
  mk_test_db

  # Seed: phase 09, plan 09-01 with completed tasks
  db_insert_plan "09" "09-01" "Auth module"
  db_insert_task "09-01" "T1" "Create auth middleware" "complete"
  db_insert_task "09-01" "T2" "Add JWT validation" "complete"
  db_insert_task "09-01" "T3" "Write auth tests" "pending"
}

@test "returns completed unreviewed tasks" {
  run bash "$SUT" --db "$TEST_DB"
  assert_success
  assert_output --partial "T1,09-01,Create auth middleware,complete"
  assert_output --partial "T2,09-01,Add JWT validation,complete"
  # T3 is pending, should not appear
  refute_output --partial "T3"
}

@test "excludes tasks from reviewed plans" {
  db_insert_review "09-01" "09"
  run bash "$SUT" --db "$TEST_DB"
  assert_success
  assert_output ""
}

@test "filters by plan" {
  db_insert_plan "09" "09-02" "Logging module"
  db_insert_task "09-02" "T1" "Create logger" "complete"
  run bash "$SUT" --plan "09-02" --db "$TEST_DB"
  assert_success
  assert_output --partial "T1,09-02,Create logger"
  refute_output --partial "09-01"
}

@test "filters by phase" {
  db_insert_plan "10" "10-01" "DB module"
  db_insert_task "10-01" "T1" "Create schema" "complete"
  run bash "$SUT" --phase "10" --db "$TEST_DB"
  assert_success
  assert_output --partial "T1,10-01,Create schema"
  refute_output --partial "09-01"
}

@test "empty when all tasks are pending" {
  sqlite3 "$TEST_DB" "UPDATE tasks SET status='pending';"
  run bash "$SUT" --db "$TEST_DB"
  assert_success
  assert_output ""
}

@test "empty when no tasks exist" {
  sqlite3 "$TEST_DB" "DELETE FROM tasks;"
  run bash "$SUT" --db "$TEST_DB"
  assert_success
  assert_output ""
}
