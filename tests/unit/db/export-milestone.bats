#!/usr/bin/env bats
# Tests for scripts/db/export-milestone.sh

setup() {
  export TEST_DIR="$BATS_TEST_TMPDIR/test-planning"
  export TEST_DB="$BATS_TEST_TMPDIR/test-yolo.db"
  export EXPORT_DIR="$BATS_TEST_TMPDIR/test-export"
  mkdir -p "$TEST_DIR/phases/01-test-phase"
  mkdir -p "$TEST_DIR/phases/02-second-phase"
  mkdir -p "$EXPORT_DIR/phases/01-test-phase"
  mkdir -p "$EXPORT_DIR/phases/02-second-phase"
}

teardown() {
  rm -rf "$TEST_DIR" "$TEST_DB" "${TEST_DB}-wal" "${TEST_DB}-shm" "$EXPORT_DIR"
}

# Helper: create and migrate a test milestone
setup_test_db() {
  # Create plan files
  cat > "$TEST_DIR/phases/01-test-phase/01-01.plan.jsonl" <<'EOF'
{"p":"01","n":"01","t":"Test plan one","w":1,"mh":["must have 1"]}
{"id":"T1","a":"Do task 1","f":["file1.sh"],"v":"test -f file1.sh","done":false}
{"id":"T2","a":"Do task 2","f":["file2.sh"],"v":"test -f file2.sh","done":true}
EOF

  cat > "$TEST_DIR/phases/01-test-phase/01-01.summary.jsonl" <<'EOF'
{"p":"01","n":"01","s":"complete","dt":"2026-02-19","tc":2,"tt":2,"ch":["abc1234"],"tst":"green_only"}
EOF

  cat > "$TEST_DIR/phases/02-second-phase/02-01.plan.jsonl" <<'EOF'
{"p":"02","n":"01","t":"Second phase plan","w":1,"mh":["must have 2"]}
{"id":"T1","a":"Second task","f":["second.sh"],"v":"echo ok","done":false}
EOF

  # Migrate to DB
  bash scripts/db/migrate-milestone.sh --planning-dir "$TEST_DIR" --db "$TEST_DB" >/dev/null 2>&1
}

@test "requires --planning-dir" {
  run bash scripts/db/export-milestone.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"--planning-dir is required"* ]]
}

@test "fails on missing DB" {
  run bash scripts/db/export-milestone.sh --planning-dir "$EXPORT_DIR" --db /nonexistent/db
  [ "$status" -eq 1 ]
  [[ "$output" == *"database not found"* ]]
}

@test "exports plans with header and tasks" {
  setup_test_db

  run bash scripts/db/export-milestone.sh --planning-dir "$EXPORT_DIR" --db "$TEST_DB"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Exported:"* ]]

  # Check plan file exists
  [ -f "$EXPORT_DIR/phases/01-test-phase/01-01.plan.jsonl" ]

  # Check header line
  header=$(head -1 "$EXPORT_DIR/phases/01-test-phase/01-01.plan.jsonl")
  echo "$header" | jq -e '.p == "01"'
  echo "$header" | jq -e '.n == "01"'
  echo "$header" | jq -e '.t == "Test plan one"'

  # Check task lines
  line_count=$(wc -l < "$EXPORT_DIR/phases/01-test-phase/01-01.plan.jsonl" | tr -d ' ')
  [ "$line_count" -eq 3 ]  # header + 2 tasks
}

@test "exports summaries" {
  setup_test_db

  run bash scripts/db/export-milestone.sh --planning-dir "$EXPORT_DIR" --db "$TEST_DB"
  [ "$status" -eq 0 ]

  [ -f "$EXPORT_DIR/phases/01-test-phase/01-01.summary.jsonl" ]
  summary=$(cat "$EXPORT_DIR/phases/01-test-phase/01-01.summary.jsonl")
  echo "$summary" | jq -e '.s == "complete"'
  echo "$summary" | jq -e '.tc == 2'
}

@test "exports single phase with --phase flag" {
  setup_test_db

  run bash scripts/db/export-milestone.sh --planning-dir "$EXPORT_DIR" --db "$TEST_DB" --phase 01
  [ "$status" -eq 0 ]

  # Phase 01 should be exported
  [ -f "$EXPORT_DIR/phases/01-test-phase/01-01.plan.jsonl" ]

  # Phase 02 should NOT be exported
  [ ! -f "$EXPORT_DIR/phases/02-second-phase/02-01.plan.jsonl" ]
}

