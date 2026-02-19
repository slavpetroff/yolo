#!/usr/bin/env bats
# fts5-search.bats — Validates FTS5 virtual tables and sync triggers

setup() {
  load '../../test_helper/common'
  load '../../test_helper/fixtures'
  mk_test_workdir
  SCHEMA="$SCRIPTS_DIR/db/schema.sql"
  DB="$TEST_WORKDIR/test.db"
  sqlite3 "$DB" "PRAGMA foreign_keys = ON;"
  sqlite3 "$DB" < "$SCHEMA"
}

# ============================================================
# FTS5 Virtual Tables Exist
# ============================================================

@test "research_fts virtual table exists" {
  run sqlite3 "$DB" "SELECT name FROM sqlite_master WHERE type='table' AND name='research_fts';"
  assert_success
  assert_output "research_fts"
}

@test "decisions_fts virtual table exists" {
  run sqlite3 "$DB" "SELECT name FROM sqlite_master WHERE type='table' AND name='decisions_fts';"
  assert_success
  assert_output "decisions_fts"
}

@test "gaps_fts virtual table exists" {
  run sqlite3 "$DB" "SELECT name FROM sqlite_master WHERE type='table' AND name='gaps_fts';"
  assert_success
  assert_output "gaps_fts"
}

# ============================================================
# Research FTS Insert + Search
# ============================================================

@test "research insert triggers FTS index" {
  sqlite3 "$DB" "INSERT INTO research (q, finding, conf, phase) VALUES ('JWT best practices', 'Use RS256 with key rotation', 'high', '01');"
  run sqlite3 "$DB" "SELECT q FROM research_fts WHERE research_fts MATCH 'JWT';"
  assert_success
  assert_output "JWT best practices"
}

@test "research FTS MATCH returns multiple results" {
  sqlite3 "$DB" <<'SQL'
INSERT INTO research (q, finding, conf, phase) VALUES ('JWT auth patterns', 'RS256 is preferred', 'high', '01');
INSERT INTO research (q, finding, conf, phase) VALUES ('OAuth2 token flow', 'JWT bearer tokens', 'medium', '01');
INSERT INTO research (q, finding, conf, phase) VALUES ('Database indexing', 'B-tree vs hash', 'high', '02');
SQL
  run sqlite3 "$DB" "SELECT COUNT(*) FROM research_fts WHERE research_fts MATCH 'JWT';"
  assert_success
  assert_output "2"
}

@test "research FTS searches finding column" {
  sqlite3 "$DB" "INSERT INTO research (q, finding, conf, phase) VALUES ('auth question', 'Use HMAC signatures for validation', 'high', '01');"
  run sqlite3 "$DB" "SELECT q FROM research_fts WHERE research_fts MATCH 'HMAC';"
  assert_success
  assert_output "auth question"
}

@test "research delete removes from FTS index" {
  sqlite3 "$DB" "INSERT INTO research (q, finding, conf, phase) VALUES ('temp query', 'temp finding', 'low', '01');"
  local rowid
  rowid=$(sqlite3 "$DB" "SELECT rowid FROM research WHERE q='temp query';")
  sqlite3 "$DB" "DELETE FROM research WHERE rowid=$rowid;"
  run sqlite3 "$DB" "SELECT COUNT(*) FROM research_fts WHERE research_fts MATCH 'temp';"
  assert_success
  assert_output "0"
}

@test "research update refreshes FTS index" {
  sqlite3 "$DB" "INSERT INTO research (q, finding, conf, phase) VALUES ('unique_xyz query', 'old_abc finding', 'low', '01');"
  local rowid
  rowid=$(sqlite3 "$DB" "SELECT rowid FROM research WHERE q='unique_xyz query';")
  sqlite3 "$DB" "UPDATE research SET finding='updated finding about caching' WHERE rowid=$rowid;"
  # Old finding content gone
  run sqlite3 "$DB" "SELECT COUNT(*) FROM research_fts WHERE research_fts MATCH 'old_abc';"
  assert_output "0"
  # New content found
  run sqlite3 "$DB" "SELECT COUNT(*) FROM research_fts WHERE research_fts MATCH 'caching';"
  assert_output "1"
}

# ============================================================
# Decisions FTS Insert + Search
# ============================================================

@test "decisions insert triggers FTS index" {
  sqlite3 "$DB" "INSERT INTO decisions (ts, agent, task, dec, reason, phase) VALUES ('2026-02-19T10:00:00Z', 'architect', 'T1', 'Use PostgreSQL', 'Better JSON support', '01');"
  run sqlite3 "$DB" "SELECT dec FROM decisions_fts WHERE decisions_fts MATCH 'PostgreSQL';"
  assert_success
  assert_output "Use PostgreSQL"
}

