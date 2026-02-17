#!/usr/bin/env bats
# compile-context.bats — Unit tests for scripts/compile-context.sh
# TOON context compiler for 26 agent roles (11 backend + 7 FE + 7 UX + owner).
# Usage: compile-context.sh <phase-number> <role> [phases-dir] [plan-path]

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  load '../test_helper/mock_stdin'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/compile-context.sh"

  # Set up .yolo-planning with phase dir, ROADMAP, conventions
  mkdir -p "$TEST_WORKDIR/.yolo-planning/phases/01-setup"
  mkdir -p "$TEST_WORKDIR/.yolo-planning/codebase"

  # Minimal ROADMAP.md
  cat > "$TEST_WORKDIR/.yolo-planning/ROADMAP.md" <<'EOF'
# Roadmap

## Phase 1: Setup
**Goal:** Initialize the project structure
**Reqs:** REQ-01, REQ-02
**Success Criteria:** All files created

## Phase 2: Build
**Goal:** Build the core
EOF

  # Conventions file
  cat > "$TEST_WORKDIR/.yolo-planning/conventions.json" <<'EOF'
{"conventions":[{"category":"naming","rule":"Use kebab-case for files"},{"category":"style","rule":"One commit per task"}]}
EOF

  PHASES_DIR="$TEST_WORKDIR/.yolo-planning/phases"
}

# Helper: run compile-context from test workdir
run_cc() {
  local phase="$1" role="$2"
  shift 2
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT' '$phase' '$role' '$PHASES_DIR' $*"
}

# --- Each role produces output ---

@test "architect role produces .ctx-architect.toon" {
  run_cc 01 architect
  assert_success
  assert_output --partial ".ctx-architect.toon"
  assert [ -f "$PHASES_DIR/01-setup/.ctx-architect.toon" ]
}

@test "lead role produces .ctx-lead.toon" {
  run_cc 01 lead
  assert_success
  assert_output --partial ".ctx-lead.toon"
  assert [ -f "$PHASES_DIR/01-setup/.ctx-lead.toon" ]
}

@test "senior role produces .ctx-senior.toon" {
  run_cc 01 senior
  assert_success
  assert_output --partial ".ctx-senior.toon"
  assert [ -f "$PHASES_DIR/01-setup/.ctx-senior.toon" ]
}

@test "dev role produces .ctx-dev.toon" {
  run_cc 01 dev
  assert_success
  assert_output --partial ".ctx-dev.toon"
  assert [ -f "$PHASES_DIR/01-setup/.ctx-dev.toon" ]
}

@test "qa role produces .ctx-qa.toon" {
  run_cc 01 qa
  assert_success
  assert_output --partial ".ctx-qa.toon"
  assert [ -f "$PHASES_DIR/01-setup/.ctx-qa.toon" ]
}

@test "qa-code role produces .ctx-qa-code.toon" {
  run_cc 01 qa-code
  assert_success
  assert_output --partial ".ctx-qa-code.toon"
  assert [ -f "$PHASES_DIR/01-setup/.ctx-qa-code.toon" ]
}

@test "security role produces .ctx-security.toon" {
  run_cc 01 security
  assert_success
  assert_output --partial ".ctx-security.toon"
  assert [ -f "$PHASES_DIR/01-setup/.ctx-security.toon" ]
}

@test "debugger role produces .ctx-debugger.toon" {
  # debugger calls git log, so initialize a repo
  cd "$TEST_WORKDIR" && git init -q && git config user.email "t@t.com" && git config user.name "T"
  echo "x" > "$TEST_WORKDIR/x.txt" && cd "$TEST_WORKDIR" && git add x.txt && git commit -q -m "init"
  run_cc 01 debugger
  assert_success
  assert_output --partial ".ctx-debugger.toon"
  assert [ -f "$PHASES_DIR/01-setup/.ctx-debugger.toon" ]
}

# --- New roles: critic and tester ---

