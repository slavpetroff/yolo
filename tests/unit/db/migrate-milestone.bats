#!/usr/bin/env bats
# Tests for scripts/db/migrate-milestone.sh

setup() {
  export TEST_DIR="$BATS_TEST_TMPDIR/test-planning"
  export TEST_DB="$BATS_TEST_TMPDIR/test-yolo.db"
  mkdir -p "$TEST_DIR/phases/01-test-phase"
  mkdir -p "$TEST_DIR/phases/02-second-phase"
}

teardown() {
  rm -rf "$TEST_DIR" "$TEST_DB" "${TEST_DB}-wal" "${TEST_DB}-shm"
}

# Helper: create a minimal plan file
create_plan() {
  local dir="$1" phase="$2" num="$3"
  cat > "$dir/${phase}-${num}.plan.jsonl" <<EOF
{"p":"$phase","n":"$num","t":"Test plan $num","w":1,"mh":["must have 1"]}
{"id":"T1","a":"Do task 1","f":["file1.sh"],"v":"test -f file1.sh","done":false}
{"id":"T2","a":"Do task 2","f":["file2.sh"],"v":"test -f file2.sh","done":false}
EOF
}

# Helper: create a summary file
create_summary() {
  local dir="$1" phase="$2" num="$3"
  cat > "$dir/${phase}-${num}.summary.jsonl" <<EOF
{"p":"$phase","n":"$num","s":"complete","dt":"2026-02-19","tc":2,"tt":2,"ch":["abc1234"],"tst":"green_only"}
EOF
}

# Helper: create ROADMAP.md
create_roadmap() {
  cat > "$TEST_DIR/ROADMAP.md" <<'EOF'
# Test Roadmap

## Phase 1: Test Phase One

**Goal:** Test goal one

**Requirements:** REQ-1

**Success Criteria:**
- Criterion 1

**Dependencies:** None

---

## Phase 2: Second Phase

**Goal:** Test goal two

**Requirements:** REQ-2

**Success Criteria:**
- Criterion 2

**Dependencies:** Phase 1
EOF
}

# Helper: create research-archive.jsonl
create_archive() {
  cat > "$TEST_DIR/research-archive.jsonl" <<'EOF'
{"q":"How to test?","finding":"Use BATS for bash testing","conf":"high","phase":"01","dt":"2026-02-19","src":"docs"}
{"q":"SQLite WAL?","finding":"WAL enables concurrent reads","conf":"high","phase":"02","dt":"2026-02-19","src":"sqlite.org"}
EOF
}

@test "requires --planning-dir" {
  run bash scripts/db/migrate-milestone.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"--planning-dir is required"* ]]
}

@test "fails on missing planning dir" {
  run bash scripts/db/migrate-milestone.sh --planning-dir /nonexistent
  [ "$status" -eq 1 ]
  [[ "$output" == *"planning directory not found"* ]]
}

@test "dry-run counts without importing" {
  create_plan "$TEST_DIR/phases/01-test-phase" "01" "01"
  create_plan "$TEST_DIR/phases/01-test-phase" "01" "02"
  create_summary "$TEST_DIR/phases/01-test-phase" "01" "01"

  run bash scripts/db/migrate-milestone.sh --planning-dir "$TEST_DIR" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Dry run:"* ]]
  [[ "$output" == *"2 plans"* ]]
  [[ "$output" == *"4 tasks"* ]]
  [[ "$output" == *"1 summaries"* ]]
  # DB should not exist
  [ ! -f "$TEST_DB" ]
  [ ! -f "$TEST_DIR/yolo.db" ]
}

@test "migrates plans and tasks" {
  create_plan "$TEST_DIR/phases/01-test-phase" "01" "01"
  create_plan "$TEST_DIR/phases/02-second-phase" "02" "01"

  run bash scripts/db/migrate-milestone.sh --planning-dir "$TEST_DIR" --db "$TEST_DB"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Migrated:"* ]]
  [[ "$output" == *"2 plans"* ]]

  # Verify DB has plans
  plan_count=$(sqlite3 "$TEST_DB" "SELECT count(*) FROM plans;")
  [ "$plan_count" -ge 2 ]

  # Verify DB has tasks
  task_count=$(sqlite3 "$TEST_DB" "SELECT count(*) FROM tasks;")
  [ "$task_count" -ge 2 ]
}

@test "migrates summaries" {
  create_plan "$TEST_DIR/phases/01-test-phase" "01" "01"
  create_summary "$TEST_DIR/phases/01-test-phase" "01" "01"

  run bash scripts/db/migrate-milestone.sh --planning-dir "$TEST_DIR" --db "$TEST_DB"
  [ "$status" -eq 0 ]

  summary_count=$(sqlite3 "$TEST_DB" "SELECT count(*) FROM summaries;")
  [ "$summary_count" -eq 1 ]
}

@test "migrates ROADMAP phases" {
  create_roadmap

  run bash scripts/db/migrate-milestone.sh --planning-dir "$TEST_DIR" --db "$TEST_DB"
  [ "$status" -eq 0 ]

  phase_count=$(sqlite3 "$TEST_DB" "SELECT count(*) FROM phases;")
  [ "$phase_count" -eq 2 ]
}