@test "decisions FTS searches reason column" {
  sqlite3 "$DB" "INSERT INTO decisions (ts, agent, task, dec, reason, phase) VALUES ('2026-02-19T10:00:00Z', 'lead', 'T2', 'Add middleware', 'Performance optimization needed', '01');"
  run sqlite3 "$DB" "SELECT dec FROM decisions_fts WHERE decisions_fts MATCH 'optimization';"
  assert_success
  assert_output "Add middleware"
}

@test "decisions delete removes from FTS index" {
  sqlite3 "$DB" "INSERT INTO decisions (ts, agent, task, dec, reason, phase) VALUES ('2026-02-19T10:00:00Z', 'dev', 'T1', 'temp decision', 'temp reason', '01');"
  local rowid
  rowid=$(sqlite3 "$DB" "SELECT rowid FROM decisions WHERE dec='temp decision';")
  sqlite3 "$DB" "DELETE FROM decisions WHERE rowid=$rowid;"
  run sqlite3 "$DB" "SELECT COUNT(*) FROM decisions_fts WHERE decisions_fts MATCH 'temp';"
  assert_success
  assert_output "0"
}

# ============================================================
# Gaps FTS Insert + Search
# ============================================================

@test "gaps insert triggers FTS index" {
  sqlite3 "$DB" "INSERT INTO gaps (id, sev, desc, exp, act, phase) VALUES ('G1', 'major', 'Missing error handling', 'All errors caught', 'Unhandled promise rejection', '01');"
  run sqlite3 "$DB" "SELECT id FROM gaps WHERE rowid IN (SELECT rowid FROM gaps_fts WHERE gaps_fts MATCH 'error');"
  assert_success
  assert_output "G1"
}

@test "gaps FTS searches across desc, exp, act columns" {
  sqlite3 "$DB" "INSERT INTO gaps (id, sev, desc, exp, act, phase) VALUES ('G2', 'minor', 'Test gap', 'Expected authentication', 'Got unauthorized', '02');"
  # Search desc
  run sqlite3 "$DB" "SELECT COUNT(*) FROM gaps_fts WHERE gaps_fts MATCH 'gap';"
  assert_output "1"
  # Search exp
  run sqlite3 "$DB" "SELECT COUNT(*) FROM gaps_fts WHERE gaps_fts MATCH 'authentication';"
  assert_output "1"
  # Search act
  run sqlite3 "$DB" "SELECT COUNT(*) FROM gaps_fts WHERE gaps_fts MATCH 'unauthorized';"
  assert_output "1"
}

@test "gaps delete removes from FTS index" {
  sqlite3 "$DB" "INSERT INTO gaps (id, sev, desc, exp, act, phase) VALUES ('G3', 'critical', 'Temp gap desc', 'expected', 'actual', '01');"
  local rowid
  rowid=$(sqlite3 "$DB" "SELECT rowid FROM gaps WHERE id='G3';")
  sqlite3 "$DB" "DELETE FROM gaps WHERE rowid=$rowid;"
  run sqlite3 "$DB" "SELECT COUNT(*) FROM gaps_fts WHERE gaps_fts MATCH 'Temp';"
  assert_success
  assert_output "0"
}

@test "gaps update refreshes FTS index" {
  sqlite3 "$DB" "INSERT INTO gaps (id, sev, desc, exp, act, phase) VALUES ('G4', 'minor', 'Old description', 'old expected', 'old actual', '01');"
  local rowid
  rowid=$(sqlite3 "$DB" "SELECT rowid FROM gaps WHERE id='G4';")
  sqlite3 "$DB" "UPDATE gaps SET desc='New concurrency issue' WHERE rowid=$rowid;"
  run sqlite3 "$DB" "SELECT COUNT(*) FROM gaps_fts WHERE gaps_fts MATCH 'concurrency';"
  assert_output "1"
  run sqlite3 "$DB" "SELECT COUNT(*) FROM gaps_fts WHERE gaps_fts MATCH '\"Old description\"';"
  assert_output "0"
}

# ============================================================
# Phase-scoped FTS search
# ============================================================

@test "FTS search can filter by phase" {
  sqlite3 "$DB" <<'SQL'
INSERT INTO research (q, finding, conf, phase) VALUES ('auth patterns', 'JWT tokens', 'high', '01');
INSERT INTO research (q, finding, conf, phase) VALUES ('auth patterns', 'OAuth2 flows', 'high', '02');
SQL
  run sqlite3 "$DB" "SELECT COUNT(*) FROM research_fts WHERE research_fts MATCH 'auth AND phase:01';"
  assert_success
  assert_output "1"
}