@test "critic role produces .ctx-critic.toon" {
  run_cc 01 critic
  assert_success
  assert_output --partial ".ctx-critic.toon"
  assert [ -f "$PHASES_DIR/01-setup/.ctx-critic.toon" ]
}

@test "tester role produces .ctx-tester.toon" {
  local plan="$PHASES_DIR/01-setup/01-01.plan.jsonl"
  cp "$FIXTURES_DIR/plans/valid-plan.jsonl" "$plan"
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT' 01 tester '$PHASES_DIR' '$plan'"
  assert_success
  assert_output --partial ".ctx-tester.toon"
  assert [ -f "$PHASES_DIR/01-setup/.ctx-tester.toon" ]
}

@test "critic role includes requirements and research" {
  echo '{"q":"Auth best practices?","finding":"Use OAuth2"}' > "$PHASES_DIR/01-setup/research.jsonl"
  run_cc 01 critic
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-critic.toon"
  run cat "$ctx"
  assert_output --partial "research:"
  assert_output --partial "OAuth2"
}

@test "tester role includes task lines with test specs" {
  local plan="$PHASES_DIR/01-setup/01-01.plan.jsonl"
  cp "$FIXTURES_DIR/plans/valid-plan.jsonl" "$plan"
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT' 01 tester '$PHASES_DIR' '$plan'"
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-tester.toon"
  run cat "$ctx"
  assert_output --partial "tasks["
}

# --- Codebase mapping references ---

@test "architect role references codebase .md files" {
  cp "$FIXTURES_DIR/codebase/INDEX.md" "$TEST_WORKDIR/.yolo-planning/codebase/INDEX.md"
  cp "$FIXTURES_DIR/codebase/PATTERNS.md" "$TEST_WORKDIR/.yolo-planning/codebase/PATTERNS.md"
  run_cc 01 architect
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-architect.toon"
  run cat "$ctx"
  assert_output --partial "INDEX.md"
  assert_output --partial "PATTERNS.md"
}

@test "critic role references codebase .md files" {
  cp "$FIXTURES_DIR/codebase/INDEX.md" "$TEST_WORKDIR/.yolo-planning/codebase/INDEX.md"
  run_cc 01 critic
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-critic.toon"
  run cat "$ctx"
  assert_output --partial "INDEX.md"
}

@test "senior role references PATTERNS.md" {
  cp "$FIXTURES_DIR/codebase/PATTERNS.md" "$TEST_WORKDIR/.yolo-planning/codebase/PATTERNS.md"
  run_cc 01 senior
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-senior.toon"
  run cat "$ctx"
  assert_output --partial "PATTERNS.md"
}

# --- Invalid role exits 1 ---

@test "exits 1 for invalid role" {
  run_cc 01 invalid-role
  assert_failure
  assert_output --partial "Unknown role"
}

# --- Department roles: Frontend ---

@test "fe-architect role produces .ctx-fe-architect.toon" {
  run_cc 01 fe-architect
  assert_success
  assert_output --partial ".ctx-fe-architect.toon"
  assert [ -f "$PHASES_DIR/01-setup/.ctx-fe-architect.toon" ]
}

@test "fe-lead role produces .ctx-fe-lead.toon" {
  run_cc 01 fe-lead
  assert_success
  assert_output --partial ".ctx-fe-lead.toon"
  assert [ -f "$PHASES_DIR/01-setup/.ctx-fe-lead.toon" ]
}

@test "fe-senior role produces .ctx-fe-senior.toon" {
  run_cc 01 fe-senior
  assert_success
  assert_output --partial ".ctx-fe-senior.toon"
  assert [ -f "$PHASES_DIR/01-setup/.ctx-fe-senior.toon" ]
}

@test "fe-dev role produces .ctx-fe-dev.toon" {
  run_cc 01 fe-dev
  assert_success
  assert_output --partial ".ctx-fe-dev.toon"
  assert [ -f "$PHASES_DIR/01-setup/.ctx-fe-dev.toon" ]
}

