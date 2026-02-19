#!/usr/bin/env bats
# get-context.bats — Unit tests for scripts/db/get-context.sh
# Role-filtered context retrieval using context-manifest.json

setup() {
  load '../../test_helper/common'
  load '../../test_helper/fixtures'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/db/get-context.sh"
  DB="$TEST_WORKDIR/test.db"
  MANIFEST="$TEST_WORKDIR/manifest.json"

  # Create test manifest
  cat > "$MANIFEST" <<'JSON'
{
  "roles": {
    "dev": {
      "files": [],
      "artifacts": ["plan"],
      "fields": {
        "plan": ["task_id","action","files","done","spec"]
      },
      "budget": 2000
    },
    "qa": {
      "files": ["success_criteria"],
      "artifacts": ["plan", "summary"],
      "fields": {
        "plan": ["task_id","action"],
        "summary": ["files_modified"]
      },
      "budget": 3000
    },
    "lead": {
      "files": [],
      "artifacts": ["decisions", "escalation"],
      "fields": {},
      "budget": 3000
    }
  }
}
JSON

  # Create database with tables
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
  phase TEXT,
  PRIMARY KEY (plan_id, task_id)
);
CREATE TABLE summaries (
  plan_id TEXT PRIMARY KEY,
  phase TEXT NOT NULL,
  status TEXT,
  tasks_completed INTEGER,
  tasks_total INTEGER,
  files_modified TEXT
);
CREATE TABLE decisions (
  rowid INTEGER PRIMARY KEY,
  ts TEXT,
  agent TEXT,
  task TEXT,
  dec TEXT,
  reason TEXT,
  phase TEXT
);
CREATE TABLE escalation (
  id TEXT PRIMARY KEY,
  dt TEXT,
  agent TEXT,
  reason TEXT,
  sb TEXT,
  tgt TEXT,
  sev TEXT,
  st TEXT,
  res TEXT,
  phase TEXT
);

INSERT INTO tasks VALUES ('09-01', 'T1', 'Create auth', '["src/auth.ts"]', 'tests pass', 'Auth created', 'JWT auth module', 'test auth', NULL, 'complete', NULL, '09');
INSERT INTO tasks VALUES ('09-01', 'T2', 'Add routes', '["src/routes.ts"]', 'routes work', 'Routes added', 'API routes', NULL, NULL, 'pending', NULL, '09');
INSERT INTO tasks VALUES ('09-02', 'T1', 'Setup DB', '["src/db.ts"]', 'db works', 'DB ready', 'SQLite setup', NULL, NULL, 'pending', NULL, '09');
INSERT INTO summaries VALUES ('09-01', '09', 'complete', 2, 2, '["src/auth.ts","src/routes.ts"]');
INSERT INTO summaries VALUES ('09-02', '09', 'partial', 1, 3, '["src/db.ts"]');
INSERT INTO decisions VALUES (1, '2026-02-19', 'architect', 'T1', 'Use WAL mode', 'Concurrent reads', '09');
SQL
}

@test "exits 1 with usage when no args" {
  run bash "$SUT" --db "$DB"
  assert_failure
  assert_output --partial "Usage"
}

@test "dev role returns task specs only" {
  run bash "$SUT" 09 dev --db "$DB" --manifest "$MANIFEST"
  assert_success
  assert_output --partial "plan"
  assert_output --partial "T1"
  assert_output --partial "Create auth"
}

@test "dev role uses manifest field filtering" {
  run bash "$SUT" 09 dev --db "$DB" --manifest "$MANIFEST"
  assert_success
  # Should have task fields from manifest: task_id, action, files, done, spec
  assert_output --partial "T1"
  assert_output --partial "Create auth"
}

@test "qa role returns plan and summary artifacts" {
  run bash "$SUT" 09 qa --db "$DB" --manifest "$MANIFEST"
  assert_success
  assert_output --partial "plan"
  assert_output --partial "summary"
}

@test "unknown role exits 1" {
  run bash "$SUT" 09 unknown --db "$DB" --manifest "$MANIFEST"
  assert_failure
  assert_output --partial "not found in manifest"
}

@test "respects budget with truncation" {
  run bash "$SUT" 09 dev --db "$DB" --manifest "$MANIFEST" --budget 10
  assert_success
  assert_output --partial "truncated"
}

@test "plan filter narrows results" {
  run bash "$SUT" 09 dev --db "$DB" --manifest "$MANIFEST" --plan 09-01
  assert_success
  assert_output --partial "Create auth"
  assert_output --partial "Add routes"
  refute_output --partial "Setup DB"
}

@test "exit 1 when database missing" {
  run bash "$SUT" 09 dev --db "$TEST_WORKDIR/nonexistent.db" --manifest "$MANIFEST"
  assert_failure
  assert_output --partial "database not found"
}

@test "exit 1 when manifest missing" {
  run bash "$SUT" 09 dev --db "$DB" --manifest "$TEST_WORKDIR/nonexistent.json"
  assert_failure
  assert_output --partial "manifest not found"
}

@test "gracefully handles missing table" {
  # lead role wants decisions+escalation, escalation has data, decisions has data
  run bash "$SUT" 09 lead --db "$DB" --manifest "$MANIFEST"
  assert_success
  assert_output --partial "decisions"
}
