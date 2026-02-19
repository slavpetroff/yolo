#!/usr/bin/env bats
# schema-valid.bats — Validates SQLite schema loads and all tables exist

setup() {
  load '../../test_helper/common'
  load '../../test_helper/fixtures'
  mk_test_workdir
  SCHEMA="$SCRIPTS_DIR/db/schema.sql"
  DB="$TEST_WORKDIR/test.db"
}

# Helper: load schema into DB with pragmas
load_schema() {
  sqlite3 "$DB" "PRAGMA foreign_keys = ON;"
  sqlite3 "$DB" < "$SCHEMA"
}

# Helper: get table names as sorted list
get_tables() {
  sqlite3 "$DB" "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;"
}

# Helper: get virtual table names
get_virtual_tables() {
  sqlite3 "$DB" "SELECT name FROM sqlite_master WHERE type='table' AND sql LIKE '%fts5%' ORDER BY name;"
}

# Helper: count columns in a table
count_columns() {
  sqlite3 "$DB" "PRAGMA table_info($1);" | wc -l | tr -d ' '
}

# Helper: check index exists
index_exists() {
  sqlite3 "$DB" "SELECT name FROM sqlite_master WHERE type='index' AND name='$1';" | grep -q "$1"
}

# ============================================================
# T1: Core artifact tables
# ============================================================

@test "schema.sql loads without errors" {
  run load_schema
  assert_success
}

@test "plans table exists with expected columns" {
  load_schema
  local cols
  cols=$(count_columns plans)
  # phase, plan_num, title, wave, depends_on, xd, must_haves, objective,
  # effort, skills, fm, autonomous, created_at, updated_at = 14
  [ "$cols" -ge 14 ]
}

@test "tasks table exists with expected columns" {
  load_schema
  local cols
  cols=$(count_columns tasks)
  # plan_id, task_id, type, action, files, verify, done, spec, test_spec,
  # task_depends, status, assigned_to, completed_at, files_written, summary,
  # created_at, updated_at = 17
  [ "$cols" -ge 17 ]
}

@test "summaries table exists with expected columns" {
  load_schema
  local cols
  cols=$(count_columns summaries)
  # plan_id, status, date_completed, tasks_completed, tasks_total,
  # commit_hashes, fm, deviations, built, test_status, suggestions,
  # created_at, updated_at = 13
  [ "$cols" -ge 13 ]
}

@test "plans has unique constraint on phase+plan_num" {
  load_schema
  sqlite3 "$DB" "INSERT INTO plans (phase, plan_num, title) VALUES ('01', '01', 'First');"
  run sqlite3 "$DB" "INSERT INTO plans (phase, plan_num, title) VALUES ('01', '01', 'Duplicate');"
  assert_failure
}

@test "tasks foreign key references plans" {
  load_schema
  run sqlite3 "$DB" "PRAGMA foreign_keys = ON; INSERT INTO tasks (plan_id, task_id, action) VALUES (9999, 'T1', 'test');"
  assert_failure
}

# ============================================================
# T2: Workflow artifact tables
# ============================================================

@test "critique table exists" {
  load_schema
  local cols
  cols=$(count_columns critique)
  [ "$cols" -ge 10 ]
}

@test "research table exists" {
  load_schema
  local cols
  cols=$(count_columns research)
  [ "$cols" -ge 12 ]
}

@test "research_archive table exists" {
  load_schema
  local cols
  cols=$(count_columns research_archive)
  [ "$cols" -ge 6 ]
}

@test "decisions table exists" {
  load_schema
  local cols
  cols=$(count_columns decisions)
  [ "$cols" -ge 7 ]
}

@test "escalation table exists" {
  load_schema
  local cols
  cols=$(count_columns escalation)
  [ "$cols" -ge 11 ]
}

@test "gaps table exists" {
  load_schema
  local cols
  cols=$(count_columns gaps)
  [ "$cols" -ge 8 ]
}

@test "verification table exists" {
  load_schema
  local cols
  cols=$(count_columns verification)
  [ "$cols" -ge 7 ]
}

@test "verification_checks table exists" {
  load_schema
  local cols
  cols=$(count_columns verification_checks)
  [ "$cols" -ge 5 ]
}

@test "code_review table exists" {
  load_schema
  local cols
  cols=$(count_columns code_review)
  [ "$cols" -ge 8 ]
}

@test "security_audit table exists" {
  load_schema
  local cols
  cols=$(count_columns security_audit)
  [ "$cols" -ge 5 ]
}

@test "test_plan table exists" {
  load_schema
  local cols
  cols=$(count_columns test_plan)
  [ "$cols" -ge 6 ]
}

@test "test_results table exists" {
  load_schema
  local cols
  cols=$(count_columns test_results)
  [ "$cols" -ge 9 ]
}

@test "qa_gate_results table exists" {
  load_schema
  local cols
  cols=$(count_columns qa_gate_results)
  [ "$cols" -ge 9 ]
}

# ============================================================
# T3: Cross-department and state tables
# ============================================================

@test "design_tokens table exists" {
  load_schema
  local cols
  cols=$(count_columns design_tokens)
  [ "$cols" -ge 6 ]
}

@test "component_specs table exists" {
  load_schema
  local cols
  cols=$(count_columns component_specs)
  [ "$cols" -ge 8 ]
}

@test "user_flows table exists" {
  load_schema
  local cols
  cols=$(count_columns user_flows)
  [ "$cols" -ge 7 ]
}

@test "design_handoff table exists" {
  load_schema
  local cols
  cols=$(count_columns design_handoff)
  [ "$cols" -ge 4 ]
}

@test "api_contracts table exists" {
  load_schema
  local cols
  cols=$(count_columns api_contracts)
  [ "$cols" -ge 5 ]
}

@test "po_qa_verdict table exists" {
  load_schema
  local cols
  cols=$(count_columns po_qa_verdict)
  [ "$cols" -ge 6 ]
}

@test "manual_qa table exists" {
  load_schema
  local cols
  cols=$(count_columns manual_qa)
  [ "$cols" -ge 4 ]
}

@test "state table exists" {
  load_schema
  local cols
  cols=$(count_columns state)
  [ "$cols" -ge 7 ]
}

@test "execution_state table exists" {
  load_schema
  local cols
  cols=$(count_columns execution_state)
  [ "$cols" -ge 5 ]
}

@test "phase index exists on critique table" {
  load_schema
  run index_exists idx_critique_phase
  assert_success
}

@test "phase+plan index exists on tasks" {
  load_schema
  run index_exists idx_tasks_phase_plan
  assert_success
}

@test "all 20+ tables exist" {
  load_schema
  local count
  count=$(sqlite3 "$DB" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';" | tr -d ' ')
  [ "$count" -ge 20 ]
}