@test "fe-tester role produces .ctx-fe-tester.toon" {
  local plan="$PHASES_DIR/01-setup/01-01.plan.jsonl"
  cp "$FIXTURES_DIR/plans/valid-plan.jsonl" "$plan"
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT' 01 fe-tester '$PHASES_DIR' '$plan'"
  assert_success
  assert_output --partial ".ctx-fe-tester.toon"
  assert [ -f "$PHASES_DIR/01-setup/.ctx-fe-tester.toon" ]
}

@test "fe-qa role produces .ctx-fe-qa.toon" {
  run_cc 01 fe-qa
  assert_success
  assert_output --partial ".ctx-fe-qa.toon"
  assert [ -f "$PHASES_DIR/01-setup/.ctx-fe-qa.toon" ]
}

@test "fe-qa-code role produces .ctx-fe-qa-code.toon" {
  run_cc 01 fe-qa-code
  assert_success
  assert_output --partial ".ctx-fe-qa-code.toon"
  assert [ -f "$PHASES_DIR/01-setup/.ctx-fe-qa-code.toon" ]
}

# --- Department roles: UI/UX ---

@test "ux-architect role produces .ctx-ux-architect.toon" {
  run_cc 01 ux-architect
  assert_success
  assert_output --partial ".ctx-ux-architect.toon"
  assert [ -f "$PHASES_DIR/01-setup/.ctx-ux-architect.toon" ]
}

@test "ux-lead role produces .ctx-ux-lead.toon" {
  run_cc 01 ux-lead
  assert_success
  assert_output --partial ".ctx-ux-lead.toon"
  assert [ -f "$PHASES_DIR/01-setup/.ctx-ux-lead.toon" ]
}

@test "ux-dev role produces .ctx-ux-dev.toon" {
  run_cc 01 ux-dev
  assert_success
  assert_output --partial ".ctx-ux-dev.toon"
  assert [ -f "$PHASES_DIR/01-setup/.ctx-ux-dev.toon" ]
}

@test "ux-qa role produces .ctx-ux-qa.toon" {
  run_cc 01 ux-qa
  assert_success
  assert_output --partial ".ctx-ux-qa.toon"
  assert [ -f "$PHASES_DIR/01-setup/.ctx-ux-qa.toon" ]
}

@test "ux-qa-code role produces .ctx-ux-qa-code.toon" {
  run_cc 01 ux-qa-code
  assert_success
  assert_output --partial ".ctx-ux-qa-code.toon"
  assert [ -f "$PHASES_DIR/01-setup/.ctx-ux-qa-code.toon" ]
}

# --- Department roles: Shared ---

@test "owner role produces .ctx-owner.toon" {
  run_cc 01 owner
  assert_success
  assert_output --partial ".ctx-owner.toon"
  assert [ -f "$PHASES_DIR/01-setup/.ctx-owner.toon" ]
}

@test "scout role produces .ctx-scout.toon" {
  run_cc 01 scout
  assert_success
  assert_output --partial ".ctx-scout.toon"
  assert [ -f "$PHASES_DIR/01-setup/.ctx-scout.toon" ]
}

# --- Department tag in context output ---

@test "fe-architect context includes department: fe tag" {
  run_cc 01 fe-architect
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-fe-architect.toon"
  run cat "$ctx"
  assert_output --partial "department: fe"
}

@test "ux-lead context includes department: ux tag" {
  run_cc 01 ux-lead
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-ux-lead.toon"
  run cat "$ctx"
  assert_output --partial "department: ux"
}

@test "backend architect context has no department tag" {
  run_cc 01 architect
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-architect.toon"
  run grep "department:" "$ctx"
  assert_failure
}

@test "owner context includes department: shared tag" {
  run_cc 01 owner
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-owner.toon"
  run cat "$ctx"
  assert_output --partial "department: shared"
}

