#!/usr/bin/env bash
# db_helper.bash — Shared helpers for DB script tests

# Create a temporary test database with schema loaded
# Sets TEST_DB to the path
mk_test_db() {
  export TEST_DB="$BATS_TEST_TMPDIR/test-$BATS_TEST_NUMBER.db"
  sqlite3 "$TEST_DB" < "$PROJECT_ROOT/scripts/db/schema.sql"
  sqlite3 "$TEST_DB" "PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000;" >/dev/null
}

# Insert a plan into the test DB
# Usage: db_insert_plan <phase> <plan_num> [title]
db_insert_plan() {
  local phase="$1" plan_num="$2" title="${3:-Test plan $2}"
  sqlite3 "$TEST_DB" \
    "INSERT INTO plans (phase, plan_num, title) VALUES ('$phase', '$plan_num', '$title');"
}

# Insert a task into the test DB
# Usage: db_insert_task <plan_num> <task_id> <action> [status] [task_depends] [assigned_to]
db_insert_task() {
  local plan_num="$1" task_id="$2" action="$3"
  local status="${4:-pending}" deps="${5:-[]}" assigned="${6:-}"
  local plan_rowid
  plan_rowid=$(sqlite3 "$TEST_DB" \
    "SELECT rowid FROM plans WHERE plan_num='$plan_num' LIMIT 1;")
  local assigned_val="NULL"
  if [[ -n "$assigned" ]]; then
    assigned_val="'$assigned'"
  fi
  local completed_val="NULL"
  if [[ "$status" == "complete" ]]; then
    completed_val="strftime('%Y-%m-%dT%H:%M:%SZ', 'now')"
  fi
  sqlite3 "$TEST_DB" \
    "INSERT INTO tasks (plan_id, task_id, action, status, task_depends, assigned_to, completed_at)
     VALUES ($plan_rowid, '$task_id', '$action', '$status', '$deps', $assigned_val, $completed_val);"
}

# Insert a code_review entry
# Usage: db_insert_review <plan_num> <phase>
db_insert_review() {
  local plan="$1" phase="$2"
  sqlite3 "$TEST_DB" \
    "INSERT INTO code_review (plan, r, phase) VALUES ('$plan', 'approve', '$phase');"
}

# Insert a summary entry
# Usage: db_insert_summary <plan_num> <status>
db_insert_summary() {
  local plan_num="$1" status="$2"
  local plan_rowid
  plan_rowid=$(sqlite3 "$TEST_DB" \
    "SELECT rowid FROM plans WHERE plan_num='$plan_num' LIMIT 1;")
  sqlite3 "$TEST_DB" \
    "INSERT INTO summaries (plan_id, status) VALUES ($plan_rowid, '$status');"
}

# Query a task's status
# Usage: db_task_status <plan_num> <task_id>
db_task_status() {
  local plan_num="$1" task_id="$2"
  sqlite3 "$TEST_DB" \
    "SELECT t.status FROM tasks t JOIN plans p ON t.plan_id=p.rowid
     WHERE p.plan_num='$plan_num' AND t.task_id='$task_id';"
}

# Query a task's assigned_to
# Usage: db_task_assigned <plan_num> <task_id>
db_task_assigned() {
  local plan_num="$1" task_id="$2"
  sqlite3 "$TEST_DB" \
    "SELECT COALESCE(t.assigned_to,'') FROM tasks t JOIN plans p ON t.plan_id=p.rowid
     WHERE p.plan_num='$plan_num' AND t.task_id='$task_id';"
}
