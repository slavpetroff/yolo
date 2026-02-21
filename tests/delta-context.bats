#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning/phases/02-test-phase"
  cat > "$TEST_TEMP_DIR/.yolo-planning/ROADMAP.md" <<'EOF'
# Test Roadmap
## Phase 2: Test Phase
**Goal:** Test goal
EOF
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
EOF
}

teardown() {
  teardown_temp_dir
}

@test "delta-files outputs changed files in git repo" {
  cd "$PROJECT_ROOT"
  run "$YOLO_BIN" delta-files "$TEST_TEMP_DIR/.yolo-planning/phases/02-test-phase"
  [ "$status" -eq 0 ]
  # Should output at least some files (we have uncommitted changes or recent commits)
  # Just verify it doesn't error
}

@test "delta-files handles non-git directory gracefully" {
  cd "$TEST_TEMP_DIR"
  # No SUMMARY.md files, no git — should output nothing and exit 0
  run "$YOLO_BIN" delta-files ".yolo-planning/phases/02-test-phase"
  [ "$status" -eq 0 ]
}

@test "delta-files extracts files from SUMMARY.md when no git" {
  cd "$TEST_TEMP_DIR"
  cat > ".yolo-planning/phases/02-test-phase/02-01-SUMMARY.md" <<'EOF'
---
phase: 2
plan: 1
title: "Test"
status: complete
---
# Summary
## Files Modified
- scripts/test.sh
- config/test.json (new)
## Deviations
EOF
  run "$YOLO_BIN" delta-files ".yolo-planning/phases/02-test-phase"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "scripts/test.sh"
}

@test "compile-context includes plan in tier 3 when v3_delta_context=true" {
  cd "$TEST_TEMP_DIR"
  jq '.v3_delta_context = true' ".yolo-planning/config.json" > ".yolo-planning/config.tmp" && mv ".yolo-planning/config.tmp" ".yolo-planning/config.json"

  run "$YOLO_BIN" compile-context 02 dev ".yolo-planning/phases/02-test-phase" ".yolo-planning/phases/02-test-phase/02-01-PLAN.md"
  [ "$status" -eq 0 ]
  # Should produce context file with plan content in TIER 3
  grep -q "TIER 3" ".yolo-planning/phases/02-test-phase/.context-dev.md"
  grep -q "Test Plan" ".yolo-planning/phases/02-test-phase/.context-dev.md"
}

@test "compile-context produces valid output when v3_delta_context=false" {
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" compile-context 02 dev ".yolo-planning/phases/02-test-phase" ".yolo-planning/phases/02-test-phase/02-01-PLAN.md"
  [ "$status" -eq 0 ]
  # Should still produce a context file with all tiers
  grep -q "TIER 1" ".yolo-planning/phases/02-test-phase/.context-dev.md"
  grep -q "END COMPILED CONTEXT" ".yolo-planning/phases/02-test-phase/.context-dev.md"
}
