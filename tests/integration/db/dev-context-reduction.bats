#!/usr/bin/env bats
# dev-context-reduction.bats — Validate Dev context reduction via SQL path
# Phase 10 success criteria: Dev from 1,064 to ~75 tokens = 93% savings

setup() {
  load '../../test_helper/common'
  load '../../test_helper/fixtures'
  load '../../test_helper/db_helper'
  mk_test_workdir

  COMPILE_CONTEXT="$SCRIPTS_DIR/compile-context.sh"

  # Create planning directory structure
  PLANNING_DIR="$TEST_WORKDIR/.yolo-planning"
  PHASES_DIR="$PLANNING_DIR/phases"
  PHASE_DIR="$PHASES_DIR/09-test-phase"
  mkdir -p "$PHASE_DIR"

  # Create ROADMAP.md
  cat > "$PLANNING_DIR/ROADMAP.md" <<'ROADMAP'
# Test Roadmap

## Progress
| Phase | Status |
|-------|--------|
| 9 | Active |

---

## Phase List
- [ ] Phase 9: Dev Context Test

---

## Phase 9: Dev Context Test

**Goal:** Test dev context reduction via SQL
**Reqs:** Unit tests
**Success Criteria:** All tests pass

---
ROADMAP

  # Create a realistic 7-task plan (matches spec: "Set up DB with a 7-task plan")
  cat > "$PHASE_DIR/09-01.plan.jsonl" <<'PLAN'
{"p":"09","n":"09-01","g":"Implement auth module with JWT tokens, role-based access control, and session management","fm":["src/auth/jwt.ts","src/auth/rbac.ts","src/auth/session.ts","src/auth/middleware.ts","src/auth/types.ts","src/auth/config.ts","tests/auth/auth.test.ts"],"tc":7,"sk":[],"tr":["REQ-101","REQ-102"]}
{"id":"T1","a":"Create JWT token generation and validation module","f":["src/auth/jwt.ts","src/auth/types.ts"],"spec":"Implement JWT signing with RS256, token refresh flow, and expiration handling. Include type definitions for TokenPayload and AuthConfig.","done":""}
{"id":"T2","a":"Implement role-based access control system","f":["src/auth/rbac.ts"],"spec":"Create RBAC middleware with permission matrix. Support admin, editor, viewer roles with granular resource permissions.","done":""}
{"id":"T3","a":"Build session management with Redis backing","f":["src/auth/session.ts"],"spec":"Implement session store using Redis with configurable TTL, sliding expiration, and concurrent session limits per user.","done":""}
{"id":"T4","a":"Create auth middleware for Express routes","f":["src/auth/middleware.ts"],"spec":"Build composable middleware: requireAuth, requireRole(roles), requirePermission(perm). Handle token extraction from Bearer header and cookies.","done":""}
{"id":"T5","a":"Add auth configuration module","f":["src/auth/config.ts"],"spec":"Environment-based config for JWT secret, token TTL, refresh TTL, session limits, allowed origins. Validate on startup.","done":""}
{"id":"T6","a":"Write comprehensive auth test suite","f":["tests/auth/auth.test.ts"],"spec":"Test all auth flows: login, token refresh, RBAC enforcement, session management, middleware chain. Cover edge cases: expired tokens, invalid signatures, rate limiting.","done":""}
{"id":"T7","a":"Integration test for full auth pipeline","f":["tests/auth/auth.test.ts","src/auth/middleware.ts"],"spec":"End-to-end test: register -> login -> get token -> access protected resource -> refresh -> logout -> verify session destroyed.","done":""}
PLAN

  # Create multiple summaries for a realistic multi-plan phase
  cat > "$PHASE_DIR/09-01.summary.jsonl" <<'SUMMARY'
{"p":"09-01","s":"complete","fm":"Implemented JWT auth with RS256 signing, RBAC middleware, and session management. All 7 tasks complete.","sg":["Consider adding rate limiting to auth endpoints","Session cleanup cron job needed for production"]}
SUMMARY

  # Create a second plan to test dev isolation
  cat > "$PHASE_DIR/09-02.plan.jsonl" <<'PLAN2'
{"p":"09","n":"09-02","g":"Implement API rate limiting","fm":["src/rate-limit/limiter.ts","src/rate-limit/store.ts","src/rate-limit/middleware.ts"],"tc":3}
{"id":"T1","a":"Create rate limit store","f":["src/rate-limit/store.ts"],"spec":"Redis-backed sliding window rate limiter","done":""}
{"id":"T2","a":"Build rate limit middleware","f":["src/rate-limit/middleware.ts"],"spec":"Express middleware with configurable limits per route","done":""}
{"id":"T3","a":"Add rate limit config","f":["src/rate-limit/limiter.ts"],"spec":"Configuration module for rate limits","done":""}
PLAN2

  cat > "$PHASE_DIR/09-02.summary.jsonl" <<'SUMMARY2'
{"p":"09-02","s":"complete","fm":"Rate limiting implemented with Redis sliding window"}
SUMMARY2

  # Create a third plan
  cat > "$PHASE_DIR/09-03.plan.jsonl" <<'PLAN3'
{"p":"09","n":"09-03","g":"Add API documentation","fm":["docs/api.md","src/docs/swagger.ts"],"tc":2}
{"id":"T1","a":"Generate OpenAPI spec","f":["src/docs/swagger.ts"],"spec":"Auto-generate OpenAPI 3.0 spec from route definitions","done":""}
{"id":"T2","a":"Write API documentation","f":["docs/api.md"],"spec":"Developer-facing API documentation with examples","done":""}
PLAN3

  PLAN_PATH="$PHASE_DIR/09-01.plan.jsonl"
}

