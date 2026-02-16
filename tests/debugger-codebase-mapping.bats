#!/usr/bin/env bats

# Tests for issue #75: Debugger agent should reference codebase mapping before investigating

load test_helper

setup() {
  setup_temp_dir
}

teardown() {
  teardown_temp_dir
}

# =============================================================================
# Agent definition: debugger references codebase mapping
# =============================================================================

@test "debugger agent references codebase mapping in investigation protocol" {
  grep -q '.vbw-planning/codebase/' "$PROJECT_ROOT/agents/vbw-debugger.md"
}

@test "debugger agent checks META.md for mapping existence" {
  grep -q 'META.md' "$PROJECT_ROOT/agents/vbw-debugger.md"
}

@test "debugger agent references ARCHITECTURE.md" {
  grep -q 'ARCHITECTURE.md' "$PROJECT_ROOT/agents/vbw-debugger.md"
}

@test "debugger agent references CONCERNS.md" {
  grep -q 'CONCERNS.md' "$PROJECT_ROOT/agents/vbw-debugger.md"
}

# =============================================================================
# Compiled context: codebase mapping hint in debugger context
# =============================================================================

# Helper: set up minimal .vbw-planning structure for compile-context.sh
setup_debugger_context() {
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/01-test"
  create_test_config

  cat > "$TEST_TEMP_DIR/.vbw-planning/ROADMAP.md" <<'ROADMAP'
## Phases

## Phase 1: Debug Phase
**Goal:** Fix the broken widget
**Reqs:** REQ-01
**Success:** Widget renders correctly

---

## Phase 2: Future Phase
**Goal:** Placeholder
**Reqs:** REQ-02
**Success:** Placeholder
ROADMAP

  cat > "$TEST_TEMP_DIR/.vbw-planning/REQUIREMENTS.md" <<'REQS'
## Requirements
- [REQ-01] Widget must render correctly
REQS

  cat > "$TEST_TEMP_DIR/.vbw-planning/STATE.md" <<'STATE'
## Status
Phase: 1 of 1 (Debug Phase)
Status: executing
Progress: 0%

## Activity
- Bug reported in widget rendering

## Decisions
- None
STATE
}

@test "compile-context.sh debugger context includes codebase mapping hint when mapping exists" {
  setup_debugger_context
  cd "$TEST_TEMP_DIR"

  # Create codebase mapping files
  mkdir -p .vbw-planning/codebase
  echo "# Meta" > .vbw-planning/codebase/META.md
  echo "# Architecture overview" > .vbw-planning/codebase/ARCHITECTURE.md
  echo "# Known concerns" > .vbw-planning/codebase/CONCERNS.md

  run bash "$SCRIPTS_DIR/compile-context.sh" "01" "debugger" ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  grep -q "Codebase Map" ".vbw-planning/phases/01-test/.context-debugger.md"
}

@test "compile-context.sh debugger context lists available mapping files" {
  setup_debugger_context
  cd "$TEST_TEMP_DIR"

  mkdir -p .vbw-planning/codebase
  echo "# Meta" > .vbw-planning/codebase/META.md
  echo "# Architecture" > .vbw-planning/codebase/ARCHITECTURE.md
  echo "# Concerns" > .vbw-planning/codebase/CONCERNS.md
  echo "# Structure" > .vbw-planning/codebase/STRUCTURE.md

  run bash "$SCRIPTS_DIR/compile-context.sh" "01" "debugger" ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  grep -q "ARCHITECTURE.md" ".vbw-planning/phases/01-test/.context-debugger.md"
  grep -q "CONCERNS.md" ".vbw-planning/phases/01-test/.context-debugger.md"
}

@test "compile-context.sh debugger context omits codebase mapping when no mapping exists" {
  setup_debugger_context
  cd "$TEST_TEMP_DIR"

  # No codebase directory created
  run bash "$SCRIPTS_DIR/compile-context.sh" "01" "debugger" ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  # Should NOT contain codebase mapping section
  run grep "Codebase Map" ".vbw-planning/phases/01-test/.context-debugger.md"
  [ "$status" -eq 1 ]
}

@test "compile-context.sh debugger context omits codebase mapping when META.md missing" {
  setup_debugger_context
  cd "$TEST_TEMP_DIR"

  # Create directory but no META.md (incomplete mapping)
  mkdir -p .vbw-planning/codebase
  echo "# Architecture" > .vbw-planning/codebase/ARCHITECTURE.md

  run bash "$SCRIPTS_DIR/compile-context.sh" "01" "debugger" ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  # Should NOT contain codebase mapping section without META.md
  run grep "Codebase Map" ".vbw-planning/phases/01-test/.context-debugger.md"
  [ "$status" -eq 1 ]
}