@test "round-trip: import then export matches original format" {
  setup_test_db

  bash scripts/db/export-milestone.sh --planning-dir "$EXPORT_DIR" --db "$TEST_DB" >/dev/null 2>&1

  # Compare plan header keys (both should have p, n, t, w)
  orig_header=$(head -1 "$TEST_DIR/phases/01-test-phase/01-01.plan.jsonl" | jq -S '{p,n,t,w}')
  exp_header=$(head -1 "$EXPORT_DIR/phases/01-test-phase/01-01.plan.jsonl" | jq -S '{p,n,t,w}')
  [ "$orig_header" = "$exp_header" ]

  # Compare task IDs
  orig_t1=$(sed -n '2p' "$TEST_DIR/phases/01-test-phase/01-01.plan.jsonl" | jq -r '.id')
  exp_t1=$(sed -n '2p' "$EXPORT_DIR/phases/01-test-phase/01-01.plan.jsonl" | jq -r '.id')
  [ "$orig_t1" = "$exp_t1" ]
}

@test "exports critique.jsonl" {
  setup_test_db
  # Add critique data directly to DB
  sqlite3 "$TEST_DB" "INSERT INTO critique (id, cat, sev, q, ctx, sug, st, cf, rd, phase) VALUES ('C1','gap','major','Missing check','init func','Add validation','open',85,1,'01');"

  run bash scripts/db/export-milestone.sh --planning-dir "$EXPORT_DIR" --db "$TEST_DB"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 critique"* ]]

  [ -f "$EXPORT_DIR/phases/01-test-phase/critique.jsonl" ]
  line=$(head -1 "$EXPORT_DIR/phases/01-test-phase/critique.jsonl")
  echo "$line" | jq -e '.id == "C1"'
  echo "$line" | jq -e '.cf == 85'
}

@test "exports decisions.jsonl" {
  setup_test_db
  sqlite3 "$TEST_DB" "INSERT INTO decisions (ts, agent, task, dec, reason, phase) VALUES ('2026-02-19T10:00:00Z','architect','T1','Use WAL','concurrent access','01');"

  run bash scripts/db/export-milestone.sh --planning-dir "$EXPORT_DIR" --db "$TEST_DB"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 decisions"* ]]

  [ -f "$EXPORT_DIR/phases/01-test-phase/decisions.jsonl" ]
  line=$(head -1 "$EXPORT_DIR/phases/01-test-phase/decisions.jsonl")
  echo "$line" | jq -e '.dec == "Use WAL"'
}

@test "exports research.jsonl" {
  setup_test_db
  sqlite3 "$TEST_DB" "INSERT INTO research (q, src, finding, conf, dt, rel, phase) VALUES ('How to test?','docs','Use BATS','high','2026-02-19','relevant','01');"

  run bash scripts/db/export-milestone.sh --planning-dir "$EXPORT_DIR" --db "$TEST_DB"
  [ "$status" -eq 0 ]

  [ -f "$EXPORT_DIR/phases/01-test-phase/research.jsonl" ]
  line=$(head -1 "$EXPORT_DIR/phases/01-test-phase/research.jsonl")
  echo "$line" | jq -e '.finding == "Use BATS"'
}

@test "exports escalation.jsonl" {
  setup_test_db
  sqlite3 "$TEST_DB" "INSERT INTO escalation (id, dt, agent, reason, sb, tgt, sev, st, res, phase) VALUES ('ESC-01','2026-02-19','dev','out of scope','db layer','senior','major','open','','01');"

  run bash scripts/db/export-milestone.sh --planning-dir "$EXPORT_DIR" --db "$TEST_DB"
  [ "$status" -eq 0 ]

  [ -f "$EXPORT_DIR/phases/01-test-phase/escalation.jsonl" ]
}

@test "exports gaps.jsonl" {
  setup_test_db
  sqlite3 "$TEST_DB" "INSERT INTO gaps (id, sev, \"desc\", exp, act, st, res, phase) VALUES ('G-01','major','Missing validation','input checked','no check','open','','01');"

  run bash scripts/db/export-milestone.sh --planning-dir "$EXPORT_DIR" --db "$TEST_DB"
  [ "$status" -eq 0 ]

  [ -f "$EXPORT_DIR/phases/01-test-phase/gaps.jsonl" ]
  line=$(head -1 "$EXPORT_DIR/phases/01-test-phase/gaps.jsonl")
  echo "$line" | jq -e '.id == "G-01"'
}

@test "help flag shows usage" {
  run bash scripts/db/export-milestone.sh --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"--planning-dir"* ]]
  [[ "$output" == *"--phase"* ]]
}

@test "handles empty DB gracefully" {
  sqlite3 "$TEST_DB" < scripts/db/schema.sql
  sqlite3 "$TEST_DB" "PRAGMA journal_mode=WAL;" >/dev/null

  run bash scripts/db/export-milestone.sh --planning-dir "$EXPORT_DIR" --db "$TEST_DB"
  [ "$status" -eq 0 ]
  [[ "$output" == *"0 plans"* ]]
}