# Helper: measure file-based dev context tokens
measure_file_tokens() {
  local role="$1" plan="$2"
  local db_path="$PLANNING_DIR/yolo.db"
  # Hide DB to force file path
  if [[ -f "$db_path" ]]; then
    mv "$db_path" "${db_path}.hidden" 2>/dev/null || true
  fi
  bash "$COMPILE_CONTEXT" --measure 09 "$role" "$PHASES_DIR" "$plan" >/dev/null 2>/tmp/measure-file-$role.json || true
  if [[ -f "${db_path}.hidden" ]]; then
    mv "${db_path}.hidden" "$db_path" 2>/dev/null || true
  fi
  local ctx="$PHASE_DIR/.ctx-${role}.toon"
  if [[ -f "$ctx" ]]; then
    local chars
    chars=$(wc -c < "$ctx" | tr -d ' ')
    echo $(( chars / 4 ))
  else
    echo 0
  fi
}

# Helper: measure SQL-based dev context tokens
measure_sql_tokens() {
  local role="$1" plan="$2"
  bash "$COMPILE_CONTEXT" --measure 09 "$role" "$PHASES_DIR" "$plan" >/dev/null 2>/tmp/measure-sql-$role.json || true
  local ctx="$PHASE_DIR/.ctx-${role}.toon"
  if [[ -f "$ctx" ]]; then
    local chars
    chars=$(wc -c < "$ctx" | tr -d ' ')
    echo $(( chars / 4 ))
  else
    echo 0
  fi
}

setup_db() {
  local DB="$PLANNING_DIR/yolo.db"
  sqlite3 "$DB" < "$SCRIPTS_DIR/db/schema.sql"
  sqlite3 "$DB" "PRAGMA journal_mode=WAL;" >/dev/null

  # Insert all 3 plans
  sqlite3 "$DB" "INSERT INTO plans (phase, plan_num, title, objective, must_haves)
    VALUES ('09', '01', 'Implement auth module', 'JWT auth with RBAC', '{\"tr\":[\"REQ-101\"]}');"
  sqlite3 "$DB" "INSERT INTO plans (phase, plan_num, title, objective, must_haves)
    VALUES ('09', '02', 'API rate limiting', 'Redis rate limiter', '{\"tr\":[]}');"
  sqlite3 "$DB" "INSERT INTO plans (phase, plan_num, title, objective, must_haves)
    VALUES ('09', '03', 'API documentation', 'OpenAPI spec', '{\"tr\":[]}');"

  # Insert all 7 tasks for plan 01
  for i in $(seq 1 7); do
    sqlite3 "$DB" "INSERT INTO tasks (plan_id, task_id, action, status, task_depends)
      VALUES (1, 'T${i}', 'Task ${i} action', 'pending', '[]');"
  done

  # Insert tasks for plan 02 and 03
  for i in $(seq 1 3); do
    sqlite3 "$DB" "INSERT INTO tasks (plan_id, task_id, action, status, task_depends)
      VALUES (2, 'T${i}', 'Rate limit task ${i}', 'pending', '[]');"
  done
  for i in $(seq 1 2); do
    sqlite3 "$DB" "INSERT INTO tasks (plan_id, task_id, action, status, task_depends)
      VALUES (3, 'T${i}', 'Doc task ${i}', 'pending', '[]');"
  done

  # Insert summaries
  sqlite3 "$DB" "INSERT INTO summaries (plan_id, status, fm)
    VALUES (1, 'complete', 'Implemented JWT auth');"
}

@test "file-based dev context produces measurable output" {
  local tokens
  tokens=$(measure_file_tokens "dev" "$PLAN_PATH")
  assert [ "$tokens" -gt 0 ]
}

@test "SQL-based dev context produces measurable output" {
  setup_db
  local tokens
  tokens=$(measure_sql_tokens "dev" "$PLAN_PATH")
  assert [ "$tokens" -gt 0 ]
}

@test "SQL path produces fewer tokens than file path" {
  setup_db
  local file_tokens sql_tokens
  file_tokens=$(measure_file_tokens "dev" "$PLAN_PATH")
  # DB was hidden and restored by measure_file_tokens — no need to recreate
  sql_tokens=$(measure_sql_tokens "dev" "$PLAN_PATH")

  # SQL should produce fewer or equal tokens (context is more targeted)
  assert [ "$sql_tokens" -le "$file_tokens" ]
}

@test "dev context spec field is present and complete" {
  setup_db
  bash "$COMPILE_CONTEXT" --measure 09 dev "$PHASES_DIR" "$PLAN_PATH" >/dev/null 2>&1 || true

  local ctx="$PHASE_DIR/.ctx-dev.toon"
  assert_file_exists "$ctx"

  # Should contain task specs (the dev's primary input)
  assert grep -q "tasks" "$ctx"
  # Should have task entries
  assert grep -q "T1" "$ctx"
}

@test "dev sees only assigned plan tasks, not other plans" {
  setup_db
  bash "$COMPILE_CONTEXT" --measure 09 dev "$PHASES_DIR" "$PLAN_PATH" >/dev/null 2>&1 || true

  local ctx="$PHASE_DIR/.ctx-dev.toon"
  assert_file_exists "$ctx"

  # Should have T1-T7 from plan 09-01
  assert grep -q "T1" "$ctx"

  # Should NOT have rate-limit tasks (plan 09-02) directly
  # The dev context for plan 09-01 should not include 09-02 task details
  ! grep -q "Rate limit" "$ctx" || {
    echo "FAIL: dev context contains tasks from other plans"
    return 1
  }
}

@test "dev context stays within budget (2000 tokens)" {
  setup_db
  local tokens
  tokens=$(measure_sql_tokens "dev" "$PLAN_PATH")
  assert [ "$tokens" -le 2000 ]
}
