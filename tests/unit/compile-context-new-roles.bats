#!/usr/bin/env bats
# compile-context-new-roles.bats — Unit tests for compile-context.sh new roles:
# analyze, po, questionary, roadmap.
# Verifies each role produces valid .ctx-{role}.toon output with role-appropriate content.

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
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

  # Create reference packages for new roles
  mkdir -p "$TEST_WORKDIR/references/packages"
  echo "role: analyze" > "$TEST_WORKDIR/references/packages/analyze.toon"
  echo "role: po" > "$TEST_WORKDIR/references/packages/po.toon"
  echo "role: questionary" > "$TEST_WORKDIR/references/packages/questionary.toon"
  echo "role: roadmap" > "$TEST_WORKDIR/references/packages/roadmap.toon"

  PHASES_DIR="$TEST_WORKDIR/.yolo-planning/phases"
}

# Helper: run compile-context from test workdir
run_cc() {
  local phase="$1" role="$2"
  shift 2
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT' '$phase' '$role' '$PHASES_DIR' $*"
}

# --- Analyze role ---

@test "analyze role produces .ctx-analyze.toon" {
  run_cc 01 analyze
  assert_success
  assert_output --partial ".ctx-analyze.toon"
  assert [ -f "$PHASES_DIR/01-setup/.ctx-analyze.toon" ]
}

@test "analyze role includes phase and goal" {
  run_cc 01 analyze
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-analyze.toon"
  run cat "$ctx"
  assert_output --partial "phase: 01"
  assert_output --partial "goal:"
}

@test "analyze role includes codebase mapping when available" {
  echo "# Architecture" > "$TEST_WORKDIR/.yolo-planning/codebase/ARCHITECTURE.md"
  echo "# Index" > "$TEST_WORKDIR/.yolo-planning/codebase/INDEX.md"
  run_cc 01 analyze
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-analyze.toon"
  run cat "$ctx"
  assert_output --partial "codebase:"
  assert_output --partial "ARCHITECTURE.md"
  assert_output --partial "INDEX.md"
}

@test "analyze role uses shared department (department: shared tag)" {
  run_cc 01 analyze
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-analyze.toon"
  run cat "$ctx"
  assert_output --partial "department: shared"
}

@test "analyze role includes reference_package when packages/ exists" {
  run_cc 01 analyze
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-analyze.toon"
  run cat "$ctx"
  assert_output --partial "reference_package:"
  assert_output --partial "packages/analyze.toon"
}

# --- PO role ---

@test "po role produces .ctx-po.toon" {
  run_cc 01 po
  assert_success
  assert_output --partial ".ctx-po.toon"
  assert [ -f "$PHASES_DIR/01-setup/.ctx-po.toon" ]
}

@test "po role includes phase and goal" {
  run_cc 01 po
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-po.toon"
  run cat "$ctx"
  assert_output --partial "phase: 01"
  assert_output --partial "goal:"
}

@test "po role includes ROADMAP reference when available" {
  run_cc 01 po
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-po.toon"
  run cat "$ctx"
  assert_output --partial "roadmap:"
}

@test "po role includes REQUIREMENTS.md reference when available" {
  printf '# Requirements\nREQ-01: Setup project structure\nREQ-02: Initialize config\n' > "$TEST_WORKDIR/.yolo-planning/REQUIREMENTS.md"
  run_cc 01 po
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-po.toon"
  run cat "$ctx"
  assert_output --partial "requirements_doc:"
}

@test "po role includes success_criteria" {
  run_cc 01 po
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-po.toon"
  run cat "$ctx"
  assert_output --partial "success_criteria:"
  assert_output --partial "All files created"
}

@test "po role includes codebase mapping when available" {
  echo "# Architecture" > "$TEST_WORKDIR/.yolo-planning/codebase/ARCHITECTURE.md"
  run_cc 01 po
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-po.toon"
  run cat "$ctx"
  assert_output --partial "codebase:"
  assert_output --partial "ARCHITECTURE.md"
}

@test "po role includes prior_summaries section" {
  echo '{"p":"01","n":"01","s":"complete"}' > "$PHASES_DIR/01-setup/01-01.summary.jsonl"
  run_cc 01 po
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-po.toon"
  run cat "$ctx"
  assert_output --partial "prior_summaries:"
}

# --- Questionary role ---

@test "questionary role produces .ctx-questionary.toon" {
  run_cc 01 questionary
  assert_success
  assert_output --partial ".ctx-questionary.toon"
  assert [ -f "$PHASES_DIR/01-setup/.ctx-questionary.toon" ]
}

@test "questionary role includes phase and goal" {
  run_cc 01 questionary
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-questionary.toon"
  run cat "$ctx"
  assert_output --partial "phase: 01"
  assert_output --partial "goal:"
}

@test "questionary role includes REQUIREMENTS.md reference" {
  printf '# Requirements\nREQ-01: Setup project structure\nREQ-02: Initialize config\n' > "$TEST_WORKDIR/.yolo-planning/REQUIREMENTS.md"
  run_cc 01 questionary
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-questionary.toon"
  run cat "$ctx"
  assert_output --partial "requirements_doc:"
}

