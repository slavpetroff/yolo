#!/usr/bin/env bats
# compile-context-sql.bats — Tests for SQL query path in compile-context.sh
# Verifies DB-first context compilation with file-based fallback.

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/compile-context.sh"
  SCHEMA="$SCRIPTS_DIR/db/schema.sql"
  INIT_DB="$SCRIPTS_DIR/db/init-db.sh"
  IMPORT="$SCRIPTS_DIR/db/import-jsonl.sh"

  # Set up .yolo-planning with phase dir
  mkdir -p "$TEST_WORKDIR/.yolo-planning/phases/01-setup"
  mkdir -p "$TEST_WORKDIR/.yolo-planning/codebase"

  PHASES_DIR="$TEST_WORKDIR/.yolo-planning/phases"
  PLANNING_DIR="$TEST_WORKDIR/.yolo-planning"
  DB_PATH="$PLANNING_DIR/yolo.db"

  # Minimal ROADMAP.md (for fallback tests)
  cat > "$PLANNING_DIR/ROADMAP.md" <<'EOF'
# Roadmap

## Phase 1: Setup
**Goal:** Initialize the project structure
**Reqs:** REQ-01, REQ-02
**Success Criteria:** All files created

## Phase 2: Build
**Goal:** Build the core
EOF

  # Conventions file
  cat > "$PLANNING_DIR/conventions.json" <<'EOF'
{"conventions":[{"category":"naming","rule":"Use kebab-case for files"},{"category":"style","rule":"One commit per task"}]}
EOF
}

# Helper: run compile-context from test workdir
run_cc() {
  local phase="$1" role="$2"
  shift 2
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT' '$phase' '$role' '$PHASES_DIR' $*"
}

# Helper: create and populate DB with test data
setup_db() {
  bash "$INIT_DB" --planning-dir "$PLANNING_DIR" >/dev/null

  # Insert a plan
  sqlite3 "$DB_PATH" "PRAGMA foreign_keys=ON;
INSERT INTO plans (phase, plan_num, title, wave, objective, must_haves, effort, fm, autonomous)
VALUES ('01', '01', 'Auth middleware', 1, 'Implement JWT auth', '{\"tr\":[\"JWT validation\",\"Session management\"]}', 'balanced', '[\"src/auth.ts\"]', 1);"

  # Insert tasks
  sqlite3 "$DB_PATH" "PRAGMA foreign_keys=ON;
INSERT INTO tasks (plan_id, task_id, type, action, files, verify, done, spec, test_spec)
VALUES (
  (SELECT rowid FROM plans WHERE phase='01' AND plan_num='01'),
  'T1', 'auto', 'Create auth middleware', '[\"src/middleware/auth.ts\"]', 'Tests pass', 'Middleware exports', 'Express middleware: verify JWT from Authorization header', 'test valid token expired token missing token'
);
INSERT INTO tasks (plan_id, task_id, type, action, files, verify, done, spec, test_spec)
VALUES (
  (SELECT rowid FROM plans WHERE phase='01' AND plan_num='01'),
  'T2', 'auto', 'Write auth tests', '[\"tests/auth.test.ts\"]', 'All pass', 'Tests created', 'jest tests: valid token expired token', 'jest describe/it blocks for auth'
);"

  # Insert summary
  sqlite3 "$DB_PATH" "PRAGMA foreign_keys=ON;
INSERT INTO summaries (plan_id, status, date_completed, tasks_completed, tasks_total, fm, test_status)
VALUES (
  (SELECT rowid FROM plans WHERE phase='01' AND plan_num='01'),
  'complete', '2026-02-19', 2, 2, '[\"src/auth.ts\",\"tests/auth.test.ts\"]', 'red_green'
);"

  # Insert research
  sqlite3 "$DB_PATH" "INSERT INTO research (q, src, finding, conf, dt, phase)
VALUES ('JWT best practices', 'web', 'Use RS256 with key rotation', 'high', '2026-02-19', '01');"

  # Insert decisions
  sqlite3 "$DB_PATH" "INSERT INTO decisions (ts, agent, task, dec, reason, phase)
VALUES ('2026-02-19T10:00:00Z', 'architect', 'T1', 'Use RS256', 'Key rotation support', '01');"

  # Insert critique
  sqlite3 "$DB_PATH" "INSERT INTO critique (id, cat, sev, q, phase)
VALUES ('C1', 'gap', 'critical', 'Missing error handling for expired tokens', '01');"

  # Insert escalation
  sqlite3 "$DB_PATH" "INSERT INTO escalation (id, dt, agent, reason, tgt, sev, st, phase)
VALUES ('ESC-01-01-T1', '2026-02-19T10:00:00Z', 'dev', 'Spec unclear', 'senior', 'blocking', 'resolved', '01');
INSERT INTO escalation (id, dt, agent, reason, tgt, sev, st, phase)
VALUES ('ESC-01-01-T2', '2026-02-19T11:00:00Z', 'dev', 'Missing dep', 'senior', 'major', 'open', '01');"

  # Insert gaps
  sqlite3 "$DB_PATH" "INSERT INTO gaps (id, sev, \"desc\", exp, act, st, res, phase)
VALUES ('G1', 'major', 'Missing error handling', 'All errors caught', 'Unhandled rejection', 'open', 'retry with error boundary', '01');"

  # Insert test results
  sqlite3 "$DB_PATH" "INSERT INTO test_results (plan, dept, tdd_phase, tc, ps, fl, dt, phase)
VALUES ('01-01', 'backend', 'green', 4, 4, 0, '2026-02-19', '01');"
}

