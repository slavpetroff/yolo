#!/usr/bin/env bats
# Migrated: update-state.sh -> yolo update-state
# CLI signature: yolo update-state <file_path>
# Behavior: triggers STATE.md / ROADMAP.md updates when a PLAN or SUMMARY file is written

load test_helper

YOLO_BIN="${YOLO_BIN:-$HOME/.cargo/bin/yolo}"

setup() {
  setup_temp_dir
  create_test_config
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning/phases/01-test-phase"
  cat > "$TEST_TEMP_DIR/.yolo-planning/STATE.md" <<'EOF'
Phase: 1 of 1 (Test Phase)
Plans: 0/0
Progress: 0%
Status: ready
EOF
  cat > "$TEST_TEMP_DIR/.yolo-planning/ROADMAP.md" <<'EOF'
- [ ] Phase 1: Test Phase

| Phase | Progress | Status | Completed |
|------|----------|--------|-----------|
| 1 - Test Phase | 0/0 | planned | - |
EOF
}

teardown() {
  teardown_temp_dir
}

@test "update-state: PLAN trigger updates plan count in STATE.md" {
  echo "# plan" > "$TEST_TEMP_DIR/.yolo-planning/phases/01-test-phase/01-01-PLAN.md"
  run "$YOLO_BIN" update-state "$TEST_TEMP_DIR/.yolo-planning/phases/01-test-phase/01-01-PLAN.md"
  [ "$status" -eq 0 ]
  grep -q 'Plans: 0/1' "$TEST_TEMP_DIR/.yolo-planning/STATE.md"
}

@test "update-state: PLAN trigger flips Status ready to active" {
  echo "# plan" > "$TEST_TEMP_DIR/.yolo-planning/phases/01-test-phase/01-01-PLAN.md"
  run "$YOLO_BIN" update-state "$TEST_TEMP_DIR/.yolo-planning/phases/01-test-phase/01-01-PLAN.md"
  [ "$status" -eq 0 ]
  grep -q 'Status: active' "$TEST_TEMP_DIR/.yolo-planning/STATE.md"
}

@test "update-state: non-PLAN/SUMMARY file exits 0 silently" {
  echo "random" > "$TEST_TEMP_DIR/test.txt"
  run "$YOLO_BIN" update-state "$TEST_TEMP_DIR/test.txt"
  [ "$status" -eq 0 ]
}

@test "update-state: nonexistent file exits 0 with message" {
  run "$YOLO_BIN" update-state "$TEST_TEMP_DIR/nonexistent.md"
  [ "$status" -eq 0 ]
}

@test "update-state: missing arguments exits with error" {
  run "$YOLO_BIN" update-state
  [ "$status" -ne 0 ]
}
