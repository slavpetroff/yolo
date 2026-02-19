#!/usr/bin/env bats
# Tests for scripts/db/verify-migration.sh

setup() {
  export TEST_DIR="$BATS_TEST_TMPDIR/test-planning"
  export TEST_DB="$BATS_TEST_TMPDIR/test-yolo.db"
  mkdir -p "$TEST_DIR/phases/01-test-phase"
}

teardown() {
  rm -rf "$TEST_DIR" "$TEST_DB" "${TEST_DB}-wal" "${TEST_DB}-shm"
}

# Helper: create and migrate clean test data
setup_clean_migration() {
  cat > "$TEST_DIR/phases/01-test-phase/01-01.plan.jsonl" <<'EOF'
{"p":"01","n":"01","t":"Test plan","w":1,"mh":["must have"]}
{"id":"T1","a":"Do task 1","f":["file1.sh"],"v":"test check","done":false}
{"id":"T2","a":"Do task 2","f":["file2.sh"],"v":"test check 2","done":true}
EOF

  cat > "$TEST_DIR/phases/01-test-phase/01-01.summary.jsonl" <<'EOF'
{"p":"01","n":"01","s":"complete","dt":"2026-02-19","tc":2,"tt":2}
EOF

  bash scripts/db/migrate-milestone.sh --planning-dir "$TEST_DIR" --db "$TEST_DB" >/dev/null 2>&1
}

@test "requires --planning-dir" {
  run bash scripts/db/verify-migration.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"--planning-dir is required"* ]]
}

@test "fails on missing DB" {
  run bash scripts/db/verify-migration.sh --planning-dir "$TEST_DIR" --db /nonexistent/db
  [ "$status" -eq 1 ]
  [[ "$output" == *"database not found"* ]]
}

@test "detects matching state (PASS)" {
  setup_clean_migration

  run bash scripts/db/verify-migration.sh --planning-dir "$TEST_DIR" --db "$TEST_DB"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESULT: PASS"* ]]
  [[ "$output" == *"Errors: 0"* ]]
}

@test "detects missing DB rows (FAIL)" {
  setup_clean_migration

  # Add a plan file without importing to DB
  cat > "$TEST_DIR/phases/01-test-phase/01-02.plan.jsonl" <<'EOF'
{"p":"01","n":"02","t":"Extra plan","w":1}
{"id":"T1","a":"Extra task","f":["x.sh"],"v":"ok","done":false}
EOF

  run bash scripts/db/verify-migration.sh --planning-dir "$TEST_DIR" --db "$TEST_DB"
  [ "$status" -eq 1 ]
  [[ "$output" == *"RESULT: FAIL"* ]]
  [[ "$output" == *"FAIL: Plans:"* ]]
}

@test "verifies FTS indexes" {
  setup_clean_migration

  # Add research data to DB
  sqlite3 "$TEST_DB" "INSERT INTO research (q, finding, conf, phase) VALUES ('test query','test finding','high','01');"

  # Add matching file
  echo '{"q":"test query","finding":"test finding","conf":"high","phase":"01"}' > "$TEST_DIR/phases/01-test-phase/research.jsonl"

  run bash scripts/db/verify-migration.sh --planning-dir "$TEST_DIR" --db "$TEST_DB"
  [ "$status" -eq 0 ]
  [[ "$output" == *"research_fts populated"* ]]
}

