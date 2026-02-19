#!/usr/bin/env bats
# import-requirements.bats — Unit tests for scripts/db/import-requirements.sh
# REQUIREMENTS.md parsing into SQLite requirements table

setup() {
  load '../../test_helper/common'
  load '../../test_helper/fixtures'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/db/import-requirements.sh"
  DB="$TEST_WORKDIR/test.db"
  # Create minimal DB
  sqlite3 "$DB" <<'SQL' > /dev/null
PRAGMA journal_mode=WAL;
SQL
  # Create test REQUIREMENTS.md
  REQS="$TEST_WORKDIR/REQUIREMENTS.md"
  cat > "$REQS" <<'EOF'
# Requirements

Defined: 2026-02-18

## Requirements

### REQ-01: Implement JWT authentication with RS256
**Must-have**

### REQ-02: Build data access layer with connection pooling
**Must-have**

### REQ-03: Rate limiting per endpoint
**Nice-to-have**

### REQ-04: Monitoring and alerting dashboard
**Should-have**

## Out of Scope

_(Nothing defined)_
EOF
}

@test "exits 1 with usage when no args" {
  run bash "$SUT"
  assert_failure
  assert_output --partial "Usage"
}

@test "exits 1 when --file missing" {
  run bash "$SUT" --db "$DB"
  assert_failure
  assert_output --partial "--file is required"
}

@test "exits 1 when file not found" {
  run bash "$SUT" --file "$TEST_WORKDIR/nonexistent.md" --db "$DB"
  assert_failure
  assert_output --partial "file not found"
}

@test "exits 1 when database missing" {
  run bash "$SUT" --file "$REQS" --db "$TEST_WORKDIR/missing.db"
  assert_failure
  assert_output --partial "database not found"
}

@test "imports all requirements" {
  run bash "$SUT" --file "$REQS" --db "$DB"
  assert_success
  assert_output --partial "imported 4 requirements"
}

@test "creates requirements table automatically" {
  bash "$SUT" --file "$REQS" --db "$DB"
  local count
  count=$(sqlite3 "$DB" "SELECT count(*) FROM requirements;")
  [ "$count" -eq 4 ]
}

@test "extracts correct req IDs" {
  bash "$SUT" --file "$REQS" --db "$DB"
  local ids
  ids=$(sqlite3 "$DB" "SELECT req_id FROM requirements ORDER BY req_id;")
  [[ "$ids" == *"REQ-01"* ]]
  [[ "$ids" == *"REQ-04"* ]]
}

@test "extracts description text" {
  bash "$SUT" --file "$REQS" --db "$DB"
  local desc
  desc=$(sqlite3 "$DB" "SELECT description FROM requirements WHERE req_id='REQ-01';")
  [[ "$desc" == *"JWT authentication"* ]]
  [[ "$desc" == *"RS256"* ]]
}

@test "extracts priority levels" {
  bash "$SUT" --file "$REQS" --db "$DB"
  local p1 p3 p4
  p1=$(sqlite3 "$DB" "SELECT priority FROM requirements WHERE req_id='REQ-01';")
  [ "$p1" = "must-have" ]
  p3=$(sqlite3 "$DB" "SELECT priority FROM requirements WHERE req_id='REQ-03';")
  [ "$p3" = "nice-to-have" ]
  p4=$(sqlite3 "$DB" "SELECT priority FROM requirements WHERE req_id='REQ-04';")
  [ "$p4" = "should-have" ]
}

@test "re-import updates existing requirements" {
  bash "$SUT" --file "$REQS" --db "$DB"
  local count1
  count1=$(sqlite3 "$DB" "SELECT count(*) FROM requirements;")
  [ "$count1" -eq 4 ]
  # Re-import
  bash "$SUT" --file "$REQS" --db "$DB"
  local count2
  count2=$(sqlite3 "$DB" "SELECT count(*) FROM requirements;")
  [ "$count2" -eq 4 ]
}

@test "stops parsing at Out of Scope section" {
  bash "$SUT" --file "$REQS" --db "$DB"
  local count
  count=$(sqlite3 "$DB" "SELECT count(*) FROM requirements;")
  [ "$count" -eq 4 ]
}

@test "handles single requirement file" {
  cat > "$TEST_WORKDIR/single.md" <<'EOF'
# Requirements

### REQ-01: Single requirement only
**Must-have**
EOF
  run bash "$SUT" --file "$TEST_WORKDIR/single.md" --db "$DB"
  assert_success
  assert_output --partial "imported 1 requirements"
}
