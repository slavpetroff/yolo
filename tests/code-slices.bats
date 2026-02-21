#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning/phases/01-test"
  # Enable delta context
  jq '.v3_delta_context = true' "$TEST_TEMP_DIR/.yolo-planning/config.json" > "$TEST_TEMP_DIR/.yolo-planning/config.json.tmp" \
    && mv "$TEST_TEMP_DIR/.yolo-planning/config.json.tmp" "$TEST_TEMP_DIR/.yolo-planning/config.json"
  # Create ROADMAP.md with phase info
  cat > "$TEST_TEMP_DIR/.yolo-planning/ROADMAP.md" << 'ROADMAP'
## Phase 1: Test Phase

**Goal:** Test code slices
**Reqs:** REQ-08
**Success:** Code slices included in context
ROADMAP
}

teardown() {
  teardown_temp_dir
}

@test "compile-context: produces output when delta enabled" {
  cd "$TEST_TEMP_DIR"
  mkdir -p src
  echo 'console.log("hello")' > src/test.js
  cat > .yolo-planning/phases/01-test/01-01-PLAN.md << 'PLAN'
---
phase: 1
plan: 1
title: Test
wave: 1
depends_on: []
files_modified:
  - src/test.js
---
Test plan
PLAN
  git init "$TEST_TEMP_DIR" > /dev/null 2>&1
  git -C "$TEST_TEMP_DIR" add src/test.js > /dev/null 2>&1
  run "$YOLO_BIN" compile-context 01 dev "$TEST_TEMP_DIR/.yolo-planning/phases/01-test" "$TEST_TEMP_DIR/.yolo-planning/phases/01-test/01-01-PLAN.md"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/.yolo-planning/phases/01-test/.context-dev.md" ]
  # Should have tiered structure
  grep -q "TIER 1" "$TEST_TEMP_DIR/.yolo-planning/phases/01-test/.context-dev.md"
}

@test "compile-context: omits delta content when delta disabled" {
  cd "$TEST_TEMP_DIR"
  jq '.v3_delta_context = false' .yolo-planning/config.json > .yolo-planning/config.json.tmp \
    && mv .yolo-planning/config.json.tmp .yolo-planning/config.json
  cat > .yolo-planning/phases/01-test/01-01-PLAN.md << 'PLAN'
---
phase: 1
plan: 1
title: Test
wave: 1
depends_on: []
---
Test plan
PLAN
  run "$YOLO_BIN" compile-context 01 dev "$TEST_TEMP_DIR/.yolo-planning/phases/01-test" "$TEST_TEMP_DIR/.yolo-planning/phases/01-test/01-01-PLAN.md"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/.yolo-planning/phases/01-test/.context-dev.md" ]
  # Should not include "Changed Files" section when delta disabled
  ! grep -q "Changed Files" "$TEST_TEMP_DIR/.yolo-planning/phases/01-test/.context-dev.md"
}

@test "compile-context: includes plan content in output" {
  cd "$TEST_TEMP_DIR"
  mkdir -p src
  printf 'function hello() {\n  return "world";\n}\n' > src/small.js
  cat > .yolo-planning/phases/01-test/01-01-PLAN.md << 'PLAN'
---
phase: 1
plan: 1
title: Test
wave: 1
depends_on: []
files_modified:
  - src/small.js
---
Test plan
PLAN
  run "$YOLO_BIN" compile-context 01 dev "$TEST_TEMP_DIR/.yolo-planning/phases/01-test" "$TEST_TEMP_DIR/.yolo-planning/phases/01-test/01-01-PLAN.md"
  [ "$status" -eq 0 ]
  # Plan content should be in tier 3
  grep -q "Test plan" "$TEST_TEMP_DIR/.yolo-planning/phases/01-test/.context-dev.md"
}