@test "detects FTS gaps when FTS is empty" {
  setup_clean_migration

  # Create a DB with research table but NO FTS table
  # (simulates a schema without FTS triggers)
  local BAD_DB="$BATS_TEST_TMPDIR/bad-fts.db"
  sqlite3 "$BAD_DB" <<'SQL'
PRAGMA journal_mode=WAL;
CREATE TABLE plans (rowid INTEGER PRIMARY KEY, phase TEXT, plan_num TEXT, title TEXT, wave INTEGER DEFAULT 1, depends_on TEXT, xd TEXT, must_haves TEXT, objective TEXT, effort TEXT DEFAULT 'balanced', skills TEXT, fm TEXT, autonomous INTEGER DEFAULT 0, created_at TEXT, updated_at TEXT, UNIQUE(phase, plan_num));
CREATE TABLE tasks (rowid INTEGER PRIMARY KEY, plan_id INTEGER, task_id TEXT, type TEXT, action TEXT, files TEXT, verify TEXT, done TEXT, spec TEXT, test_spec TEXT, task_depends TEXT, status TEXT DEFAULT 'pending', assigned_to TEXT, completed_at TEXT, files_written TEXT, summary TEXT, created_at TEXT, updated_at TEXT, UNIQUE(plan_id, task_id));
CREATE TABLE summaries (rowid INTEGER PRIMARY KEY, plan_id INTEGER, status TEXT, date_completed TEXT, tasks_completed INTEGER, tasks_total INTEGER, commit_hashes TEXT, fm TEXT, deviations TEXT, built TEXT, test_status TEXT, suggestions TEXT, created_at TEXT, updated_at TEXT, UNIQUE(plan_id));
CREATE TABLE critique (rowid INTEGER PRIMARY KEY, id TEXT, cat TEXT, sev TEXT, q TEXT, ctx TEXT, sug TEXT, st TEXT DEFAULT 'open', cf INTEGER DEFAULT 0, rd INTEGER DEFAULT 1, phase TEXT, created_at TEXT);
CREATE TABLE research (rowid INTEGER PRIMARY KEY, q TEXT, src TEXT, finding TEXT, conf TEXT, dt TEXT, rel TEXT, brief_for TEXT, mode TEXT, priority TEXT, ra TEXT, rt TEXT, resolved_at TEXT, phase TEXT, created_at TEXT);
CREATE TABLE decisions (rowid INTEGER PRIMARY KEY, ts TEXT, agent TEXT, task TEXT, dec TEXT, reason TEXT, alts TEXT, phase TEXT, created_at TEXT);
CREATE TABLE escalation (rowid INTEGER PRIMARY KEY, id TEXT, dt TEXT, agent TEXT, reason TEXT, sb TEXT, tgt TEXT, sev TEXT, st TEXT DEFAULT 'open', res TEXT, phase TEXT, created_at TEXT);
CREATE TABLE gaps (rowid INTEGER PRIMARY KEY, id TEXT, sev TEXT, "desc" TEXT, exp TEXT, act TEXT, st TEXT DEFAULT 'open', res TEXT, phase TEXT, created_at TEXT);
CREATE TABLE phases (phase_num TEXT PRIMARY KEY, slug TEXT, goal TEXT, reqs TEXT, success_criteria TEXT, deps TEXT, status TEXT DEFAULT 'planned');
CREATE VIRTUAL TABLE research_fts USING fts5(q, finding, conf, phase, content=research, content_rowid=rowid);
CREATE VIRTUAL TABLE decisions_fts USING fts5(dec, reason, agent, phase, content=decisions, content_rowid=rowid);
CREATE VIRTUAL TABLE gaps_fts USING fts5(desc, exp, act, res, phase, content=gaps, content_rowid=rowid);
-- Insert research WITHOUT trigger (no FTS sync)
INSERT INTO research (q, finding, conf, phase) VALUES ('test','finding','high','01');
SQL

  echo '{"q":"test","finding":"finding","conf":"high","phase":"01"}' > "$TEST_DIR/phases/01-test-phase/research.jsonl"

  run bash scripts/db/verify-migration.sh --planning-dir "$TEST_DIR" --db "$BAD_DB"
  [ "$status" -eq 1 ]
  [[ "$output" == *"research_fts empty"* ]]
  rm -f "$BAD_DB" "${BAD_DB}-wal" "${BAD_DB}-shm"
}

@test "verifies integrity check passes" {
  setup_clean_migration

  run bash scripts/db/verify-migration.sh --planning-dir "$TEST_DIR" --db "$TEST_DB"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Integrity check: ok"* ]]
}

@test "verifies WAL journal mode" {
  setup_clean_migration

  run bash scripts/db/verify-migration.sh --planning-dir "$TEST_DIR" --db "$TEST_DB"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Journal mode: WAL"* ]]
}

@test "verifies phases table populated" {
  cat > "$TEST_DIR/ROADMAP.md" <<'EOF'
# Test Roadmap

## Phase 1: Test Phase

**Goal:** Test goal

**Requirements:** None

**Success Criteria:**
- Criterion

**Dependencies:** None
EOF

  bash scripts/db/migrate-milestone.sh --planning-dir "$TEST_DIR" --db "$TEST_DB" >/dev/null 2>&1

  run bash scripts/db/verify-migration.sh --planning-dir "$TEST_DIR" --db "$TEST_DB"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Phases table populated"* ]]
}

@test "reports discrepancies count" {
  setup_clean_migration

  # Create extra file not in DB
  cat > "$TEST_DIR/phases/01-test-phase/01-02.plan.jsonl" <<'EOF'
{"p":"01","n":"02","t":"Extra","w":1}
EOF

  run bash scripts/db/verify-migration.sh --planning-dir "$TEST_DIR" --db "$TEST_DB"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Errors:"* ]]
}

@test "spot-checks plan title" {
  setup_clean_migration

  run bash scripts/db/verify-migration.sh --planning-dir "$TEST_DIR" --db "$TEST_DB"
  [ "$status" -eq 0 ]
  [[ "$output" == *"title matches"* ]]
}

@test "help flag shows usage" {
  run bash scripts/db/verify-migration.sh --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "handles empty planning dir" {
  # Empty DB
  sqlite3 "$TEST_DB" < scripts/db/schema.sql
  sqlite3 "$TEST_DB" "PRAGMA journal_mode=WAL;" >/dev/null

  run bash scripts/db/verify-migration.sh --planning-dir "$TEST_DIR" --db "$TEST_DB"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESULT: PASS"* ]]
}
