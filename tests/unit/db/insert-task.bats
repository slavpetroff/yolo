#!/usr/bin/env bats
# insert-task.bats — Unit tests for scripts/db/insert-task.sh

setup() {
  load '../../test_helper/common'
  load '../../test_helper/fixtures'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/db/insert-task.sh"
  DB="$TEST_WORKDIR/test.db"
  # Create DB with schema
  sqlite3 "$DB" < "$SCRIPTS_DIR/db/schema.sql"
  sqlite3 "$DB" "PRAGMA journal_mode=WAL;"
}

@test "inserts task with required fields" {
  run bash "$SUT" --plan 10-03 --id T1 --action "Create auth module" --db "$DB"
  assert_success
  assert_output --partial "ok: T1 inserted into plan 10-03"
  # Verify in DB
  local action
  action=$(sqlite3 "$DB" "SELECT action FROM tasks WHERE task_id='T1';")
  [ "$action" = "Create auth module" ]
}

@test "inserts task with all optional fields" {
  run bash "$SUT" --plan 10-03 --id T2 \
    --action "Build middleware" \
    --spec "Express middleware for JWT auth" \
    --files "src/auth.ts,src/middleware.ts" \
    --verify "Tests pass" \
    --done "Middleware created" \
    --test-spec "Unit tests for auth flow" \
    --deps "T1" \
    --db "$DB"
  assert_success
  # Verify spec stored
  local spec
  spec=$(sqlite3 "$DB" "SELECT spec FROM tasks WHERE task_id='T2';")
  [ "$spec" = "Express middleware for JWT auth" ]
  # Verify verify stored
  local verify
  verify=$(sqlite3 "$DB" "SELECT verify FROM tasks WHERE task_id='T2';")
  [ "$verify" = "Tests pass" ]
}

@test "files stored as JSON array" {
  run bash "$SUT" --plan 10-03 --id T3 \
    --action "Create files" \
    --files "src/a.ts,src/b.ts,src/c.ts" \
    --db "$DB"
  assert_success
  local files
  files=$(sqlite3 "$DB" "SELECT files FROM tasks WHERE task_id='T3';")
  # Should be a JSON array
  local count
  count=$(echo "$files" | jq 'length')
  [ "$count" -eq 3 ]
  local first
  first=$(echo "$files" | jq -r '.[0]')
  [ "$first" = "src/a.ts" ]
}

@test "deps stored as JSON array" {
  run bash "$SUT" --plan 10-03 --id T4 \
    --action "Depends on others" \
    --deps "T1,T2,T3" \
    --db "$DB"
  assert_success
  local deps
  deps=$(sqlite3 "$DB" "SELECT task_depends FROM tasks WHERE task_id='T4';")
  local count
  count=$(echo "$deps" | jq 'length')
  [ "$count" -eq 3 ]
}

@test "upsert updates existing task" {
  # Insert first
  run bash "$SUT" --plan 10-03 --id T1 --action "Original action" --db "$DB"
  assert_success
  # Upsert with new action
  run bash "$SUT" --plan 10-03 --id T1 --action "Updated action" --spec "New spec" --db "$DB"
  assert_success
  # Verify updated
  local action
  action=$(sqlite3 "$DB" "SELECT action FROM tasks WHERE task_id='T1';")
  [ "$action" = "Updated action" ]
  local spec
  spec=$(sqlite3 "$DB" "SELECT spec FROM tasks WHERE task_id='T1';")
  [ "$spec" = "New spec" ]
  # Only one row
  local count
  count=$(sqlite3 "$DB" "SELECT count(*) FROM tasks WHERE task_id='T1';")
  [ "$count" -eq 1 ]
}

@test "missing --plan exits 1" {
  run bash "$SUT" --id T1 --action "test" --db "$DB"
  assert_failure
  assert_output --partial "--plan is required"
}

@test "missing --id exits 1" {
  run bash "$SUT" --plan 10-03 --action "test" --db "$DB"
  assert_failure
  assert_output --partial "--id is required"
}

@test "missing --action exits 1" {
  run bash "$SUT" --plan 10-03 --id T1 --db "$DB"
  assert_failure
  assert_output --partial "--action is required"
}

@test "status defaults to pending" {
  run bash "$SUT" --plan 10-03 --id T1 --action "test" --db "$DB"
  assert_success
  local status
  status=$(sqlite3 "$DB" "SELECT status FROM tasks WHERE task_id='T1';")
  [ "$status" = "pending" ]
}

@test "auto-creates plan record if missing" {
  run bash "$SUT" --plan 10-05 --id T1 --action "test" --db "$DB"
  assert_success
  local plan_count
  plan_count=$(sqlite3 "$DB" "SELECT count(*) FROM plans WHERE phase='10' AND plan_num='05';")
  [ "$plan_count" -eq 1 ]
}
