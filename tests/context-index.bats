#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  # Create a minimal phase directory structure
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning/phases/02-test-phase"
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning"
  # Create a minimal ROADMAP.md
  cat > "$TEST_TEMP_DIR/.yolo-planning/ROADMAP.md" <<'EOF'
# Test Roadmap
## Phase 2: Test Phase
**Goal:** Test goal
**Success:** Tests pass
**Reqs:** REQ-01
EOF
  # Create a minimal plan
  cat > "$TEST_TEMP_DIR/.yolo-planning/phases/02-test-phase/02-01-PLAN.md" <<'EOF'
---
phase: 2
plan: 1
title: "Test Plan"
wave: 1
depends_on: []
must_haves: ["test"]
---
# Test Plan
## Tasks
### Task 1: Test
- **Files:** test.sh
- **Action:** Test
EOF
}

teardown() {
  teardown_temp_dir
}

@test "compile-context produces context file when v3_context_cache=false" {
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" compile-context 02 dev ".yolo-planning/phases/02-test-phase" ".yolo-planning/phases/02-test-phase/02-01-PLAN.md"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/.yolo-planning/phases/02-test-phase/.context-dev.md" ]
}

@test "compile-context produces context file when v3_context_cache=true" {
  jq '.v3_context_cache = true' "$TEST_TEMP_DIR/.yolo-planning/config.json" > "$TEST_TEMP_DIR/.yolo-planning/config.tmp" && mv "$TEST_TEMP_DIR/.yolo-planning/config.tmp" "$TEST_TEMP_DIR/.yolo-planning/config.json"

  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" compile-context 02 dev ".yolo-planning/phases/02-test-phase" ".yolo-planning/phases/02-test-phase/02-01-PLAN.md"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/.yolo-planning/phases/02-test-phase/.context-dev.md" ]
}

@test "compile-context output has correct tiered structure" {
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" compile-context 02 dev ".yolo-planning/phases/02-test-phase" ".yolo-planning/phases/02-test-phase/02-01-PLAN.md"
  [ "$status" -eq 0 ]

  local ctx_file="$TEST_TEMP_DIR/.yolo-planning/phases/02-test-phase/.context-dev.md"
  # Must have all 3 tier headers and end sentinel
  grep -q "TIER 1: SHARED BASE" "$ctx_file"
  grep -q "TIER 2: ROLE FAMILY" "$ctx_file"
  grep -q "TIER 3: VOLATILE TAIL" "$ctx_file"
  grep -q "END COMPILED CONTEXT" "$ctx_file"
}

@test "compile-context includes plan content in tier 3" {
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" compile-context 02 dev ".yolo-planning/phases/02-test-phase" ".yolo-planning/phases/02-test-phase/02-01-PLAN.md"
  [ "$status" -eq 0 ]

  grep -q "Test Plan" "$TEST_TEMP_DIR/.yolo-planning/phases/02-test-phase/.context-dev.md"
}

@test "compile-context produces context for multiple roles" {
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" compile-context 02 lead ".yolo-planning/phases/02-test-phase" ".yolo-planning/phases/02-test-phase/02-01-PLAN.md"
  [ "$status" -eq 0 ]
  run "$YOLO_BIN" compile-context 02 dev ".yolo-planning/phases/02-test-phase" ".yolo-planning/phases/02-test-phase/02-01-PLAN.md"
  [ "$status" -eq 0 ]
  run "$YOLO_BIN" compile-context 02 qa ".yolo-planning/phases/02-test-phase" ".yolo-planning/phases/02-test-phase/02-01-PLAN.md"
  [ "$status" -eq 0 ]

  # Verify context files for all 3 roles
  [ -f "$TEST_TEMP_DIR/.yolo-planning/phases/02-test-phase/.context-lead.md" ]
  [ -f "$TEST_TEMP_DIR/.yolo-planning/phases/02-test-phase/.context-dev.md" ]
  [ -f "$TEST_TEMP_DIR/.yolo-planning/phases/02-test-phase/.context-qa.md" ]
}

@test "compile-context survives malformed cache index" {
  jq '.v3_context_cache = true' "$TEST_TEMP_DIR/.yolo-planning/config.json" > "$TEST_TEMP_DIR/.yolo-planning/config.tmp" && mv "$TEST_TEMP_DIR/.yolo-planning/config.tmp" "$TEST_TEMP_DIR/.yolo-planning/config.json"

  cd "$TEST_TEMP_DIR"
  # Create a corrupted index file
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning/.cache"
  echo "NOT VALID JSON{{{{" > "$TEST_TEMP_DIR/.yolo-planning/.cache/context-index.json"

  # Compilation should still succeed (index failure is non-fatal)
  run "$YOLO_BIN" compile-context 02 dev ".yolo-planning/phases/02-test-phase" ".yolo-planning/phases/02-test-phase/02-01-PLAN.md"
  [ "$status" -eq 0 ]

  # Context file should still be produced
  [ -f "$TEST_TEMP_DIR/.yolo-planning/phases/02-test-phase/.context-dev.md" ]
}
