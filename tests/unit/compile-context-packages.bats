#!/usr/bin/env bats
# compile-context-packages.bats -- Tests for reference package integration in compile-context.sh
# Verifies: per-role reference_package @-references, fallback when packages/ absent,
# BASE_ROLE mapping for department-prefixed roles, budget compliance, tool_restrictions absence.

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  load '../test_helper/mock_stdin'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/compile-context.sh"

  # Set up .yolo-planning with phase dir, ROADMAP, conventions
  mkdir -p "$TEST_WORKDIR/.yolo-planning/phases/01-setup"

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

  # Create reference packages directory with mock package files
  mkdir -p "$TEST_WORKDIR/references/packages"

  cat > "$TEST_WORKDIR/references/packages/architect.toon" <<'EOF'
role: architect
step_protocol: Step 2 Architecture
escalation: Architect escalates to Lead
EOF

  cat > "$TEST_WORKDIR/references/packages/lead.toon" <<'EOF'
role: lead
step_protocol: Step 3 Load Plans, Step 10 Sign-off
escalation: Lead escalates to Owner
EOF

  cat > "$TEST_WORKDIR/references/packages/senior.toon" <<'EOF'
role: senior
step_protocol: Step 4 Design Review, Step 7 Code Review
escalation: Senior escalates to Lead
EOF

  cat > "$TEST_WORKDIR/references/packages/dev.toon" <<'EOF'
role: dev
step_protocol: Step 6 Implementation
escalation: Dev escalates to Senior
EOF

  cat > "$TEST_WORKDIR/references/packages/tester.toon" <<'EOF'
role: tester
step_protocol: Step 5 Test Authoring
escalation: Tester escalates to Senior
EOF

  cat > "$TEST_WORKDIR/references/packages/qa.toon" <<'EOF'
role: qa
step_protocol: Step 8 QA
escalation: QA escalates to Lead
EOF

  cat > "$TEST_WORKDIR/references/packages/qa-code.toon" <<'EOF'
role: qa-code
step_protocol: Step 8 QA Code
escalation: QA-Code escalates to Lead
EOF

  cat > "$TEST_WORKDIR/references/packages/critic.toon" <<'EOF'
role: critic
step_protocol: Step 1 Critique
escalation: Critic escalates to Lead
EOF

  cat > "$TEST_WORKDIR/references/packages/security.toon" <<'EOF'
role: security
step_protocol: Step 9 Security Audit
escalation: Security escalates to Lead
EOF

  PHASES_DIR="$TEST_WORKDIR/.yolo-planning/phases"
}

# Helper: run compile-context from test workdir
run_cc() {
  local phase="$1" role="$2"
  shift 2
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT' '$phase' '$role' '$PHASES_DIR' $*"
}

# --- Test 1: dev context includes reference_package when packages/ exists ---

@test "dev context includes reference_package when packages/ exists" {
  run_cc 01 dev
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-dev.toon"
  run cat "$ctx"
  assert_output --partial "reference_package:"
  assert_output --partial "packages/dev.toon"
}

# --- Test 2: senior context includes reference_package for senior.toon ---

@test "senior context includes reference_package for senior.toon" {
  run_cc 01 senior
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-senior.toon"
  run cat "$ctx"
  assert_output --partial "reference_package:"
  assert_output --partial "packages/senior.toon"
}

# --- Test 3: qa context includes reference_package for qa.toon ---

@test "qa context includes reference_package for qa.toon" {
  run_cc 01 qa
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-qa.toon"
  run cat "$ctx"
  assert_output --partial "reference_package:"
  assert_output --partial "packages/qa.toon"
}

# --- Test 4: architect context includes reference_package for architect.toon ---

@test "architect context includes reference_package for architect.toon" {
  run_cc 01 architect
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-architect.toon"
  run cat "$ctx"
  assert_output --partial "packages/architect.toon"
}

# --- Test 5: fe-dev context includes packages/dev.toon (BASE_ROLE mapping, D2) ---

@test "fe-dev context includes packages/dev.toon via BASE_ROLE mapping" {
  run_cc 01 fe-dev
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-fe-dev.toon"
  run cat "$ctx"
  assert_output --partial "packages/dev.toon"
}

# --- Test 6: fallback -- no reference_package when packages/ dir missing ---

@test "fallback: no reference_package when packages/ dir missing" {
  rm -rf "$TEST_WORKDIR/references/packages"
  run_cc 01 dev
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-dev.toon"
  run grep 'reference_package' "$ctx"
  assert_failure
}

# --- Test 7: all 9 base roles include reference_package ---

@test "all 9 base roles include reference_package" {
  for role in architect lead senior dev qa qa-code security critic; do
    run_cc 01 "$role"
    assert_success
    local ctx="$PHASES_DIR/01-setup/.ctx-${role}.toon"
    run grep 'reference_package:' "$ctx"
    assert_success
  done

  # tester needs a plan file
  local plan="$PHASES_DIR/01-setup/01-01.plan.jsonl"
  cp "$FIXTURES_DIR/plans/valid-plan.jsonl" "$plan"
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT' 01 tester '$PHASES_DIR' '$plan'"
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-tester.toon"
  run grep 'reference_package:' "$ctx"
  assert_success
}

# --- Test 8: context with packages is not drastically larger (budget check) ---

@test "context with packages is not drastically larger (budget check)" {
  run_cc 01 dev
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-dev.toon"
  local chars
  chars=$(wc -c < "$ctx")
  local tokens=$((chars / 4))
  [ "$tokens" -le 2000 ]
}

# --- Test 9: tool_restrictions section absent when resolve-tool-permissions.sh not available ---

@test "tool_restrictions section absent when resolve-tool-permissions.sh not available" {
  # Unset CLAUDE_PLUGIN_ROOT so it falls back to script dir resolution
  # The test environment does NOT have resolve-tool-permissions.sh as executable
  # in the expected location relative to the test workdir
  run bash -c "cd '$TEST_WORKDIR' && CLAUDE_PLUGIN_ROOT=/nonexistent bash '$SUT' 01 dev '$PHASES_DIR'"
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-dev.toon"
  run grep 'tool_restrictions' "$ctx"
  assert_failure
}

# --- Test 10: ux-architect uses packages/architect.toon (dept prefix stripped) ---

@test "ux-architect uses packages/architect.toon (dept prefix stripped)" {
  run_cc 01 ux-architect
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-ux-architect.toon"
  run cat "$ctx"
  assert_output --partial "packages/architect.toon"
}
