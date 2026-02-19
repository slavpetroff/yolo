#!/usr/bin/env bats
# get-phase.bats — Unit tests for scripts/db/get-phase.sh
# Phase metadata retrieval: goals, reqs, success criteria

setup() {
  load '../../test_helper/common'
  load '../../test_helper/fixtures'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/db/get-phase.sh"
  DB="$TEST_WORKDIR/test.db"
  # Create phases table
  sqlite3 "$DB" <<'SQL'
CREATE TABLE phases (
  phase_num TEXT PRIMARY KEY,
  goal TEXT,
  reqs TEXT,
  success_criteria TEXT,
  slug TEXT
);
INSERT INTO phases VALUES (
  '09',
  'Implement authentication system',
  'REQ-01,REQ-03,REQ-07',
  'All auth tests pass, JWT tokens validated',
  'auth-system'
);
INSERT INTO phases VALUES (
  '10',
  'Build SQLite artifact store',
  'REQ-12,REQ-14',
  'All query scripts return <100 tokens, WAL mode active',
  'sqlite-artifact-store'
);
SQL
}

@test "exits 1 with usage when no args" {
  run bash "$SUT" --db "$DB"
  assert_failure
  assert_output --partial "Usage"
}

@test "returns full phase info by default" {
  run bash "$SUT" 09 --db "$DB"
  assert_success
  assert_output --partial "phase: 09"
  assert_output --partial "goal: Implement authentication system"
  assert_output --partial "reqs: REQ-01,REQ-03,REQ-07"
  assert_output --partial "success: All auth tests pass"
}

@test "--goals returns only goal info" {
  run bash "$SUT" 09 --db "$DB" --goals
  assert_success
  assert_output --partial "goal: Implement authentication system"
  refute_output --partial "success:"
}

@test "--reqs returns only requirements" {
  run bash "$SUT" 09 --db "$DB" --reqs
  assert_success
  assert_output --partial "reqs: REQ-01,REQ-03,REQ-07"
  refute_output --partial "goal:"
}

@test "--success returns only success criteria" {
  run bash "$SUT" 09 --db "$DB" --success
  assert_success
  assert_output --partial "success: All auth tests pass"
  refute_output --partial "goal:"
}

@test "--full returns all sections" {
  run bash "$SUT" 09 --db "$DB" --full
  assert_success
  assert_output --partial "phase: 09"
  assert_output --partial "slug: auth-system"
  assert_output --partial "goal:"
  assert_output --partial "reqs:"
  assert_output --partial "success:"
}

@test "TOON format output has key-value lines" {
  run bash "$SUT" 09 --db "$DB" --full
  assert_success
  # Count output lines (should have phase, slug, goal, reqs, success)
  local line_count
  line_count=$(echo "$output" | wc -l | tr -d ' ')
  [ "$line_count" -eq 5 ]
}

@test "exit 1 on missing phase" {
  run bash "$SUT" 99 --db "$DB"
  assert_failure
  assert_output --partial "not found"
}

@test "returns different phase data for phase 10" {
  run bash "$SUT" 10 --db "$DB" --goals
  assert_success
  assert_output --partial "Build SQLite artifact store"
  refute_output --partial "authentication"
}

@test "exit 1 when database missing" {
  run bash "$SUT" 09 --db "$TEST_WORKDIR/nonexistent.db"
  assert_failure
  assert_output --partial "database not found"
}
