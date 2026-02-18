#!/usr/bin/env bats
# compile-context-rolling-summary.bats — Tests for rolling summary and error recovery context
# Verifies T-1 (rolling summaries) and CG-4 (error recovery) in compile-context.sh

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
**Reqs:** REQ-01
**Success Criteria:** All files created
EOF

  # Conventions file
  cat > "$TEST_WORKDIR/.yolo-planning/conventions.json" <<'EOF'
{"conventions":[{"category":"naming","rule":"Use kebab-case for files"}]}
EOF

  PHASES_DIR="$TEST_WORKDIR/.yolo-planning/phases"
  PHASE_DIR="$PHASES_DIR/01-setup"

  # Create 3 plans: 01-01, 01-02, 01-03
  # Plan 01-01
  cat > "$PHASE_DIR/01-01.plan.jsonl" <<'EOF'
{"p":"01","n":"01-01","t":"First plan","mh":{"tr":["first plan must-have"]},"obj":"Build first feature"}
{"id":"T1","a":"create","f":["src/a.ts"],"spec":"Create module A","done":"module A exists"}
EOF

  # Plan 01-02
  cat > "$PHASE_DIR/01-02.plan.jsonl" <<'EOF'
{"p":"01","n":"01-02","t":"Second plan","mh":{"tr":["second plan must-have"]},"obj":"Build second feature"}
{"id":"T1","a":"create","f":["src/b.ts"],"spec":"Create module B","done":"module B exists"}
EOF

  # Plan 01-03 (current plan for tests)
  cat > "$PHASE_DIR/01-03.plan.jsonl" <<'EOF'
{"p":"01","n":"01-03","t":"Third plan","mh":{"tr":["third plan must-have"]},"obj":"Build third feature"}
{"id":"T1","a":"create","f":["src/c.ts"],"spec":"Create module C","done":"module C exists"}
EOF

  # Summary for plan 01-01 (completed)
  cat > "$PHASE_DIR/01-01.summary.jsonl" <<'EOF'
{"p":"01","n":"01-01","s":"complete","fm":["src/a.ts"],"desc":"Built first feature"}
EOF

  # Summary for plan 01-02 (completed)
  cat > "$PHASE_DIR/01-02.summary.jsonl" <<'EOF'
{"p":"01","n":"01-02","s":"complete","fm":["src/b.ts"],"desc":"Built second feature"}
EOF
}

# Helper: run compile-context from test workdir
run_cc() {
  local phase="$1" role="$2"
  shift 2
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT' '$phase' '$role' '$PHASES_DIR' $*"
}

# --- Rolling summary tests for dev ---

@test "dev context for plan 03 includes prior_plans with summaries for 01 and 02" {
  local plan="$PHASE_DIR/01-03.plan.jsonl"
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT' 01 dev '$PHASES_DIR' '$plan'"
  assert_success
  local ctx="$PHASE_DIR/.ctx-dev.toon"
  run cat "$ctx"
  assert_output --partial "prior_plans:"
  assert_output --partial "01-01: s=complete"
  assert_output --partial "01-02: s=complete"
}

@test "dev context for plan 03 includes full task detail for current plan" {
  local plan="$PHASE_DIR/01-03.plan.jsonl"
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT' 01 dev '$PHASES_DIR' '$plan'"
  assert_success
  local ctx="$PHASE_DIR/.ctx-dev.toon"
  run cat "$ctx"
  assert_output --partial "tasks["
  assert_output --partial "Create module C"
}

@test "dev context for plan 01 has no prior_plans section" {
  local plan="$PHASE_DIR/01-01.plan.jsonl"
  # Remove summaries that would match (no plans before 01-01)
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT' 01 dev '$PHASES_DIR' '$plan'"
  assert_success
  local ctx="$PHASE_DIR/.ctx-dev.toon"
  run cat "$ctx"
  refute_output --partial "prior_plans:"
}

@test "dev context for plan 02 includes only plan 01 summary" {
  local plan="$PHASE_DIR/01-02.plan.jsonl"
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT' 01 dev '$PHASES_DIR' '$plan'"
  assert_success
  local ctx="$PHASE_DIR/.ctx-dev.toon"
  run cat "$ctx"
  assert_output --partial "prior_plans:"
  assert_output --partial "01-01: s=complete"
  refute_output --partial "01-02: s=complete"
}

# --- Rolling summary tests for senior ---

@test "senior context for plan 03 includes prior_plans with summaries" {
  local plan="$PHASE_DIR/01-03.plan.jsonl"
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT' 01 senior '$PHASES_DIR' '$plan'"
  assert_success
  local ctx="$PHASE_DIR/.ctx-senior.toon"
  run cat "$ctx"
  assert_output --partial "prior_plans:"
  assert_output --partial "01-01: s=complete"
  assert_output --partial "01-02: s=complete"
}

