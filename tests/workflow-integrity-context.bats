#!/usr/bin/env bats

load test_helper

# --- Context compilation tests for ARCHITECTURE.md in execution family ---

setup() {
  setup_temp_dir
  create_test_config

  mkdir -p "$TEST_TEMP_DIR/.yolo-planning/codebase"
  echo "# Architecture" > "$TEST_TEMP_DIR/.yolo-planning/codebase/ARCHITECTURE.md"
  echo "Architecture overview" >> "$TEST_TEMP_DIR/.yolo-planning/codebase/ARCHITECTURE.md"
  echo "# Roadmap" > "$TEST_TEMP_DIR/.yolo-planning/codebase/ROADMAP.md"
  echo "# Conventions" > "$TEST_TEMP_DIR/.yolo-planning/codebase/CONVENTIONS.md"
  echo "# Stack" > "$TEST_TEMP_DIR/.yolo-planning/codebase/STACK.md"
  mkdir -p "$TEST_TEMP_DIR/phases"
}

teardown() {
  teardown_temp_dir
}

@test "dev compiled context includes ARCHITECTURE.md content" {
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" compile-context 1 dev "$TEST_TEMP_DIR/phases"
  [ "$status" -eq 0 ]
  grep -q "Architecture overview" "$TEST_TEMP_DIR/phases/.context-dev.md"
}

@test "qa compiled context includes ARCHITECTURE.md content" {
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" compile-context 1 qa "$TEST_TEMP_DIR/phases"
  [ "$status" -eq 0 ]
  grep -q "Architecture overview" "$TEST_TEMP_DIR/phases/.context-qa.md"
}

@test "debugger compiled context includes ARCHITECTURE.md content" {
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" compile-context 1 debugger "$TEST_TEMP_DIR/phases"
  [ "$status" -eq 0 ]
  grep -q "Architecture overview" "$TEST_TEMP_DIR/phases/.context-debugger.md"
}

@test "default family does NOT get ARCHITECTURE.md" {
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" compile-context 1 observer "$TEST_TEMP_DIR/phases"
  [ "$status" -eq 0 ]
  ! grep -q "Architecture overview" "$TEST_TEMP_DIR/phases/.context-observer.md"
}
