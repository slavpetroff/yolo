#!/usr/bin/env bats
# complete-task.bats — Unit tests for scripts/db/complete-task.sh

setup() {
  load '../../test_helper/common'
  load '../../test_helper/fixtures'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/db/complete-task.sh"
  INSERT="$SCRIPTS_DIR/db/insert-task.sh"
  DB="$TEST_WORKDIR/test.db"
  # Create DB with schema
  sqlite3 "$DB" < "$SCRIPTS_DIR/db/schema.sql"
  sqlite3 "$DB" "PRAGMA journal_mode=WAL;"
  # Seed a pending task
  bash "$INSERT" --plan 10-03 --id T1 --action "Create auth module" --db "$DB"
}

@test "completes pending task" {
  run bash "$SUT" T1 --plan 10-03 --db "$DB"
  assert_success
  assert_output --partial "ok: T1 complete"
  local status
  status=$(sqlite3 "$DB" "SELECT status FROM tasks WHERE task_id='T1';")
  [ "$status" = "complete" ]
}

@test "sets completed_at timestamp" {
  run bash "$SUT" T1 --plan 10-03 --db "$DB"
  assert_success
  local ts
  ts=$(sqlite3 "$DB" "SELECT completed_at FROM tasks WHERE task_id='T1';")
  [ -n "$ts" ]
}

@test "rejects already-complete task" {
  bash "$SUT" T1 --plan 10-03 --db "$DB"
  run bash "$SUT" T1 --plan 10-03 --db "$DB"
  assert_failure
  assert_output --partial "already complete"
}

@test "stores files_written" {
  run bash "$SUT" T1 --plan 10-03 --files "src/auth.ts,src/middleware.ts" --db "$DB"
  assert_success
  local files
  files=$(sqlite3 "$DB" "SELECT files_written FROM tasks WHERE task_id='T1';")
  local count
  count=$(echo "$files" | jq 'length')
  [ "$count" -eq 2 ]
}

@test "stores summary text" {
  run bash "$SUT" T1 --plan 10-03 --summary "Auth module created with JWT support" --db "$DB"
  assert_success
  local summary
  summary=$(sqlite3 "$DB" "SELECT summary FROM tasks WHERE task_id='T1';")
  [ "$summary" = "Auth module created with JWT support" ]
}

@test "exit 1 on missing task" {
  run bash "$SUT" T99 --plan 10-03 --db "$DB"
  assert_failure
  assert_output --partial "not found"
}

@test "exit 1 on missing plan" {
  run bash "$SUT" T1 --plan 99-99 --db "$DB"
  assert_failure
  assert_output --partial "not found"
}

@test "exit 1 without TASK_ID" {
  run bash "$SUT" --plan 10-03 --db "$DB"
  assert_failure
  assert_output --partial "TASK_ID is required"
}

@test "exit 1 without --plan" {
  run bash "$SUT" T1 --db "$DB"
  assert_failure
  assert_output --partial "--plan is required"
}
