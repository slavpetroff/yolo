#!/usr/bin/env bats
# claim-task.bats — Unit tests for scripts/db/claim-task.sh

setup() {
  load '../../test_helper/common'
  load '../../test_helper/db_helper'
  SUT="$SCRIPTS_DIR/db/claim-task.sh"
  mk_test_db

  db_insert_plan "09" "09-01" "Auth module"
  db_insert_task "09-01" "T1" "Create auth middleware" "pending"
  db_insert_task "09-01" "T2" "Add JWT validation" "in_progress" "[]" "other-agent"
  db_insert_task "09-01" "T3" "Write auth tests" "complete"
}

@test "claims pending task successfully" {
  run bash "$SUT" --plan "09-01" --task "T1" --agent "dev-01" --db "$TEST_DB"
  assert_success
  assert_output --partial "claimed T1 for agent dev-01"
}

@test "sets status to in_progress after claim" {
  bash "$SUT" --plan "09-01" --task "T1" --agent "dev-01" --db "$TEST_DB"
  local status
  status=$(db_task_status "09-01" "T1")
  [ "$status" = "in_progress" ]
}

@test "sets assigned_to after claim" {
  bash "$SUT" --plan "09-01" --task "T1" --agent "dev-01" --db "$TEST_DB"
  local assigned
  assigned=$(db_task_assigned "09-01" "T1")
  [ "$assigned" = "dev-01" ]
}

@test "rejects already-claimed task (in_progress)" {
  run bash "$SUT" --plan "09-01" --task "T2" --agent "dev-01" --db "$TEST_DB"
  assert_failure
  assert_output --partial "not pending"
}

@test "rejects already-complete task" {
  run bash "$SUT" --plan "09-01" --task "T3" --agent "dev-01" --db "$TEST_DB"
  assert_failure
  assert_output --partial "not pending"
}

@test "rejects non-existent task" {
  run bash "$SUT" --plan "09-01" --task "T99" --agent "dev-01" --db "$TEST_DB"
  assert_failure
  assert_output --partial "not pending or does not exist"
}

@test "rejects non-existent plan" {
  run bash "$SUT" --plan "99-99" --task "T1" --agent "dev-01" --db "$TEST_DB"
  assert_failure
  assert_output --partial "not pending or does not exist"
}

@test "exits 1 without required args" {
  run bash "$SUT" --db "$TEST_DB"
  assert_failure
  assert_output --partial "usage:"
}
