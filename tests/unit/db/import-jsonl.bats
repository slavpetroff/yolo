#!/usr/bin/env bats
# import-jsonl.bats — Unit tests for scripts/db/import-jsonl.sh

setup() {
  load '../../test_helper/common'
  load '../../test_helper/fixtures'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/db/import-jsonl.sh"
  DB="$TEST_WORKDIR/test.db"
  # Create DB with schema
  sqlite3 "$DB" < "$SCRIPTS_DIR/db/schema.sql"
  sqlite3 "$DB" "PRAGMA journal_mode=WAL;"
}

mk_plan_file() {
  local file="$TEST_WORKDIR/10-03.plan.jsonl"
  cat > "$file" <<'JSONL'
{"p":"10","n":"03","t":"Write scripts","w":1,"d":[],"mh":{"tr":["insert-task.sh"],"ar":[],"kl":[]},"obj":"Create write scripts","sk":["commit"],"fm":["scripts/db/insert-task.sh"],"auto":true}
{"id":"T1","tp":"auto","a":"Create insert-task.sh","f":["scripts/db/insert-task.sh"],"v":"Tests pass","done":"Script created","spec":"Create insert-task.sh with upsert"}
{"id":"T2","tp":"auto","a":"Create complete-task.sh","f":["scripts/db/complete-task.sh"],"v":"Tests pass","done":"Script created","spec":"Create complete-task.sh"}
JSONL
  echo "$file"
}

mk_summary_file() {
  # Need plan to exist first
  local plan_file
  plan_file=$(mk_plan_file)
  bash "$SUT" --type plan --file "$plan_file" --phase 10 --db "$DB" >/dev/null

  local file="$TEST_WORKDIR/10-03.summary.jsonl"
  cat > "$file" <<'JSONL'
{"p":"10","n":"03","t":"Write scripts","s":"complete","dt":"2026-02-19","tc":2,"tt":2,"ch":["abc123"],"fm":["scripts/db/insert-task.sh"],"dv":[],"built":["insert-task.sh","complete-task.sh"],"tst":"red_green"}
JSONL
  echo "$file"
}

mk_critique_file() {
  local file="$TEST_WORKDIR/critique.jsonl"
  cat > "$file" <<'JSONL'
{"id":"C1","cat":"gap","sev":"major","q":"Missing error handling","ctx":"insert-task.sh","sug":"Add try/catch"}
{"id":"C2","cat":"improvement","sev":"minor","q":"Naming inconsistency","ctx":"schema.sql"}
{"id":"C3","cat":"risk","sev":"critical","q":"SQL injection possible","ctx":"All scripts","sug":"Use parameterized queries"}
JSONL
  echo "$file"
}

@test "imports plan file (header + tasks)" {
  local plan_file
  plan_file=$(mk_plan_file)
  run bash "$SUT" --type plan --file "$plan_file" --phase 10 --db "$DB"
  assert_success
  assert_output --partial "Imported 3 rows into plans+tasks"
  # Verify plan header
  local title
  title=$(sqlite3 "$DB" "SELECT title FROM plans WHERE phase='10' AND plan_num='03';")
  [ "$title" = "Write scripts" ]
  # Verify tasks
  local task_count
  task_count=$(sqlite3 "$DB" "SELECT count(*) FROM tasks;")
  [ "$task_count" -eq 2 ]
  # Verify task action
  local action
  action=$(sqlite3 "$DB" "SELECT action FROM tasks WHERE task_id='T1';")
  [ "$action" = "Create insert-task.sh" ]
}

@test "imports summary" {
  local summary_file
  summary_file=$(mk_summary_file)
  run bash "$SUT" --type summary --file "$summary_file" --phase 10 --db "$DB"
  assert_success
  assert_output --partial "Imported 1 row into summaries"
  local status
  status=$(sqlite3 "$DB" "SELECT status FROM summaries;")
  [ "$status" = "complete" ]
}

@test "imports multi-line critique" {
  local critique_file
  critique_file=$(mk_critique_file)
  run bash "$SUT" --type critique --file "$critique_file" --phase 10 --db "$DB"
  assert_success
  assert_output --partial "Imported 3 rows into critique"
  local count
  count=$(sqlite3 "$DB" "SELECT count(*) FROM critique;")
  [ "$count" -eq 3 ]
  # Verify first critique
  local sev
  sev=$(sqlite3 "$DB" "SELECT sev FROM critique WHERE id='C3';")
  [ "$sev" = "critical" ]
}

@test "imports research" {
  local file="$TEST_WORKDIR/research.jsonl"
  cat > "$file" <<'JSONL'
{"q":"How does SQLite WAL work?","src":"docs","finding":"WAL allows concurrent reads","conf":"high","dt":"2026-02-19"}
{"q":"FTS5 performance","src":"web","finding":"FTS5 handles 100k rows well","conf":"medium","dt":"2026-02-19"}
JSONL
  run bash "$SUT" --type research --file "$file" --phase 10 --db "$DB"
  assert_success
  assert_output --partial "Imported 2 rows into research"
}

@test "imports decisions" {
  local file="$TEST_WORKDIR/decisions.jsonl"
  cat > "$file" <<'JSONL'
{"ts":"2026-02-19T10:00:00Z","agent":"architect","dec":"Use SQLite","reason":"Zero deps","alts":["PostgreSQL","JSON files"]}
JSONL
  run bash "$SUT" --type decisions --file "$file" --phase 10 --db "$DB"
  assert_success
  assert_output --partial "Imported 1 rows into decisions"
}

@test "transaction rollback on error — rejects missing file" {
  run bash "$SUT" --type plan --file /nonexistent/file.jsonl --phase 10 --db "$DB"
  assert_failure
  assert_output --partial "file not found"
}

@test "rejects unknown type" {
  local file="$TEST_WORKDIR/dummy.jsonl"
  echo '{}' > "$file"
  run bash "$SUT" --type foobar --file "$file" --phase 10 --db "$DB"
  assert_failure
  assert_output --partial "unknown type"
}

@test "missing --type exits 1" {
  run bash "$SUT" --file /tmp/x --phase 10 --db "$DB"
  assert_failure
  assert_output --partial "--type is required"
}

@test "missing --file exits 1" {
  run bash "$SUT" --type plan --phase 10 --db "$DB"
  assert_failure
  assert_output --partial "--file is required"
}

@test "missing --phase exits 1" {
  local file="$TEST_WORKDIR/dummy.jsonl"
  echo '{}' > "$file"
  run bash "$SUT" --type plan --file "$file" --db "$DB"
  assert_failure
  assert_output --partial "--phase is required"
}
