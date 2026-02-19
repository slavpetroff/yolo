#!/usr/bin/env bats
# get-task.bats — Unit tests for scripts/db/get-task.sh
# Single-task retrieval with field filtering and TOON output

setup() {
  load '../../test_helper/common'
  load '../../test_helper/fixtures'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/db/get-task.sh"
  DB="$TEST_WORKDIR/test.db"
  # Create tasks table matching 10-01 schema
  sqlite3 "$DB" <<'SQL'
CREATE TABLE tasks (
  plan_id TEXT NOT NULL,
  task_id TEXT NOT NULL,
  action TEXT,
  files TEXT,
  verify TEXT,
  done TEXT,
  spec TEXT,
  test_spec TEXT,
  task_depends TEXT,
  status TEXT DEFAULT 'pending',
  assigned_to TEXT,
  completed_at TEXT,
  files_written TEXT,
  summary TEXT,
  PRIMARY KEY (plan_id, task_id)
);
INSERT INTO tasks (plan_id, task_id, action, files, done, spec)
  VALUES ('09-02', 'T1', 'Create auth middleware', '["src/auth.ts"]', 'Tests pass', 'Express middleware for JWT auth');
INSERT INTO tasks (plan_id, task_id, action, files, done, spec)
  VALUES ('09-02', 'T2', 'Add route guards', '["src/routes.ts"]', 'Guards active', 'Protect API routes');
INSERT INTO tasks (plan_id, task_id, action, files, done, spec)
  VALUES ('09-03', 'T1', 'Setup DB', '["src/db.ts"]', 'DB connected', 'Initialize SQLite connection');
SQL
}

@test "exits 1 with usage when no args" {
  run bash "$SUT" --db "$DB"
  assert_failure
  assert_output --partial "Usage"
}

@test "returns correct task with default fields" {
  run bash "$SUT" 09-02 T1 --db "$DB"
  assert_success
  # Default fields: task_id,action,files,done,spec
  assert_output --partial "T1"
  assert_output --partial "Create auth middleware"
  assert_output --partial "Express middleware for JWT auth"
}

@test "field filtering returns only requested columns" {
  run bash "$SUT" 09-02 T1 --db "$DB" --fields "task_id,action"
  assert_success
  assert_output --partial "T1"
  assert_output --partial "Create auth middleware"
  # Should NOT contain spec text (not in selected fields)
  refute_output --partial "Express middleware for JWT auth"
}

@test "exit 1 on missing task" {
  run bash "$SUT" 09-02 T99 --db "$DB"
  assert_failure
  assert_output --partial "not found"
}

@test "exit 1 on missing plan" {
  run bash "$SUT" 99-99 T1 --db "$DB"
  assert_failure
  assert_output --partial "not found"
}

@test "comma-separated output for multiple fields" {
  run bash "$SUT" 09-02 T2 --db "$DB" --fields "task_id,action,done"
  assert_success
  # sqlite3 list mode uses | as default separator, but output should be single line
  local line_count
  line_count=$(echo "$output" | wc -l | tr -d ' ')
  [ "$line_count" -eq 1 ]
}

@test "returns task from correct plan when same task_id exists" {
  run bash "$SUT" 09-03 T1 --db "$DB" --fields "task_id,spec"
  assert_success
  assert_output --partial "Initialize SQLite connection"
  refute_output --partial "JWT auth"
}

@test "exit 1 when database missing" {
  run bash "$SUT" 09-02 T1 --db "$TEST_WORKDIR/nonexistent.db"
  assert_failure
  assert_output --partial "database not found"
}