@test "migrates research-archive" {
  create_archive

  run bash scripts/db/migrate-milestone.sh --planning-dir "$TEST_DIR" --db "$TEST_DB"
  [ "$status" -eq 0 ]

  archive_count=$(sqlite3 "$TEST_DB" "SELECT count(*) FROM research_archive;")
  [ "$archive_count" -eq 2 ]
}

@test "migrates verification.jsonl" {
  cat > "$TEST_DIR/phases/01-test-phase/verification.jsonl" <<'EOF'
{"tier":"standard","r":"PASS","ps":5,"fl":0,"tt":5,"dt":"2026-02-19"}
{"c":"must_have_check","r":"pass","ev":"found in output","cat":"must_have"}
EOF

  run bash scripts/db/migrate-milestone.sh --planning-dir "$TEST_DIR" --db "$TEST_DB"
  [ "$status" -eq 0 ]

  ver_count=$(sqlite3 "$TEST_DB" "SELECT count(*) FROM verification;")
  [ "$ver_count" -eq 1 ]
  check_count=$(sqlite3 "$TEST_DB" "SELECT count(*) FROM verification_checks;")
  [ "$check_count" -eq 1 ]
}

@test "migrates critique.jsonl" {
  cat > "$TEST_DIR/phases/01-test-phase/critique.jsonl" <<'EOF'
{"id":"C1","cat":"gap","sev":"major","q":"Missing error handling","ctx":"in init function","sug":"Add try-catch","st":"open","cf":80,"rd":1}
EOF

  run bash scripts/db/migrate-milestone.sh --planning-dir "$TEST_DIR" --db "$TEST_DB"
  [ "$status" -eq 0 ]

  critique_count=$(sqlite3 "$TEST_DB" "SELECT count(*) FROM critique;")
  [ "$critique_count" -eq 1 ]
}

@test "migrates decisions.jsonl" {
  cat > "$TEST_DIR/phases/01-test-phase/decisions.jsonl" <<'EOF'
{"ts":"2026-02-19T10:00:00Z","agent":"architect","task":"T1","dec":"Use WAL mode","reason":"concurrent access","phase":"01"}
EOF

  run bash scripts/db/migrate-milestone.sh --planning-dir "$TEST_DIR" --db "$TEST_DB"
  [ "$status" -eq 0 ]

  dec_count=$(sqlite3 "$TEST_DB" "SELECT count(*) FROM decisions;")
  [ "$dec_count" -eq 1 ]
}

@test "idempotent re-migration" {
  create_plan "$TEST_DIR/phases/01-test-phase" "01" "01"
  create_summary "$TEST_DIR/phases/01-test-phase" "01" "01"
  create_roadmap

  # First migration
  run bash scripts/db/migrate-milestone.sh --planning-dir "$TEST_DIR" --db "$TEST_DB"
  [ "$status" -eq 0 ]

  first_plans=$(sqlite3 "$TEST_DB" "SELECT count(*) FROM plans;")
  first_phases=$(sqlite3 "$TEST_DB" "SELECT count(*) FROM phases;")

  # Second migration (should be clean since --force recreates)
  run bash scripts/db/migrate-milestone.sh --planning-dir "$TEST_DIR" --db "$TEST_DB"
  [ "$status" -eq 0 ]

  second_plans=$(sqlite3 "$TEST_DB" "SELECT count(*) FROM plans;")
  second_phases=$(sqlite3 "$TEST_DB" "SELECT count(*) FROM phases;")

  [ "$first_plans" -eq "$second_plans" ]
  [ "$first_phases" -eq "$second_phases" ]
}

@test "help flag shows usage" {
  run bash scripts/db/migrate-milestone.sh --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"--planning-dir"* ]]
  [[ "$output" == *"--dry-run"* ]]
}

@test "handles empty phases dir" {
  # No plan files in phase dirs
  run bash scripts/db/migrate-milestone.sh --planning-dir "$TEST_DIR" --db "$TEST_DB"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Migrated:"* ]]
  [[ "$output" == *"0 plans"* ]]
}

@test "migrates multiple phases" {
  create_plan "$TEST_DIR/phases/01-test-phase" "01" "01"
  create_plan "$TEST_DIR/phases/01-test-phase" "01" "02"
  create_plan "$TEST_DIR/phases/02-second-phase" "02" "01"

  run bash scripts/db/migrate-milestone.sh --planning-dir "$TEST_DIR" --db "$TEST_DB"
  [ "$status" -eq 0 ]

  plan_count=$(sqlite3 "$TEST_DB" "SELECT count(*) FROM plans;")
  [ "$plan_count" -ge 3 ]
}

@test "dry-run does not create DB" {
  create_plan "$TEST_DIR/phases/01-test-phase" "01" "01"

  run bash scripts/db/migrate-milestone.sh --planning-dir "$TEST_DIR" --db "$TEST_DB" --dry-run
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_DB" ]
}

@test "default DB path is planning-dir/yolo.db" {
  create_plan "$TEST_DIR/phases/01-test-phase" "01" "01"

  run bash scripts/db/migrate-milestone.sh --planning-dir "$TEST_DIR"
  [ "$status" -eq 0 ]
  [ -f "$TEST_DIR/yolo.db" ]
}
