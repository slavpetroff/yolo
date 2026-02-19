#!/usr/bin/env bats
# import-roadmap.bats — Unit tests for scripts/db/import-roadmap.sh
# ROADMAP.md parsing into SQLite phases table

setup() {
  load '../../test_helper/common'
  load '../../test_helper/fixtures'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/db/import-roadmap.sh"
  DB="$TEST_WORKDIR/test.db"
  # Create minimal DB with schema
  sqlite3 "$DB" <<'SQL' > /dev/null
PRAGMA journal_mode=WAL;
SQL
  # Create test ROADMAP.md with 3 phases
  ROADMAP="$TEST_WORKDIR/ROADMAP.md"
  cat > "$ROADMAP" <<'EOF'
# Test Roadmap

## Progress
| Phase | Status |
|-------|--------|
| 1 | Planned |
| 2 | Planned |
| 3 | Planned |

---

## Phase 1: Auth System

**Goal:** Implement JWT-based authentication with RS256 signing.

**Requirements:** Support login, logout, token refresh, password reset, MFA optional

**Success Criteria:**
- All auth endpoints return correct status codes
- Token refresh works within 5s window
- Password reset sends email notification

**Dependencies:** None

---

## Phase 2: Data Layer

**Goal:** Build PostgreSQL data access layer with connection pooling.

**Requirements:** Connection pooling, query builder, migrations, seeders

**Success Criteria:**
- Connection pool handles 100 concurrent connections
- Migrations run idempotently

**Dependencies:** Phase 1

---

## Phase 3: API Gateway

**Goal:** REST API gateway with rate limiting and circuit breaker.

**Requirements:** Rate limiting per endpoint, circuit breaker for downstream services, request logging

**Success Criteria:**
- Rate limiter enforces per-IP and per-user limits
- Circuit breaker trips after 5 consecutive failures

**Dependencies:** Phase 1, Phase 2
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
  run bash "$SUT" --file "$ROADMAP" --db "$TEST_WORKDIR/missing.db"
  assert_failure
  assert_output --partial "database not found"
}

@test "imports all phases from ROADMAP" {
  run bash "$SUT" --file "$ROADMAP" --db "$DB"
  assert_success
  assert_output --partial "imported 3 phases"
}

@test "creates phases table automatically" {
  run bash "$SUT" --file "$ROADMAP" --db "$DB"
  assert_success
  local count
  count=$(sqlite3 "$DB" "SELECT count(*) FROM phases;")
  [ "$count" -eq 3 ]
}

@test "extracts correct phase numbers with zero-padding" {
  bash "$SUT" --file "$ROADMAP" --db "$DB"
  local phases
  phases=$(sqlite3 "$DB" "SELECT phase_num FROM phases ORDER BY phase_num;")
  [[ "$phases" == *"01"* ]]
  [[ "$phases" == *"02"* ]]
  [[ "$phases" == *"03"* ]]
}

@test "extracts correct slugs from titles" {
  bash "$SUT" --file "$ROADMAP" --db "$DB"
  local slug
  slug=$(sqlite3 "$DB" "SELECT slug FROM phases WHERE phase_num='01';")
  [ "$slug" = "auth-system" ]
  slug=$(sqlite3 "$DB" "SELECT slug FROM phases WHERE phase_num='02';")
  [ "$slug" = "data-layer" ]
  slug=$(sqlite3 "$DB" "SELECT slug FROM phases WHERE phase_num='03';")
  [ "$slug" = "api-gateway" ]
}

@test "extracts goal text" {
  bash "$SUT" --file "$ROADMAP" --db "$DB"
  local goal
  goal=$(sqlite3 "$DB" "SELECT goal FROM phases WHERE phase_num='01';")
  [[ "$goal" == *"JWT-based authentication"* ]]
  [[ "$goal" == *"RS256"* ]]
}

@test "extracts requirements text" {
  bash "$SUT" --file "$ROADMAP" --db "$DB"
  local reqs
  reqs=$(sqlite3 "$DB" "SELECT reqs FROM phases WHERE phase_num='02';")
  [[ "$reqs" == *"Connection pooling"* ]]
  [[ "$reqs" == *"migrations"* ]]
}

@test "extracts success criteria with bullet points" {
  bash "$SUT" --file "$ROADMAP" --db "$DB"
  local sc
  sc=$(sqlite3 "$DB" "SELECT success_criteria FROM phases WHERE phase_num='01';")
  [[ "$sc" == *"auth endpoints"* ]]
  [[ "$sc" == *"Token refresh"* ]]
}

@test "extracts dependencies" {
  bash "$SUT" --file "$ROADMAP" --db "$DB"
  local deps
  deps=$(sqlite3 "$DB" "SELECT deps FROM phases WHERE phase_num='01';")
  [ "$deps" = "None" ]
  deps=$(sqlite3 "$DB" "SELECT deps FROM phases WHERE phase_num='02';")
  [[ "$deps" == *"Phase 1"* ]]
  deps=$(sqlite3 "$DB" "SELECT deps FROM phases WHERE phase_num='03';")
  [[ "$deps" == *"Phase 1"* ]]
  [[ "$deps" == *"Phase 2"* ]]
}

@test "re-import updates existing phases (ON CONFLICT DO UPDATE)" {
  bash "$SUT" --file "$ROADMAP" --db "$DB"
  local count1
  count1=$(sqlite3 "$DB" "SELECT count(*) FROM phases;")
  [ "$count1" -eq 3 ]
  # Re-import
  bash "$SUT" --file "$ROADMAP" --db "$DB"
  local count2
  count2=$(sqlite3 "$DB" "SELECT count(*) FROM phases;")
  [ "$count2" -eq 3 ]
}

@test "get-phase.sh reads imported data" {
  bash "$SUT" --file "$ROADMAP" --db "$DB"
  GET_PHASE="$SCRIPTS_DIR/db/get-phase.sh"
  run bash "$GET_PHASE" 01 --db "$DB" --goals
  assert_success
  assert_output --partial "goal: Implement JWT-based authentication"
}

@test "handles phases with double-digit numbers" {
  cat >> "$ROADMAP" <<'EOF'

---

## Phase 10: Final Delivery

**Goal:** Ship the product to production.

**Requirements:** CI/CD pipeline, monitoring, alerting

**Success Criteria:**
- All tests pass in CI
- Monitoring dashboards operational

**Dependencies:** Phase 9
EOF
  run bash "$SUT" --file "$ROADMAP" --db "$DB"
  assert_success
  assert_output --partial "imported 4 phases"
  local slug
  slug=$(sqlite3 "$DB" "SELECT slug FROM phases WHERE phase_num='10';")
  [ "$slug" = "final-delivery" ]
}