# --- Rolling summary tests for qa ---

@test "qa context includes plan_summaries for all plans" {
  run_cc 01 qa
  assert_success
  local ctx="$PHASE_DIR/.ctx-qa.toon"
  run cat "$ctx"
  assert_output --partial "plan_summaries:"
  assert_output --partial "01-01: s=complete"
  assert_output --partial "01-02: s=complete"
}

@test "qa context includes test_results when available" {
  echo '{"plan":"01-01","ps":5,"fl":0,"dept":"backend"}' > "$PHASE_DIR/test-results.jsonl"
  run_cc 01 qa
  assert_success
  local ctx="$PHASE_DIR/.ctx-qa.toon"
  run cat "$ctx"
  assert_output --partial "test_results:"
  assert_output --partial "01-01: ps=5 fl=0"
}

# --- Rolling summary tests for qa-code ---

@test "qa-code context includes plan_summaries for all plans" {
  run_cc 01 qa-code
  assert_success
  local ctx="$PHASE_DIR/.ctx-qa-code.toon"
  run cat "$ctx"
  assert_output --partial "plan_summaries:"
  assert_output --partial "01-01: s=complete"
  assert_output --partial "01-02: s=complete"
}

# --- Error recovery context tests ---

@test "dev context includes error_recovery when gaps.jsonl has retry_context" {
  cat > "$PHASE_DIR/gaps.jsonl" <<'EOF'
{"id":"G-01","st":"open","desc":"Auth fails","retry_context":"JWT token expired at line 42, stack: auth.ts:42 > middleware.ts:15"}
EOF
  local plan="$PHASE_DIR/01-03.plan.jsonl"
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT' 01 dev '$PHASES_DIR' '$plan'"
  assert_success
  local ctx="$PHASE_DIR/.ctx-dev.toon"
  run cat "$ctx"
  assert_output --partial "error_recovery:"
  assert_output --partial "G-01"
  assert_output --partial "JWT token expired"
}

@test "senior context includes error_recovery when gaps.jsonl has retry_context" {
  cat > "$PHASE_DIR/gaps.jsonl" <<'EOF'
{"id":"G-02","st":"open","desc":"Rate limit bug","retry_context":"Rate limiter not applying to /api/v2 routes"}
EOF
  local plan="$PHASE_DIR/01-03.plan.jsonl"
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT' 01 senior '$PHASES_DIR' '$plan'"
  assert_success
  local ctx="$PHASE_DIR/.ctx-senior.toon"
  run cat "$ctx"
  assert_output --partial "error_recovery:"
  assert_output --partial "G-02"
  assert_output --partial "Rate limiter not applying"
}

@test "dev context has no error_recovery when gaps.jsonl has no open retry entries" {
  cat > "$PHASE_DIR/gaps.jsonl" <<'EOF'
{"id":"G-01","st":"resolved","desc":"Auth fixed","retry_context":"was broken"}
{"id":"G-02","st":"open","desc":"No retry ctx"}
EOF
  local plan="$PHASE_DIR/01-03.plan.jsonl"
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT' 01 dev '$PHASES_DIR' '$plan'"
  assert_success
  local ctx="$PHASE_DIR/.ctx-dev.toon"
  run cat "$ctx"
  refute_output --partial "error_recovery:"
}

@test "dev context has no error_recovery when gaps.jsonl does not exist" {
  local plan="$PHASE_DIR/01-03.plan.jsonl"
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT' 01 dev '$PHASES_DIR' '$plan'"
  assert_success
  local ctx="$PHASE_DIR/.ctx-dev.toon"
  run cat "$ctx"
  refute_output --partial "error_recovery:"
}

@test "error_recovery includes multiple open gaps with retry_context" {
  cat > "$PHASE_DIR/gaps.jsonl" <<'EOF'
{"id":"G-01","st":"open","desc":"First fail","retry_context":"Error in module A"}
{"id":"G-02","st":"open","desc":"Second fail","retry_context":"Error in module B"}
{"id":"G-03","st":"resolved","desc":"Fixed","retry_context":"was broken"}
EOF
  local plan="$PHASE_DIR/01-03.plan.jsonl"
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT' 01 dev '$PHASES_DIR' '$plan'"
  assert_success
  local ctx="$PHASE_DIR/.ctx-dev.toon"
  run cat "$ctx"
  assert_output --partial "error_recovery:"
  assert_output --partial "G-01"
  assert_output --partial "Error in module A"
  assert_output --partial "G-02"
  assert_output --partial "Error in module B"
  refute_output --partial "G-03"
}