# --- FE-specific context inclusion ---

@test "fe-architect includes design_handoff when available" {
  echo '{"type":"design_handoff","status":"complete"}' > "$PHASES_DIR/01-setup/design-handoff.jsonl"
  run_cc 01 fe-architect
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-fe-architect.toon"
  run cat "$ctx"
  assert_output --partial "design_handoff:"
}

@test "fe-lead includes api_contracts when available" {
  echo '{"type":"api_contract","status":"proposed"}' > "$PHASES_DIR/01-setup/api-contracts.jsonl"
  run_cc 01 fe-lead
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-fe-lead.toon"
  run cat "$ctx"
  assert_output --partial "api_contracts:"
}

@test "fe-dev includes design_tokens when available" {
  echo '{"cat":"color","name":"primary","val":"#0066cc"}' > "$PHASES_DIR/01-setup/design-tokens.jsonl"
  run_cc 01 fe-dev
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-fe-dev.toon"
  run cat "$ctx"
  assert_output --partial "design_tokens:"
}

@test "fe-senior includes design_tokens and component_specs when available" {
  echo '{"cat":"color","name":"primary","val":"#0066cc"}' > "$PHASES_DIR/01-setup/design-tokens.jsonl"
  echo '{"name":"Button","desc":"Primary action"}' > "$PHASES_DIR/01-setup/component-specs.jsonl"
  run_cc 01 fe-senior
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-fe-senior.toon"
  run cat "$ctx"
  assert_output --partial "design_tokens:"
  assert_output --partial "component_specs:"
}

# --- Owner role content ---

@test "owner role includes departments section" {
  run_cc 01 owner
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-owner.toon"
  run cat "$ctx"
  assert_output --partial "departments:"
}

# --- Missing phase dir exits 1 ---

@test "exits 1 when phase directory not found" {
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT' 99 architect '$PHASES_DIR'"
  assert_failure
  assert_output --partial "Phase 99 directory not found"
}

# --- Includes conventions ---

@test "senior role includes conventions in output" {
  run_cc 01 senior
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-senior.toon"
  run cat "$ctx"
  assert_output --partial "conventions"
  assert_output --partial "naming"
}

# --- Includes research from research.jsonl ---

@test "architect role includes research findings" {
  echo '{"q":"How to auth?","finding":"Use JWT tokens"}' > "$PHASES_DIR/01-setup/research.jsonl"
  run_cc 01 architect
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-architect.toon"
  run cat "$ctx"
  assert_output --partial "research:"
  assert_output --partial "JWT tokens"
}

# --- Includes decisions from decisions.jsonl ---

@test "lead role includes decisions" {
  echo '{"agent":"architect","dec":"Use REST API","reason":"simpler"}' > "$PHASES_DIR/01-setup/decisions.jsonl"
  run_cc 01 lead
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-lead.toon"
  run cat "$ctx"
  assert_output --partial "decisions:"
  assert_output --partial "REST API"
}

# --- Dev role includes task lines ---

@test "dev role includes task lines from plan" {
  local plan="$PHASES_DIR/01-setup/01-01.plan.jsonl"
  cp "$FIXTURES_DIR/plans/valid-plan.jsonl" "$plan"
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT' 01 dev '$PHASES_DIR' '$plan'"
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-dev.toon"
  run cat "$ctx"
  assert_output --partial "tasks["
}

# --- QA role includes success criteria ---

@test "qa role includes success criteria" {
  run_cc 01 qa
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-qa.toon"
  run cat "$ctx"
  assert_output --partial "success_criteria:"
  assert_output --partial "All files created"
}

# --- QA-code role includes files list ---

@test "qa-code role includes files_to_check from summaries" {
  cp "$FIXTURES_DIR/summaries/valid-summary.jsonl" "$PHASES_DIR/01-setup/01-01.summary.jsonl"
  run_cc 01 qa-code
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-qa-code.toon"
  run cat "$ctx"
  assert_output --partial "files_to_check:"
  assert_output --partial "src/foo.ts"
}

