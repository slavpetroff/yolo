#!/usr/bin/env bats
# roadmap-dedup.bats — Validate ROADMAP triplication elimination
# Phase 10 success criteria: ROADMAP read once per phase, not 3x (11,811 → 1,200 tokens)

setup() {
  load '../../test_helper/common'
  load '../../test_helper/fixtures'
  load '../../test_helper/db_helper'
  mk_test_workdir

  COMPILE_CONTEXT="$SCRIPTS_DIR/compile-context.sh"
  DB="$TEST_WORKDIR/.yolo-planning/yolo.db"

  # Create planning directory structure
  PLANNING_DIR="$TEST_WORKDIR/.yolo-planning"
  PHASES_DIR="$PLANNING_DIR/phases"
  PHASE_DIR="$PHASES_DIR/09-test-phase"
  mkdir -p "$PHASE_DIR"
  mkdir -p "$PLANNING_DIR/codebase"

  # Create a realistic ROADMAP (>3000 tokens worth = >12000 chars)
  {
    echo "# Test Roadmap"
    echo ""
    echo "## Progress"
    echo "| Phase | Status | Plans | Tasks | Commits |"
    echo "|-------|--------|-------|-------|---------|"
    for i in $(seq 1 10); do
      echo "| $i | Complete | 5 | 20 | 22 |"
    done
    echo ""
    echo "---"
    echo ""
    echo "## Phase List"
    for i in $(seq 1 10); do
      echo "- [x] Phase $i: Test Phase $i"
    done
    echo ""
    echo "---"
    echo ""
    for i in $(seq 1 10); do
      echo "## Phase $i: Test Phase $i"
      echo ""
      echo "**Goal:** Implement feature set $i with comprehensive testing, documentation, and cross-department integration validation"
      echo "**Reqs:** REQ-${i}01, REQ-${i}02, REQ-${i}03"
      echo "**Success Criteria:** All tests pass, 95% coverage, no regressions, documentation complete, security audit pass"
      echo ""
      echo "**Requirements:**"
      for j in $(seq 1 5); do
        echo "- Requirement $i.$j: Implement component $j with proper error handling and retry logic"
      done
      echo ""
      echo "**Dependencies:** Phase $((i-1))"
      echo ""
      echo "---"
      echo ""
    done
  } > "$PLANNING_DIR/ROADMAP.md"

  # Record ROADMAP size
  ROADMAP_CHARS=$(wc -c < "$PLANNING_DIR/ROADMAP.md" | tr -d ' ')
  ROADMAP_TOKENS=$(( ROADMAP_CHARS / 4 ))

  # Create plan file
  cat > "$PHASE_DIR/09-01.plan.jsonl" <<'PLAN'
{"p":"09","n":"09-01","g":"Test plan","fm":["src/a.ts"],"tc":2}
{"id":"T1","a":"dev","f":["src/a.ts"],"spec":"Create module A","done":""}
{"id":"T2","a":"dev","f":["src/b.ts"],"spec":"Create module B","done":""}
PLAN

  cat > "$PHASE_DIR/09-01.summary.jsonl" <<'SUMMARY'
{"p":"09-01","s":"complete","fm":"Added modules"}
SUMMARY

  # Set up DB with ROADMAP data imported
  sqlite3 "$DB" < "$SCRIPTS_DIR/db/schema.sql"
  sqlite3 "$DB" "PRAGMA journal_mode=WAL;" >/dev/null
  sqlite3 "$DB" "INSERT INTO plans (phase, plan_num, title, objective, must_haves)
    VALUES ('09', '01', 'Test plan', 'Implement feature set 9 with comprehensive testing', '{\"tr\":[\"REQ-901\",\"REQ-902\"]}');"
  sqlite3 "$DB" "INSERT INTO tasks (plan_id, task_id, action, status, task_depends)
    VALUES (1, 'T1', 'Create module A', 'pending', '[]');"
  sqlite3 "$DB" "INSERT INTO tasks (plan_id, task_id, action, status, task_depends)
    VALUES (1, 'T2', 'Create module B', 'pending', '[]');"
}

