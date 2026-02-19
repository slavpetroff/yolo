#!/usr/bin/env bats
# token-audit-report.bats — Unit tests for scripts/db/token-audit-report.sh

setup() {
  load '../../test_helper/common'
  load '../../test_helper/fixtures'
  load '../../test_helper/db_helper'
  mk_test_workdir

  SUT="$SCRIPTS_DIR/db/token-audit-report.sh"
  DB="$TEST_WORKDIR/test.db"
  sqlite3 "$DB" < "$SCRIPTS_DIR/db/schema.sql"
  sqlite3 "$DB" "PRAGMA journal_mode=WAL;" >/dev/null

  # Create planning structure for token-measure.sh fallback
  PLANNING_DIR="$TEST_WORKDIR/.yolo-planning"
  PHASES_DIR="$PLANNING_DIR/phases"
  PHASE_DIR="$PHASES_DIR/09-test-phase"
  mkdir -p "$PHASE_DIR"

  cat > "$PLANNING_DIR/ROADMAP.md" <<'ROADMAP'
# Test Roadmap

## Phase 9: Test Phase
**Goal:** Test phase
ROADMAP

  cat > "$PHASE_DIR/09-01.plan.jsonl" <<'PLAN'
{"p":"09","n":"09-01","g":"Test plan","fm":["src/a.ts"],"tc":1}
{"id":"T1","a":"dev","f":["src/a.ts"],"spec":"Create module","done":""}
PLAN

  ln -sf "$DB" "$PLANNING_DIR/yolo.db"

  # Insert plan data for compile-context.sh
  sqlite3 "$DB" "INSERT INTO plans (phase, plan_num, title, objective, must_haves)
    VALUES ('09', '01', 'Test plan', 'Test phase', '{\"tr\":[]}');"
  sqlite3 "$DB" "INSERT INTO tasks (plan_id, task_id, action, status, task_depends)
    VALUES (1, 'T1', 'Create module', 'pending', '[]');"

  # Pre-populate token_measurements for predictable testing
  sqlite3 "$DB" "CREATE TABLE IF NOT EXISTS token_measurements (
    phase TEXT NOT NULL,
    role TEXT NOT NULL,
    file_tokens INTEGER NOT NULL DEFAULT 0,
    sql_tokens INTEGER NOT NULL DEFAULT 0,
    measured_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    UNIQUE(phase, role)
  );"
}

# Helper: seed measurements with known values
seed_measurements() {
  local phase="$1" file_total="$2" sql_total="$3" role_count="$4"
  local per_file=$(( file_total / role_count ))
  local per_sql=$(( sql_total / role_count ))
  local roles=("dev" "architect" "lead" "senior" "qa")
  for i in $(seq 0 $((role_count - 1))); do
    local role="${roles[$i]}"
    sqlite3 "$DB" "INSERT OR REPLACE INTO token_measurements (phase, role, file_tokens, sql_tokens)
      VALUES ('$phase', '$role', $per_file, $per_sql);"
  done
}

@test "requires --phase flag" {
  run bash "$SUT" --db "$DB"
  assert_failure
  assert_output --partial "error: --phase required"
}

@test "creates token_audit_reports table" {
  seed_measurements "09" 10000 3000 5

  run bash "$SUT" --phase 09 --db "$DB"
  assert_success

  local count
  count=$(sqlite3 "$DB" "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='token_audit_reports';")
  assert_equal "$count" "1"
}

@test "generates report with totals" {
  seed_measurements "09" 10000 3000 5

  run bash "$SUT" --phase 09 --db "$DB"
  assert_success
  assert_output --partial "Token Audit Report: Phase 09"
  assert_output --partial "Total file-based tokens:"
  assert_output --partial "Total SQL-based tokens:"
  assert_output --partial "Total savings:"
}

@test "PASS verdict when savings > 50%" {
  seed_measurements "09" 10000 3000 5  # 70% savings

  run bash "$SUT" --phase 09 --db "$DB"
  assert_success
  assert_output --partial "Verdict:                  PASS"
}

@test "WARN verdict when savings 30-50%" {
  seed_measurements "09" 10000 6000 5  # 40% savings

  run bash "$SUT" --phase 09 --db "$DB"
  assert_success
  assert_output --partial "Verdict:                  WARN"
}

@test "FAIL verdict when savings < 30%" {
  seed_measurements "09" 10000 8000 5  # 20% savings

  run bash "$SUT" --phase 09 --db "$DB"
  assert_success
  assert_output --partial "Verdict:                  FAIL"
}

@test "stores report in DB" {
  seed_measurements "09" 10000 3000 5

  run bash "$SUT" --phase 09 --db "$DB"
  assert_success

  local verdict
  verdict=$(sqlite3 "$DB" "SELECT verdict FROM token_audit_reports WHERE phase='09';")
  assert_equal "$verdict" "PASS"

  local total_file
  total_file=$(sqlite3 "$DB" "SELECT total_file_tokens FROM token_audit_reports WHERE phase='09';")
  assert_equal "$total_file" "10000"
}

@test "per-role breakdown is shown" {
  seed_measurements "09" 10000 3000 3

  run bash "$SUT" --phase 09 --db "$DB"
  assert_success
  assert_output --partial "Per-Role Breakdown"
  assert_output --partial "file="
  assert_output --partial "sql="
  assert_output --partial "savings="
}

@test "baseline comparison when --baseline provided" {
  seed_measurements "08" 15000 10000 5  # baseline phase
  seed_measurements "09" 10000 3000 5   # current phase

  run bash "$SUT" --phase 09 --baseline 08 --db "$DB"
  assert_success
  assert_output --partial "Baseline Comparison (Phase 08)"
  assert_output --partial "Baseline file tokens:"
  assert_output --partial "Improvement over baseline:"
}

@test "upserts on repeat report generation" {
  seed_measurements "09" 10000 3000 5

  bash "$SUT" --phase 09 --db "$DB" >/dev/null 2>&1
  bash "$SUT" --phase 09 --db "$DB" >/dev/null 2>&1

  local count
  count=$(sqlite3 "$DB" "SELECT count(*) FROM token_audit_reports WHERE phase='09';")
  assert_equal "$count" "1"
}

@test "fails when no measurements exist" {
  run bash "$SUT" --phase 99 --db "$DB"
  assert_failure
  assert_output --partial "no measurements found"
}