# --- Department-specific architecture file resolution ---

@test "fe-senior uses fe-architecture.toon when available" {
  echo "goal: Build FE components" > "$PHASES_DIR/01-setup/fe-architecture.toon"
  echo "tech_decisions: React, TypeScript" >> "$PHASES_DIR/01-setup/fe-architecture.toon"
  run_cc 01 fe-senior
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-fe-senior.toon"
  run cat "$ctx"
  assert_output --partial "Build FE components"
  assert_output --partial "React, TypeScript"
}

@test "ux-lead uses ux-architecture.toon when available" {
  echo "goal: Design UI system" > "$PHASES_DIR/01-setup/ux-architecture.toon"
  echo "tech_decisions: Figma tokens, 8px grid" >> "$PHASES_DIR/01-setup/ux-architecture.toon"
  run_cc 01 ux-lead
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-ux-lead.toon"
  run cat "$ctx"
  assert_output --partial "Design UI system"
  assert_output --partial "Figma tokens"
}

@test "backend lead uses architecture.toon (not fe- or ux- prefixed)" {
  echo "goal: Build backend API" > "$PHASES_DIR/01-setup/architecture.toon"
  echo "tech_decisions: Node.js, Express" >> "$PHASES_DIR/01-setup/architecture.toon"
  run_cc 01 lead
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-lead.toon"
  run cat "$ctx"
  assert_output --partial "Build backend API"
  assert_output --partial "Express"
}

# --- Scout role with critique findings ---

@test "scout case includes research directives from critique.jsonl" {
  printf '{"id":"C-01","sev":"critical","q":"Auth token expiry not validated"}\n' > "$PHASES_DIR/01-setup/critique.jsonl"
  printf '{"id":"C-02","sev":"major","q":"Rate limiting missing"}\n' >> "$PHASES_DIR/01-setup/critique.jsonl"
  printf '{"id":"C-03","sev":"minor","q":"Typo in comment"}\n' >> "$PHASES_DIR/01-setup/critique.jsonl"
  run_cc 01 scout
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-scout.toon"
  run cat "$ctx"
  assert_output --partial "research_directives:"
  assert_output --partial "C-01"
  assert_output --partial "Auth token expiry not validated"
  assert_output --partial "C-02"
  assert_output --partial "Rate limiting missing"
  refute_output --partial "C-03"
  refute_output --partial "Typo in comment"
}

@test "scout case includes codebase references" {
  mkdir -p "$TEST_WORKDIR/.yolo-planning/codebase"
  echo "# Index" > "$TEST_WORKDIR/.yolo-planning/codebase/INDEX.md"
  echo "# Patterns" > "$TEST_WORKDIR/.yolo-planning/codebase/PATTERNS.md"
  run_cc 01 scout
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-scout.toon"
  run cat "$ctx"
  assert_output --partial "codebase:"
  assert_output --partial "INDEX.md"
  assert_output --partial "PATTERNS.md"
}

@test "scout case works without critique.jsonl" {
  run_cc 01 scout
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-scout.toon"
  run cat "$ctx"
  assert_output --partial "phase:"
  assert_output --partial "goal:"
  refute_output --partial "research_directives:"
}

@test "scout case respects token budget" {
  # Create critique.jsonl with 50 critical findings
  for i in $(seq 1 50); do
    printf '{"id":"C-%02d","sev":"critical","q":"Finding number %d with a fairly descriptive message about what is wrong"}\n' "$i" "$i"
  done > "$PHASES_DIR/01-setup/critique.jsonl"
  run_cc 01 scout
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-scout.toon"
  local char_count
  char_count=$(wc -c < "$ctx")
  # enforce_budget enforces 1000-token (4000-char) limit; allow +200 for one-line overshoot
  assert [ "$char_count" -le 4200 ]
}

