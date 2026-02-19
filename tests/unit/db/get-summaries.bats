#!/usr/bin/env bats
# get-summaries.bats — Unit tests for scripts/db/get-summaries.sh
# Plan summary retrieval with status/plan/field filtering

setup() {
  load '../../test_helper/common'
  load '../../test_helper/fixtures'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/db/get-summaries.sh"
  DB="$TEST_WORKDIR/test.db"
  # Create summaries table matching 10-01 schema
  sqlite3 "$DB" <<'SQL'
CREATE TABLE summaries (
  plan_id TEXT PRIMARY KEY,
  phase TEXT NOT NULL,
  status TEXT,
  date_completed TEXT,
  tasks_completed INTEGER,
  tasks_total INTEGER,
  commit_hashes TEXT,
  files_modified TEXT,
  deviations TEXT,
  built TEXT,
  test_status TEXT,
  suggestions TEXT
);
INSERT INTO summaries VALUES (
  '09-01', '09', 'complete', '2026-02-18', 5, 5,
  '["abc123","def456"]', '["src/auth.ts","src/middleware.ts"]',
  '[]', '["auth module"]', 'pass', '[]'
);
INSERT INTO summaries VALUES (
  '09-02', '09', 'complete', '2026-02-18', 3, 3,
  '["ghi789"]', '["src/routes.ts"]',
  '[]', '["route guards"]', 'pass', '[]'
);
INSERT INTO summaries VALUES (
  '09-03', '09', 'partial', '2026-02-19', 2, 4,
  '["jkl012"]', '["src/db.ts"]',
  '["T3 blocked"]', '["db layer"]', 'fail', '["fix T3"]'
);
INSERT INTO summaries VALUES (
  '10-01', '10', 'complete', '2026-02-19', 5, 5,
  '["mno345"]', '["scripts/db/schema.sql"]',
  '[]', '["schema"]', 'pass', '[]'
);
SQL
}

@test "exits 1 with usage when no args" {
  run bash "$SUT" --db "$DB"
  assert_failure
  assert_output --partial "Usage"
}

@test "returns all summaries for phase" {
  run bash "$SUT" 09 --db "$DB"
  assert_success
  # Should have 3 lines (09-01, 09-02, 09-03)
  local line_count
  line_count=$(echo "$output" | wc -l | tr -d ' ')
  [ "$line_count" -eq 3 ]
}

@test "filters by status=complete" {
  run bash "$SUT" 09 --db "$DB" --status complete
  assert_success
  local line_count
  line_count=$(echo "$output" | wc -l | tr -d ' ')
  [ "$line_count" -eq 2 ]
  assert_output --partial "09-01"
  assert_output --partial "09-02"
  refute_output --partial "09-03"
}

@test "filters by status=partial" {
  run bash "$SUT" 09 --db "$DB" --status partial
  assert_success
  assert_output --partial "09-03"
  refute_output --partial "09-01"
}

@test "filters by specific plan" {
  run bash "$SUT" 09 --db "$DB" --plan 09-02
  assert_success
  assert_output --partial "09-02"
  refute_output --partial "09-01"
  refute_output --partial "09-03"
}

@test "field selection returns only requested columns" {
  run bash "$SUT" 09 --db "$DB" --fields "plan_id,status" --plan 09-01
  assert_success
  assert_output --partial "09-01"
  assert_output --partial "complete"
  # Should not have files_modified content
  refute_output --partial "src/auth.ts"
}

@test "empty result for nonexistent phase exits 0" {
  run bash "$SUT" 99 --db "$DB"
  assert_success
  [ -z "$output" ]
}

@test "returns phase 10 summaries separately" {
  run bash "$SUT" 10 --db "$DB"
  assert_success
  assert_output --partial "10-01"
  refute_output --partial "09-"
}

@test "combined status and plan filter" {
  run bash "$SUT" 09 --db "$DB" --status complete --plan 09-01
  assert_success
  assert_output --partial "09-01"
}

@test "exit 1 when database missing" {
  run bash "$SUT" 09 --db "$TEST_WORKDIR/nonexistent.db"
  assert_failure
  assert_output --partial "database not found"
}