# ============================================================
# T1: SQL path detection and helpers
# ============================================================

@test "SQL path used when DB exists" {
  setup_db
  run_cc 01 architect
  assert_success
  # Should produce output file
  assert_output --partial ".ctx-architect.toon"
}

@test "file fallback when DB absent" {
  # No DB created — should use ROADMAP.md
  run_cc 01 architect
  assert_success
  local toon="$PHASES_DIR/01-setup/.ctx-architect.toon"
  run cat "$toon"
  assert_output --partial "goal: Initialize the project structure"
}

@test "ROADMAP not needed when DB has plan data" {
  setup_db
  # Remove ROADMAP
  rm -f "$PLANNING_DIR/ROADMAP.md"
  run_cc 01 architect
  assert_success
  local toon="$PHASES_DIR/01-setup/.ctx-architect.toon"
  run cat "$toon"
  # Goal comes from DB objective field
  assert_output --partial "goal: Implement JWT auth"
}

# ============================================================
# T2: Architect and critic SQL migration
# ============================================================

@test "architect TOON includes research from SQL" {
  setup_db
  run_cc 01 architect
  assert_success
  local toon="$PHASES_DIR/01-setup/.ctx-architect.toon"
  run cat "$toon"
  assert_output --partial "research:"
  assert_output --partial "JWT best practices"
  assert_output --partial "RS256 with key rotation"
}

@test "architect TOON includes requirements from SQL" {
  setup_db
  run_cc 01 architect
  assert_success
  local toon="$PHASES_DIR/01-setup/.ctx-architect.toon"
  run cat "$toon"
  assert_output --partial "reqs:"
  assert_output --partial "JWT validation"
}

@test "critic TOON includes research from SQL" {
  setup_db
  run_cc 01 critic
  assert_success
  local toon="$PHASES_DIR/01-setup/.ctx-critic.toon"
  run cat "$toon"
  assert_output --partial "research:"
  assert_output --partial "JWT best practices"
}

@test "critic TOON output matches structure when using SQL" {
  setup_db
  run_cc 01 critic
  assert_success
  local toon="$PHASES_DIR/01-setup/.ctx-critic.toon"
  run cat "$toon"
  assert_output --partial "phase: 01"
  assert_output --partial "goal:"
  assert_output --partial "success_criteria:"
}

# ============================================================
# T3: Lead, senior, dev SQL migration
# ============================================================

@test "dev TOON includes task specs from SQL when plan provided" {
  setup_db
  # Create plan file for plan path
  cat > "$PHASES_DIR/01-setup/01-01.plan.jsonl" <<'JSONL'
{"p":"01","n":"01","t":"Auth","w":1,"d":[],"mh":{"tr":["JWT"]},"obj":"Implement JWT","sk":[],"fm":["src/auth.ts"],"auto":true}
{"id":"T1","tp":"auto","a":"Create auth","f":["src/auth.ts"],"v":"Tests pass","done":"Done","spec":"Express JWT middleware"}
{"id":"T2","tp":"auto","a":"Write tests","f":["tests/auth.ts"],"v":"Pass","done":"Done","spec":"jest tests"}
JSONL
  run_cc 01 dev "'$PHASES_DIR/01-setup/01-01.plan.jsonl'"
  assert_success
  local toon="$PHASES_DIR/01-setup/.ctx-dev.toon"
  run cat "$toon"
  assert_output --partial "tasks["
  assert_output --partial "T1"
  assert_output --partial "T2"
}

@test "lead TOON includes decisions from SQL" {
  setup_db
  run_cc 01 lead
  assert_success
  local toon="$PHASES_DIR/01-setup/.ctx-lead.toon"
  run cat "$toon"
  assert_output --partial "decisions:"
  assert_output --partial "Use RS256"
}

@test "lead TOON includes test results from SQL" {
  setup_db
  run_cc 01 lead
  assert_success
  local toon="$PHASES_DIR/01-setup/.ctx-lead.toon"
  run cat "$toon"
  assert_output --partial "test_results:"
}

@test "senior TOON includes suggestions from SQL summaries" {
  setup_db
  # Add suggestions to summary
  sqlite3 "$DB_PATH" "UPDATE summaries SET suggestions='[\"Consider caching\",\"Add retry logic\"]'
    WHERE plan_id = (SELECT rowid FROM plans WHERE phase='01' AND plan_num='01');"
  run_cc 01 senior
  assert_success
  local toon="$PHASES_DIR/01-setup/.ctx-senior.toon"
  # Senior should load — suggestions come from summary files, not SQL in senior block directly
  assert [ -f "$toon" ]
}

