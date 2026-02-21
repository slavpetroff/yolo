#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  export YOLO_BIN="${YOLO_BIN:-$HOME/.cargo/bin/yolo}"
  cd "$TEST_TEMP_DIR"
  git init --quiet
  git config user.email "test@test.com"
  git config user.name "Test"
  touch dummy && git add dummy && git commit -m "init" --quiet
}

teardown() {
  cd "$PROJECT_ROOT"
  teardown_temp_dir
}

@test "detects no planning directory" {
  rm -rf .yolo-planning
  run "$YOLO_BIN" phase-detect
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "planning_dir_exists=false"
}

@test "detects planning directory exists" {
  run "$YOLO_BIN" phase-detect
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "planning_dir_exists=true"
}

@test "detects no project when PROJECT.md missing" {
  run "$YOLO_BIN" phase-detect
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "project_exists=false"
}

@test "detects project exists" {
  echo "# My Project" > .yolo-planning/PROJECT.md
  run "$YOLO_BIN" phase-detect
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "project_exists=true"
}

@test "detects zero phases" {
  mkdir -p .yolo-planning/phases
  run "$YOLO_BIN" phase-detect
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "phase_count=0"
}

@test "detects phases needing plan" {
  mkdir -p .yolo-planning/phases/01-test/
  run "$YOLO_BIN" phase-detect
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "next_phase_state=needs_plan_and_execute"
}

@test "detects phases needing execution" {
  mkdir -p .yolo-planning/phases/01-test/
  touch .yolo-planning/phases/01-test/01-01-PLAN.md
  run "$YOLO_BIN" phase-detect
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "next_phase_state=needs_execute"
}

@test "detects all phases done" {
  mkdir -p .yolo-planning/phases/01-test/
  touch .yolo-planning/phases/01-test/01-01-PLAN.md
  touch .yolo-planning/phases/01-test/01-01-SUMMARY.md
  run "$YOLO_BIN" phase-detect
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "next_phase_state=all_done"
}

@test "reads config values" {
  run "$YOLO_BIN" phase-detect
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "config_effort=balanced"
  echo "$output" | grep -q "config_autonomy=standard"
}
