#!/usr/bin/env bats
# token-measure.bats — Unit tests for scripts/db/token-measure.sh

setup() {
  load '../../test_helper/common'
  load '../../test_helper/fixtures'
  load '../../test_helper/db_helper'
  mk_test_workdir

  SUT="$SCRIPTS_DIR/db/token-measure.sh"
  DB="$TEST_WORKDIR/test.db"
  sqlite3 "$DB" < "$SCRIPTS_DIR/db/schema.sql"
  sqlite3 "$DB" "PRAGMA journal_mode=WAL;" >/dev/null

  # Create planning directory structure
  PLANNING_DIR="$TEST_WORKDIR/.yolo-planning"
  PHASES_DIR="$PLANNING_DIR/phases"
  PHASE_DIR="$PHASES_DIR/09-test-phase"
  mkdir -p "$PHASE_DIR"
  mkdir -p "$PLANNING_DIR"

  # Create ROADMAP.md (compile-context.sh needs it)
  cat > "$PLANNING_DIR/ROADMAP.md" <<'ROADMAP'
# Test Roadmap

## Progress
| Phase | Status |
|-------|--------|
| 9 | Active |

---

## Phase List
- [ ] Phase 9: Test Phase

---

## Phase 9: Test Phase

**Goal:** Test phase for token measurement
**Reqs:** Unit tests
**Success Criteria:** All tests pass

---
ROADMAP

  # Create a valid plan file
  cat > "$PHASE_DIR/09-01.plan.jsonl" <<'PLAN'
{"p":"09","n":"09-01","g":"Test plan","fm":["src/a.ts"],"tc":2}
{"id":"T1","a":"dev","f":["src/a.ts"],"spec":"Create module A","done":""}
{"id":"T2","a":"dev","f":["src/b.ts"],"spec":"Create module B","done":""}
PLAN

  # Create a summary
  cat > "$PHASE_DIR/09-01.summary.jsonl" <<'SUMMARY'
{"p":"09-01","s":"complete","fm":"Added module A and B"}
SUMMARY

  # Symlink the DB into .yolo-planning/ where compile-context.sh expects it
  # (compile-context.sh uses .yolo-planning/yolo.db hardcoded path)
  ln -sf "$DB" "$PLANNING_DIR/yolo.db"

  # Insert phase data in DB for SQL path
  sqlite3 "$DB" "INSERT INTO plans (phase, plan_num, title, objective, must_haves) VALUES ('09', '01', 'Test plan', 'Test phase for token measurement', '{\"tr\":[]}');"
  sqlite3 "$DB" "INSERT INTO tasks (plan_id, task_id, action, status, task_depends) VALUES (1, 'T1', 'Create module A', 'pending', '[]');"
  sqlite3 "$DB" "INSERT INTO tasks (plan_id, task_id, action, status, task_depends) VALUES (1, 'T2', 'Create module B', 'pending', '[]');"
}

@test "requires --phase flag" {
  run bash "$SUT" --db "$DB"
  assert_failure
  assert_output --partial "error: --phase required"
}

@test "creates token_measurements table if not exists" {
  # Verify table doesn't exist yet
  local count
  count=$(sqlite3 "$DB" "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='token_measurements';")
  assert_equal "$count" "0"

  # Run for single role (fast)
  run bash "$SUT" --phase 09 --role dev --db "$DB"
  assert_success

  # Table should exist now
  count=$(sqlite3 "$DB" "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='token_measurements';")
  assert_equal "$count" "1"
}

@test "measures single role and stores in DB" {
  run bash "$SUT" --phase 09 --role dev --db "$DB"
  assert_success

  # Check DB has measurement
  local row
  row=$(sqlite3 "$DB" "SELECT role, file_tokens, sql_tokens FROM token_measurements WHERE phase='09' AND role='dev';")
  assert [ -n "$row" ]
  # Role should be 'dev'
  assert_output --partial "dev:"
}

@test "JSON output format is valid" {
  run bash "$SUT" --phase 09 --role dev --db "$DB" --output json
  assert_success

  # Validate JSON structure
  echo "$output" | jq . >/dev/null 2>&1
  assert_equal "$?" "0"

  # Check required fields
  local phase
  phase=$(echo "$output" | jq -r '.phase')
  assert_equal "$phase" "09"

  local role_count
  role_count=$(echo "$output" | jq '.roles | length')
  assert_equal "$role_count" "1"

  local role_name
  role_name=$(echo "$output" | jq -r '.roles[0].role')
  assert_equal "$role_name" "dev"
}

@test "TOON output format has expected fields" {
  run bash "$SUT" --phase 09 --role dev --db "$DB" --output toon
  assert_success
  assert_output --partial "token_measurement:"
  assert_output --partial "phase: 09"
  assert_output --partial "total_file:"
  assert_output --partial "total_sql:"
  assert_output --partial "savings:"
  assert_output --partial "roles:"
}

@test "calculates savings percentage correctly" {
  run bash "$SUT" --phase 09 --role dev --db "$DB" --output json
  assert_success

  # file_tokens and sql_tokens should be >= 0
  local ft st
  ft=$(echo "$output" | jq '.roles[0].file_tokens')
  st=$(echo "$output" | jq '.roles[0].sql_tokens')
  assert [ "$ft" -ge 0 ]
  assert [ "$st" -ge 0 ]

  # savings_pct should be integer
  local sp
  sp=$(echo "$output" | jq '.roles[0].savings_pct')
  assert [ "$sp" -ge -100 ]
  assert [ "$sp" -le 100 ]
}

@test "measures multiple roles when no --role specified" {
  run bash "$SUT" --phase 09 --db "$DB" --output json
  assert_success

  # Should have multiple roles
  local role_count
  role_count=$(echo "$output" | jq '.roles | length')
  assert [ "$role_count" -gt 1 ]

  # DB should have multiple rows
  local db_count
  db_count=$(sqlite3 "$DB" "SELECT count(*) FROM token_measurements WHERE phase='09';")
  assert [ "$db_count" -gt 1 ]
}

@test "upserts on repeat measurement" {
  # Run twice
  bash "$SUT" --phase 09 --role dev --db "$DB" --output json >/dev/null 2>&1
  bash "$SUT" --phase 09 --role dev --db "$DB" --output json >/dev/null 2>&1

  # Should still have 1 row (upsert, not insert)
  local count
  count=$(sqlite3 "$DB" "SELECT count(*) FROM token_measurements WHERE phase='09' AND role='dev';")
  assert_equal "$count" "1"
}

@test "fails on missing phase directory" {
  run bash "$SUT" --phase 99 --role dev --db "$DB"
  assert_failure
  assert_output --partial "error: phase directory not found"
}