@test "questionary role includes research findings when available" {
  echo '{"q":"Auth best practices?","finding":"Use OAuth2"}' > "$PHASES_DIR/01-setup/research.jsonl"
  run_cc 01 questionary
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-questionary.toon"
  run cat "$ctx"
  assert_output --partial "research:"
  assert_output --partial "OAuth2"
}

@test "questionary role includes codebase mapping with PATTERNS" {
  echo "# Architecture" > "$TEST_WORKDIR/.yolo-planning/codebase/ARCHITECTURE.md"
  echo "# Index" > "$TEST_WORKDIR/.yolo-planning/codebase/INDEX.md"
  echo "# Patterns" > "$TEST_WORKDIR/.yolo-planning/codebase/PATTERNS.md"
  run_cc 01 questionary
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-questionary.toon"
  run cat "$ctx"
  assert_output --partial "codebase:"
  assert_output --partial "ARCHITECTURE.md"
  assert_output --partial "INDEX.md"
  assert_output --partial "PATTERNS.md"
}

# --- Roadmap role ---

@test "roadmap role produces .ctx-roadmap.toon" {
  run_cc 01 roadmap
  assert_success
  assert_output --partial ".ctx-roadmap.toon"
  assert [ -f "$PHASES_DIR/01-setup/.ctx-roadmap.toon" ]
}

@test "roadmap role includes phase and goal" {
  run_cc 01 roadmap
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-roadmap.toon"
  run cat "$ctx"
  assert_output --partial "phase: 01"
  assert_output --partial "goal:"
}

@test "roadmap role includes ROADMAP reference" {
  run_cc 01 roadmap
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-roadmap.toon"
  run cat "$ctx"
  assert_output --partial "roadmap:"
}

@test "roadmap role includes REQUIREMENTS.md reference" {
  printf '# Requirements\nREQ-01: Setup project structure\nREQ-02: Initialize config\n' > "$TEST_WORKDIR/.yolo-planning/REQUIREMENTS.md"
  run_cc 01 roadmap
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-roadmap.toon"
  run cat "$ctx"
  assert_output --partial "requirements_doc:"
}

@test "roadmap role includes full codebase mapping with CONCERNS" {
  echo "# Architecture" > "$TEST_WORKDIR/.yolo-planning/codebase/ARCHITECTURE.md"
  echo "# Index" > "$TEST_WORKDIR/.yolo-planning/codebase/INDEX.md"
  echo "# Patterns" > "$TEST_WORKDIR/.yolo-planning/codebase/PATTERNS.md"
  echo "# Concerns" > "$TEST_WORKDIR/.yolo-planning/codebase/CONCERNS.md"
  run_cc 01 roadmap
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-roadmap.toon"
  run cat "$ctx"
  assert_output --partial "codebase:"
  assert_output --partial "ARCHITECTURE.md"
  assert_output --partial "CONCERNS.md"
}

@test "roadmap role includes success_criteria" {
  run_cc 01 roadmap
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-roadmap.toon"
  run cat "$ctx"
  assert_output --partial "success_criteria:"
  assert_output --partial "All files created"
}

# --- Budget enforcement ---

@test "analyze role stays within 2000 token budget" {
  echo "# Architecture" > "$TEST_WORKDIR/.yolo-planning/codebase/ARCHITECTURE.md"
  echo "# Index" > "$TEST_WORKDIR/.yolo-planning/codebase/INDEX.md"
  run_cc 01 analyze
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-analyze.toon"
  local chars
  chars=$(wc -c < "$ctx")
  local tokens=$((chars / 4))
  [ "$tokens" -le 2000 ]
}

@test "po role stays within 3000 token budget" {
  printf '# Requirements\nREQ-01: Setup project structure\nREQ-02: Initialize config\n' > "$TEST_WORKDIR/.yolo-planning/REQUIREMENTS.md"
  run_cc 01 po
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-po.toon"
  local chars
  chars=$(wc -c < "$ctx")
  local tokens=$((chars / 4))
  [ "$tokens" -le 3000 ]
}

@test "questionary role stays within 2000 token budget" {
  run_cc 01 questionary
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-questionary.toon"
  local chars
  chars=$(wc -c < "$ctx")
  local tokens=$((chars / 4))
  [ "$tokens" -le 2000 ]
}

@test "roadmap role stays within 3000 token budget" {
  run_cc 01 roadmap
  assert_success
  local ctx="$PHASES_DIR/01-setup/.ctx-roadmap.toon"
  local chars
  chars=$(wc -c < "$ctx")
  local tokens=$((chars / 4))
  [ "$tokens" -le 3000 ]
}

# --- All new roles are recognized (not "Unknown role") ---

@test "all new roles are recognized without error" {
  for role in analyze po questionary roadmap; do
    run_cc 01 "$role"
    assert_success
    refute_output --partial "Unknown role"
  done
}
