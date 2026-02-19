#!/usr/bin/env bats
# get-phase.bats — Unit tests for scripts/db/get-phase.sh
# Phase metadata retrieval: goals, reqs, success criteria, --reqs-detail, --all-phases

setup() {
  load '../../test_helper/common'
  load '../../test_helper/fixtures'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/db/get-phase.sh"
  DB="$TEST_WORKDIR/test.db"
  # Create phases table (matches import-roadmap.sh schema)
  sqlite3 "$DB" <<'SQL' > /dev/null
PRAGMA journal_mode=WAL;
CREATE TABLE phases (
  phase_num TEXT PRIMARY KEY,
  slug TEXT,
  goal TEXT,
  reqs TEXT,
  success_criteria TEXT,
  deps TEXT,
  status TEXT DEFAULT 'planned'
);
INSERT INTO phases VALUES (
  '09',
  'auth-system',
  'Implement authentication system',
  'REQ-01,REQ-03,REQ-07',
  'All auth tests pass, JWT tokens validated',
  'Phase 8',
  'complete'
);
INSERT INTO phases VALUES (
  '10',
  'sqlite-artifact-store',
  'Build SQLite artifact store',
  'REQ-12,REQ-14',
  'All query scripts return <100 tokens, WAL mode active',
  'Phase 9',
  'planned'
);
CREATE TABLE requirements (
  req_id TEXT PRIMARY KEY,
  description TEXT,
  priority TEXT DEFAULT 'must-have'
);
INSERT INTO requirements VALUES ('REQ-01', '26 specialized agents across 4 departments', 'must-have');
INSERT INTO requirements VALUES ('REQ-03', 'Company hierarchy: Architect -> Lead -> Senior -> Dev', 'must-have');
INSERT INTO requirements VALUES ('REQ-07', 'Teammate API integration with Task tool fallback', 'must-have');
INSERT INTO requirements VALUES ('REQ-12', 'SQLite schema covering all artifact types', 'must-have');
INSERT INTO requirements VALUES ('REQ-14', 'FTS5 full-text search for research and decisions', 'must-have');
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

# --reqs-detail tests

@test "--reqs-detail expands REQ-IDs to descriptions" {
  run bash "$SUT" 09 --db "$DB" --reqs-detail
  assert_success
  assert_output --partial "reqs: REQ-01,REQ-03,REQ-07"
  assert_output --partial "REQ-01: 26 specialized agents across 4 departments"
  assert_output --partial "REQ-03: Company hierarchy"
  assert_output --partial "REQ-07: Teammate API integration"
}

@test "--reqs-detail shows details for phase 10" {
  run bash "$SUT" 10 --db "$DB" --reqs-detail
  assert_success
  assert_output --partial "REQ-12: SQLite schema covering all artifact types"
  assert_output --partial "REQ-14: FTS5 full-text search"
}

@test "--reqs-detail with no requirements table degrades gracefully" {
  # Create DB without requirements table
  local DB2="$TEST_WORKDIR/no-reqs.db"
  sqlite3 "$DB2" <<'SQL' > /dev/null
PRAGMA journal_mode=WAL;
CREATE TABLE phases (
  phase_num TEXT PRIMARY KEY,
  slug TEXT,
  goal TEXT,
  reqs TEXT,
  success_criteria TEXT,
  deps TEXT,
  status TEXT DEFAULT 'planned'
);
INSERT INTO phases VALUES ('01', 'test', 'Test goal', 'REQ-01,REQ-02', 'Test criteria', 'None', 'planned');
SQL
  run bash "$SUT" 01 --db "$DB2" --reqs-detail
  assert_success
  assert_output --partial "reqs: REQ-01,REQ-02"
  # No expanded lines since requirements table doesn't exist
  refute_output --partial "REQ-01:"
}

@test "--reqs-detail indents expanded requirement lines" {
  run bash "$SUT" 09 --db "$DB" --reqs-detail
  assert_success
  # Detail lines should be indented with 2 spaces
  assert_output --partial "  REQ-01:"
}

# --all-phases tests

@test "--all-phases lists all phases" {
  run bash "$SUT" --all-phases --db "$DB"
  assert_success
  assert_output --partial "phase: 09"
  assert_output --partial "phase: 10"
}

@test "--all-phases shows slug and status" {
  run bash "$SUT" --all-phases --db "$DB"
  assert_success
  assert_output --partial "auth-system"
  assert_output --partial "complete"
  assert_output --partial "sqlite-artifact-store"
  assert_output --partial "planned"
}

@test "--all-phases exits 1 when no phases exist" {
  local DB2="$TEST_WORKDIR/empty.db"
  sqlite3 "$DB2" <<'SQL' > /dev/null
PRAGMA journal_mode=WAL;
CREATE TABLE phases (
  phase_num TEXT PRIMARY KEY,
  slug TEXT,
  goal TEXT,
  reqs TEXT,
  success_criteria TEXT,
  deps TEXT,
  status TEXT DEFAULT 'planned'
);
SQL
  run bash "$SUT" --all-phases --db "$DB2"
  assert_failure
  assert_output --partial "no phases found"
}

@test "--all-phases pipe-delimited format" {
  run bash "$SUT" --all-phases --db "$DB"
  assert_success
  # Each line should have phase: NN | slug | status format
  assert_output --partial "09 | auth-system | complete"
  assert_output --partial "10 | sqlite-artifact-store | planned"
}

@test "--all-phases does not require phase number argument" {
  run bash "$SUT" --all-phases --db "$DB"
  assert_success
  # Should not fail with "Usage" even though no positional arg
  refute_output --partial "Usage"
}
