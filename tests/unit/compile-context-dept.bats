#!/usr/bin/env bats
# compile-context-dept.bats — Tests for department conventions injection in compile-context.sh
# Verifies: generated TOON resolution, dept_conventions injection per role, fallback, budget.

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  load '../test_helper/mock_stdin'
  mk_test_workdir
  mk_planning_dir
  SUT="$SCRIPTS_DIR/compile-context.sh"

  # Create phase dir with 1 plan file
  PHASE_DIR=$(mk_phase 1 setup 1 0)

  # Create ROADMAP (needed by compile-context.sh for phase metadata)
  mk_roadmap

  # Create conventions.json (needed for generic conventions)
  cat > "$TEST_WORKDIR/.yolo-planning/conventions.json" <<'EOF'
{"conventions":[{"category":"naming","rule":"Use kebab-case for files"},{"category":"style","rule":"One commit per task"}]}
EOF

  # Create generated department TOONs
  mkdir -p "$TEST_WORKDIR/.yolo-planning/departments"

  cat > "$TEST_WORKDIR/.yolo-planning/departments/backend.toon" <<'EOF'
backend_conventions:
  desc: Project-specific backend conventions (generated)

  language: Bash
  testing: bats-core
  tooling: jq, shell scripting
EOF

  cat > "$TEST_WORKDIR/.yolo-planning/departments/frontend.toon" <<'EOF'
frontend_conventions:
  desc: Project-specific frontend conventions (generated)

  language: React
  testing: jest
  tooling: webpack, TypeScript
EOF

  cat > "$TEST_WORKDIR/.yolo-planning/departments/uiux.toon" <<'EOF'
uiux_conventions:
  desc: Project-specific UI/UX conventions (generated)

  design_system: Figma tokens
  grid: 8px
  tooling: Storybook
EOF

  PHASES_DIR="$TEST_WORKDIR/.yolo-planning/phases"
}

# Helper: run compile-context.sh from test workdir
run_compile() {
  local role="$1"
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT' 01 '$role' '$PHASES_DIR'"
}

# --- 1. dev context includes dept_conventions when generated TOON exists ---

@test "dev context includes dept_conventions when generated TOON exists" {
  run_compile dev
  assert_success
  local ctx="$PHASE_DIR/.ctx-dev.toon"
  assert [ -f "$ctx" ]
  run grep 'dept_conventions' "$ctx"
  assert_success
}

# --- 2. dev context includes Bash language from generated TOON ---

@test "dev context includes Bash language from generated TOON" {
  run_compile dev
  assert_success
  local ctx="$PHASE_DIR/.ctx-dev.toon"
  run grep 'Bash' "$ctx"
  assert_success
}

# --- 3. senior context includes dept_conventions ---

@test "senior context includes dept_conventions" {
  run_compile senior
  assert_success
  local ctx="$PHASE_DIR/.ctx-senior.toon"
  assert [ -f "$ctx" ]
  run grep 'dept_conventions' "$ctx"
  assert_success
}

# --- 4. tester context includes dept_conventions ---

@test "tester context includes dept_conventions" {
  local plan="$PHASE_DIR/01-01.plan.jsonl"
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT' 01 tester '$PHASES_DIR' '$plan'"
  assert_success
  local ctx="$PHASE_DIR/.ctx-tester.toon"
  assert [ -f "$ctx" ]
  run grep 'dept_conventions' "$ctx"
  assert_success
}

# --- 5. qa-code context includes dept_conventions ---

@test "qa-code context includes dept_conventions" {
  run_compile qa-code
  assert_success
  local ctx="$PHASE_DIR/.ctx-qa-code.toon"
  assert [ -f "$ctx" ]
  run grep 'dept_conventions' "$ctx"
  assert_success
}

# --- 6. architect context does NOT include dept_conventions ---

@test "architect context does NOT include dept_conventions" {
  run_compile architect
  assert_success
  local ctx="$PHASE_DIR/.ctx-architect.toon"
  assert [ -f "$ctx" ]
  run grep 'dept_conventions' "$ctx"
  assert_failure
}

# --- 7. fallback: dev context works without generated TOON ---

@test "fallback: dev context works without generated TOON" {
  rm -rf "$TEST_WORKDIR/.yolo-planning/departments"
  run_compile dev
  assert_success
  local ctx="$PHASE_DIR/.ctx-dev.toon"
  assert [ -f "$ctx" ]
}

# --- 8. fe-dev resolves frontend.toon ---

@test "fe-dev resolves frontend.toon" {
  run_compile fe-dev
  assert_success
  local ctx="$PHASE_DIR/.ctx-fe-dev.toon"
  assert [ -f "$ctx" ]
  run grep 'dept_conventions' "$ctx"
  assert_success
  run grep 'React' "$ctx"
  assert_success
}

# --- 9. ux-dev resolves uiux.toon ---

@test "ux-dev resolves uiux.toon" {
  run_compile ux-dev
  assert_success
  local ctx="$PHASE_DIR/.ctx-ux-dev.toon"
  assert [ -f "$ctx" ]
  run grep 'dept_conventions' "$ctx"
  assert_success
  run grep 'Figma' "$ctx"
  assert_success
}

# --- 10. budget not exceeded for dev role ---

@test "budget not exceeded for dev role" {
  run_compile dev
  assert_success
  local ctx="$PHASE_DIR/.ctx-dev.toon"
  assert [ -f "$ctx" ]
  local chars
  chars=$(wc -c < "$ctx")
  local tokens=$((chars / 4))
  [ "$tokens" -le 2000 ]
}

# --- 11. lead context does NOT include dept_conventions ---

@test "lead context does NOT include dept_conventions" {
  run_compile lead
  assert_success
  local ctx="$PHASE_DIR/.ctx-lead.toon"
  assert [ -f "$ctx" ]
  run grep 'dept_conventions' "$ctx"
  assert_failure
}