# --- Field filtering integration tests (plan 02-04) ---

@test "dev context does not contain plan header obj field" {
  local plan="$PHASES_DIR/01-setup/01-01.plan.jsonl"
  cp "$FIXTURES_DIR/plans/filter-test-plan.jsonl" "$plan"
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT' 01 dev '$PHASES_DIR' '$plan'"
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-dev.toon"
  # Dev context should have task data but NOT header obj field
  run cat "$ctx"
  assert_output --partial "T1"
  refute_output --partial "Build auth middleware"
}

@test "dev context does not contain task v field when filter available" {
  local plan="$PHASES_DIR/01-setup/01-01.plan.jsonl"
  cp "$FIXTURES_DIR/plans/filter-test-plan.jsonl" "$plan"
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT' 01 dev '$PHASES_DIR' '$plan'"
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-dev.toon"
  run cat "$ctx"
  # The 'v' field value 'middleware exports' should NOT appear in dev context
  # Note: when filter is unavailable (fallback), 'v' also does not appear because
  # the jq expression never extracts .v. So this test passes in both modes.
  refute_output --partial "middleware exports"
}

@test "dev context includes spec field from tasks" {
  local plan="$PHASES_DIR/01-setup/01-01.plan.jsonl"
  cp "$FIXTURES_DIR/plans/filter-test-plan.jsonl" "$plan"
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT' 01 dev '$PHASES_DIR' '$plan'"
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-dev.toon"
  run cat "$ctx"
  assert_output --partial "JWT validation"
}

@test "qa context includes plan_context with must_have when plan provided" {
  local plan="$PHASES_DIR/01-setup/01-01.plan.jsonl"
  cp "$FIXTURES_DIR/plans/filter-test-plan.jsonl" "$plan"
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT' 01 qa '$PHASES_DIR' '$plan'"
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-qa.toon"
  run cat "$ctx"
  # QA should see plan header data
  assert_output --partial "Build auth middleware"
  assert_output --partial "auth middleware exists"
  # QA should NOT see task spec details
  refute_output --partial "JWT validation"
  refute_output --partial "express-rate-limit"
}

@test "security context includes file paths from summaries" {
  cp "$FIXTURES_DIR/summaries/filter-test-summary.jsonl" "$PHASES_DIR/01-setup/01-01.summary.jsonl"
  run_cc 01 security
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-security.toon"
  run cat "$ctx"
  assert_output --partial "src/auth.ts"
  assert_output --partial "src/rate-limit.ts"
}

@test "security context does not contain commit hashes from summaries" {
  cp "$FIXTURES_DIR/summaries/filter-test-summary.jsonl" "$PHASES_DIR/01-setup/01-01.summary.jsonl"
  run_cc 01 security
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-security.toon"
  run cat "$ctx"
  # Security should NOT see commit hashes (ch field)
  refute_output --partial "abc1234"
  refute_output --partial "def5678"
  # Security should NOT see built descriptions
  refute_output --partial "rate limiter"
}

@test "tester context includes task test_spec from plan" {
  local plan="$PHASES_DIR/01-setup/01-01.plan.jsonl"
  cp "$FIXTURES_DIR/plans/filter-test-plan.jsonl" "$plan"
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT' 01 tester '$PHASES_DIR' '$plan'"
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-tester.toon"
  run cat "$ctx"
  assert_output --partial "validates tokens"
  assert_output --partial "rate limiting"
}

@test "qa-code context includes files_to_check from summaries" {
  cp "$FIXTURES_DIR/summaries/filter-test-summary.jsonl" "$PHASES_DIR/01-setup/01-01.summary.jsonl"
  run_cc 01 qa-code
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-qa-code.toon"
  run cat "$ctx"
  assert_output --partial "files_to_check:"
  assert_output --partial "src/auth.ts"
  # Should NOT have commit hashes
  refute_output --partial "abc1234"
}