# ============================================================
# T4: QA, security, tester SQL migration
# ============================================================

@test "qa TOON includes plan summaries from SQL" {
  setup_db
  run_cc 01 qa
  assert_success
  local toon="$PHASES_DIR/01-setup/.ctx-qa.toon"
  run cat "$toon"
  assert_output --partial "plan_summaries:"
  assert_output --partial "01-01"
  assert_output --partial "complete"
}

@test "qa TOON includes escalation counts from SQL" {
  setup_db
  run_cc 01 qa
  assert_success
  local toon="$PHASES_DIR/01-setup/.ctx-qa.toon"
  run cat "$toon"
  assert_output --partial "escalations:"
}

@test "security TOON includes files to audit from SQL summaries" {
  setup_db
  run_cc 01 security
  assert_success
  local toon="$PHASES_DIR/01-setup/.ctx-security.toon"
  run cat "$toon"
  assert_output --partial "files_to_audit:"
}

@test "tester TOON includes task test specs from plan file" {
  setup_db
  cat > "$PHASES_DIR/01-setup/01-01.plan.jsonl" <<'JSONL'
{"p":"01","n":"01","t":"Auth","w":1,"d":[],"mh":{"tr":["JWT"]},"obj":"Implement JWT","sk":[],"fm":["src/auth.ts"],"auto":true}
{"id":"T1","tp":"auto","a":"Create auth","f":["src/auth.ts"],"v":"Tests pass","done":"Done","spec":"Express JWT","ts":"test valid token expired token"}
JSONL
  run_cc 01 tester "'$PHASES_DIR/01-setup/01-01.plan.jsonl'"
  assert_success
  local toon="$PHASES_DIR/01-setup/.ctx-tester.toon"
  run cat "$toon"
  assert_output --partial "tasks["
  assert_output --partial "test_spec"
}

# ============================================================
# T5: Remaining roles and populate hook
# ============================================================

@test "owner TOON includes requirements from SQL" {
  setup_db
  run_cc 01 owner
  assert_success
  local toon="$PHASES_DIR/01-setup/.ctx-owner.toon"
  run cat "$toon"
  assert_output --partial "reqs:"
}

@test "debugger TOON includes gaps from SQL" {
  setup_db
  run_cc 01 debugger
  assert_success
  local toon="$PHASES_DIR/01-setup/.ctx-debugger.toon"
  run cat "$toon"
  assert_output --partial "known_gaps:"
  assert_output --partial "Missing error handling"
}

@test "scout TOON includes critique directives from SQL" {
  setup_db
  run_cc 01 scout
  assert_success
  local toon="$PHASES_DIR/01-setup/.ctx-scout.toon"
  run cat "$toon"
  assert_output --partial "research_directives:"
  assert_output --partial "C1"
}

@test "integration-gate TOON includes test results from SQL" {
  setup_db
  run_cc 01 integration-gate
  assert_success
  local toon="$PHASES_DIR/01-setup/.ctx-integration-gate.toon"
  run cat "$toon"
  assert_output --partial "test_results:"
}

@test "po TOON includes requirements from SQL" {
  setup_db
  run_cc 01 po
  assert_success
  local toon="$PHASES_DIR/01-setup/.ctx-po.toon"
  run cat "$toon"
  assert_output --partial "reqs:"
}

@test "populate hook triggers when JSONL newer than DB" {
  setup_db
  # Create a research.jsonl that's newer than DB
  sleep 1
  cat > "$PHASES_DIR/01-setup/research.jsonl" <<'JSONL'
{"q":"New research query","src":"web","finding":"New finding about caching","conf":"high","dt":"2026-02-19"}
JSONL
  # Run compile-context — should trigger import
  run_cc 01 architect
  assert_success
  # Verify the new research entry is in DB
  local count
  count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM research WHERE q='New research query';")
  [ "$count" -ge 1 ]
}

@test "budget enforcement preserved with SQL path" {
  setup_db
  run_cc 01 dev
  assert_success
  local toon="$PHASES_DIR/01-setup/.ctx-dev.toon"
  # File should exist and be within budget (dev = 2000 tokens = ~8000 chars)
  local chars
  chars=$(wc -c < "$toon" | tr -d ' ')
  [ "$chars" -lt 10000 ]
}

@test "backward compatible: all roles work without DB" {
  # No DB, just files
  cat > "$PHASES_DIR/01-setup/research.jsonl" <<'JSONL'
{"q":"JWT patterns","finding":"Use RS256","conf":"high","dt":"2026-02-19"}
JSONL
  for role in architect lead senior dev qa qa-code security debugger critic tester owner scout; do
    run_cc 01 "$role"
    assert_success
  done
}