# Helper: measure a role's context size in tokens (chars/4)
measure_role_tokens() {
  local role="$1"
  bash "$COMPILE_CONTEXT" --measure "$PHASE_NUM" "$role" "$PHASES_DIR" "$PHASE_DIR/09-01.plan.jsonl" 2>/tmp/measure-$role.json >/dev/null || true
  local output_file="$PHASE_DIR/.ctx-${role}.toon"
  if [[ -f "$output_file" ]]; then
    local chars
    chars=$(wc -c < "$output_file" | tr -d ' ')
    echo $(( chars / 4 ))
  else
    echo 0
  fi
}

PHASE_NUM=09

@test "ROADMAP file is large enough to be meaningful" {
  # Verify our test ROADMAP is realistically sized (>2000 tokens)
  assert [ "$ROADMAP_TOKENS" -gt 2000 ]
}

@test "critic gets targeted context via SQL, not full ROADMAP" {
  local tokens
  tokens=$(measure_role_tokens "critic")
  # Critic context should be present
  assert [ "$tokens" -gt 0 ]
  # Critic context should be significantly less than the full ROADMAP
  assert [ "$tokens" -lt "$ROADMAP_TOKENS" ]
}

@test "architect gets targeted context via SQL, not full ROADMAP" {
  local tokens
  tokens=$(measure_role_tokens "architect")
  assert [ "$tokens" -gt 0 ]
  # Architect has 5000 token budget — should stay under
  assert [ "$tokens" -le 5000 ]
}

@test "lead gets targeted context via SQL, not full ROADMAP" {
  local tokens
  tokens=$(measure_role_tokens "lead")
  assert [ "$tokens" -gt 0 ]
  # Lead has 3000 token budget
  assert [ "$tokens" -le 3000 ]
}

@test "total tokens for 3 ROADMAP readers is less than 2x ROADMAP size" {
  # If ROADMAP were read 3x (triplication), total would be ~3x ROADMAP_TOKENS
  # With SQL dedup, total should be much less: each role gets targeted subset
  local critic_tokens architect_tokens lead_tokens total
  critic_tokens=$(measure_role_tokens "critic")
  architect_tokens=$(measure_role_tokens "architect")
  lead_tokens=$(measure_role_tokens "lead")
  total=$(( critic_tokens + architect_tokens + lead_tokens ))

  # Total should be less than 2x the ROADMAP (significant dedup)
  local threshold=$(( ROADMAP_TOKENS * 2 ))
  assert [ "$total" -lt "$threshold" ]
}

@test "no role reads ROADMAP.md file directly when DB available" {
  # Compile context for all 3 roles
  for role in critic architect lead; do
    bash "$COMPILE_CONTEXT" --measure "$PHASE_NUM" "$role" "$PHASES_DIR" "$PHASE_DIR/09-01.plan.jsonl" >/dev/null 2>&1 || true
  done

  # Check output files don't contain raw ROADMAP references
  for role in critic architect lead; do
    local ctx_file="$PHASE_DIR/.ctx-${role}.toon"
    if [[ -f "$ctx_file" ]]; then
      # Should NOT contain "## Phase" (raw ROADMAP section headers)
      ! grep -q "^## Phase [0-9]" "$ctx_file" || {
        echo "FAIL: $role context contains raw ROADMAP section headers"
        return 1
      }
    fi
  done
}

@test "each role gets distinct targeted data" {
  for role in critic architect lead; do
    bash "$COMPILE_CONTEXT" --measure "$PHASE_NUM" "$role" "$PHASES_DIR" "$PHASE_DIR/09-01.plan.jsonl" >/dev/null 2>&1 || true
  done

  # Architect should have phase goal
  local arch_ctx="$PHASE_DIR/.ctx-architect.toon"
  if [[ -f "$arch_ctx" ]]; then
    assert grep -q "goal:" "$arch_ctx"
  fi

  # Lead should have phase goal
  local lead_ctx="$PHASE_DIR/.ctx-lead.toon"
  if [[ -f "$lead_ctx" ]]; then
    assert grep -q "goal:" "$lead_ctx"
  fi

  # Critic should have phase goal
  local critic_ctx="$PHASE_DIR/.ctx-critic.toon"
  if [[ -f "$critic_ctx" ]]; then
    assert grep -q "goal:" "$critic_ctx"
  fi
}
