#!/usr/bin/env bats
# architect-budget.bats — Validate Architect budget overflow fix
# Phase 10 success criteria: Architect receives complete context within 5000 token budget

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
  mkdir -p "$PLANNING_DIR/codebase"

  # Create a large ROADMAP (~3937 tokens = ~15748 chars)
  {
    echo "# Large Roadmap"
    echo ""
    echo "## Progress"
    echo "| Phase | Status | Plans | Tasks | Commits |"
    echo "|-------|--------|-------|-------|---------|"
    for i in $(seq 1 15); do
      echo "| $i | Complete | 7 | 35 | 40 |"
    done
    echo ""
    echo "---"
    echo ""
    echo "## Phase List"
    for i in $(seq 1 15); do
      echo "- [x] Phase $i: Large Feature Phase $i"
    done
    echo ""
    echo "---"
    echo ""
    for i in $(seq 1 15); do
      echo "## Phase $i: Large Feature Phase $i"
      echo ""
      echo "**Goal:** Implement comprehensive feature set $i including backend API, frontend components, database migrations, caching layer, and cross-department integration with full test coverage and documentation"
      echo ""
      echo "**Requirements:**"
      for j in $(seq 1 8); do
        echo "- REQ-${i}${j}: Build component $j with proper error handling, retry logic, circuit breakers, health checks, and monitoring integration"
      done
      echo ""
      echo "**Success Criteria:**"
      echo "- All unit tests pass with >95% coverage"
      echo "- Integration tests cover all API endpoints"
      echo "- Performance benchmarks meet SLA targets"
      echo "- Security audit passes with no critical findings"
      echo "- Documentation complete for all public APIs"
      echo ""
      echo "**Dependencies:** Phase $((i-1))"
      echo ""
      echo "---"
      echo ""
    done
  } > "$PLANNING_DIR/ROADMAP.md"

  # Create codebase mapping files (500 tokens = ~2000 chars)
  for base in INDEX ARCHITECTURE PATTERNS CONCERNS; do
    {
      echo "# $base Summary"
      echo ""
      for i in $(seq 1 10); do
        echo "## Section $i"
        echo "This section covers the $base aspect $i of the codebase with detailed analysis of patterns, conventions, and best practices used throughout the project."
        echo ""
      done
    } > "$PLANNING_DIR/codebase/${base}.md"
  done

  # Create research.jsonl (2000 tokens = ~8000 chars)
  for i in $(seq 1 20); do
    echo "{\"q\":\"Research question $i about implementation patterns and best practices\",\"finding\":\"Finding $i: Detailed analysis of the approach with recommendations for implementation including error handling, performance considerations, and security implications. This finding covers multiple aspects of the system design.\",\"ra\":\"scout\",\"rt\":\"blocking\",\"phase\":\"09\"}" >> "$PHASE_DIR/research.jsonl"
  done

  # Create critique.jsonl (1000 tokens = ~4000 chars)
  for i in $(seq 1 10); do
    echo "{\"id\":\"C$i\",\"cat\":\"risk\",\"sev\":\"major\",\"q\":\"Critique finding $i regarding architectural decisions and their impact on maintainability and scalability of the system\",\"phase\":\"09\"}" >> "$PHASE_DIR/critique.jsonl"
  done

  # Create plan file
  cat > "$PHASE_DIR/09-01.plan.jsonl" <<'PLAN'
{"p":"09","n":"09-01","g":"Large feature plan","fm":["src/a.ts","src/b.ts","src/c.ts"],"tc":3}
{"id":"T1","a":"dev","f":["src/a.ts"],"spec":"Create module A","done":""}
{"id":"T2","a":"dev","f":["src/b.ts"],"spec":"Create module B","done":""}
{"id":"T3","a":"dev","f":["src/c.ts"],"spec":"Create module C","done":""}
PLAN

  PLAN_PATH="$PHASE_DIR/09-01.plan.jsonl"
}

# Helper: measure architect context
measure_architect() {
  local use_db="$1"
  local db_path="$PLANNING_DIR/yolo.db"

  if [[ "$use_db" = "false" ]] && [[ -f "$db_path" ]]; then
    mv "$db_path" "${db_path}.hidden" 2>/dev/null || true
  fi

  bash "$COMPILE_CONTEXT" --measure 09 architect "$PHASES_DIR" "$PLAN_PATH" >/dev/null 2>/tmp/measure-arch.json || true

  if [[ "$use_db" = "false" ]] && [[ -f "${db_path}.hidden" ]]; then
    mv "${db_path}.hidden" "$db_path" 2>/dev/null || true
  fi

  local ctx="$PHASE_DIR/.ctx-architect.toon"
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

  # Insert phase data
  sqlite3 "$DB" "INSERT INTO plans (phase, plan_num, title, objective, must_haves)
    VALUES ('09', '01', 'Large feature plan', 'Implement comprehensive feature set 9', '{\"tr\":[\"REQ-91\",\"REQ-92\"]}');"

  # Insert research findings
  for i in $(seq 1 20); do
    sqlite3 "$DB" "INSERT INTO research (q, finding, ra, rt, phase)
      VALUES ('Research question $i', 'Finding $i: Detailed analysis', 'scout', 'blocking', '09');"
  done

  # Insert critique
  for i in $(seq 1 10); do
    sqlite3 "$DB" "INSERT INTO critique (id, cat, sev, q, phase)
      VALUES ('C$i', 'risk', 'major', 'Critique finding $i', '09');"
  done
}

@test "file-based architect context is produced" {
  local tokens
  tokens=$(measure_architect "false")
  assert [ "$tokens" -gt 0 ]
}

@test "file-based architect context triggers budget enforcement" {
  # With large ROADMAP + codebase + research, file-based should be large
  local tokens
  tokens=$(measure_architect "false")
  # Architect budget is 5000 tokens — enforce_budget should trim to fit
  assert [ "$tokens" -le 5000 ]
}

@test "SQL-based architect context stays within budget" {
  setup_db
  local tokens
  tokens=$(measure_architect "true")
  assert [ "$tokens" -gt 0 ]
  assert [ "$tokens" -le 5000 ]
}

@test "SQL architect context includes phase goal" {
  setup_db
  bash "$COMPILE_CONTEXT" --measure 09 architect "$PHASES_DIR" "$PLAN_PATH" >/dev/null 2>&1 || true

  local ctx="$PHASE_DIR/.ctx-architect.toon"
  assert_file_exists "$ctx"
  assert grep -q "goal:" "$ctx"
}

@test "SQL architect context includes research" {
  setup_db
  bash "$COMPILE_CONTEXT" --measure 09 architect "$PHASES_DIR" "$PLAN_PATH" >/dev/null 2>&1 || true

  local ctx="$PHASE_DIR/.ctx-architect.toon"
  assert_file_exists "$ctx"
  # Research should be present (either from DB or file fallback)
  assert grep -q "research" "$ctx"
}

@test "SQL architect context includes requirements" {
  setup_db
  bash "$COMPILE_CONTEXT" --measure 09 architect "$PHASES_DIR" "$PLAN_PATH" >/dev/null 2>&1 || true

  local ctx="$PHASE_DIR/.ctx-architect.toon"
  assert_file_exists "$ctx"
  # Requirements section should be present
  assert grep -q "reqs:" "$ctx"
}

@test "SQL path avoids lossy truncation vs file path" {
  setup_db
  # SQL path: targeted queries
  bash "$COMPILE_CONTEXT" --measure 09 architect "$PHASES_DIR" "$PLAN_PATH" >/dev/null 2>&1 || true
  local sql_ctx="$PHASE_DIR/.ctx-architect.toon"

  # Count key sections present in SQL output
  local sql_sections=0
  grep -q "goal:" "$sql_ctx" 2>/dev/null && ((sql_sections++)) || true
  grep -q "research" "$sql_ctx" 2>/dev/null && ((sql_sections++)) || true
  grep -q "reqs:" "$sql_ctx" 2>/dev/null && ((sql_sections++)) || true
  grep -q "success_criteria:" "$sql_ctx" 2>/dev/null && ((sql_sections++)) || true

  # SQL should have at least 3 of the 4 key sections (goal, research, reqs, success)
  assert [ "$sql_sections" -ge 3 ]
}
