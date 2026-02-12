#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
}

teardown() {
  teardown_temp_dir
}

@test "lock-lite.sh exits 0 when v3_lock_lite=false" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/lock-lite.sh" acquire "03-01-T1" "scripts/foo.sh"
  [ "$status" -eq 0 ]
  [ ! -d ".vbw-planning/.locks" ]
}

@test "lock-lite.sh acquire creates lock file" {
  cd "$TEST_TEMP_DIR"
  jq '.v3_lock_lite = true' ".vbw-planning/config.json" > ".vbw-planning/config.tmp" && mv ".vbw-planning/config.tmp" ".vbw-planning/config.json"

  run bash "$SCRIPTS_DIR/lock-lite.sh" acquire "03-01-T1" "scripts/foo.sh" "config/bar.json"
  [ "$status" -eq 0 ]
  [ "$output" = "acquired" ]
  [ -f ".vbw-planning/.locks/03-01-T1.lock" ]
}

@test "lock-lite.sh lock file contains task_id and files" {
  cd "$TEST_TEMP_DIR"
  jq '.v3_lock_lite = true' ".vbw-planning/config.json" > ".vbw-planning/config.tmp" && mv ".vbw-planning/config.tmp" ".vbw-planning/config.json"

  bash "$SCRIPTS_DIR/lock-lite.sh" acquire "03-01-T1" "scripts/foo.sh" "config/bar.json"

  run jq -r '.task_id' ".vbw-planning/.locks/03-01-T1.lock"
  [ "$output" = "03-01-T1" ]

  run jq -r '.files | length' ".vbw-planning/.locks/03-01-T1.lock"
  [ "$output" = "2" ]

  run jq -r '.files[0]' ".vbw-planning/.locks/03-01-T1.lock"
  [ "$output" = "scripts/foo.sh" ]
}

@test "lock-lite.sh release removes lock file" {
  cd "$TEST_TEMP_DIR"
  jq '.v3_lock_lite = true' ".vbw-planning/config.json" > ".vbw-planning/config.tmp" && mv ".vbw-planning/config.tmp" ".vbw-planning/config.json"

  bash "$SCRIPTS_DIR/lock-lite.sh" acquire "03-01-T1" "scripts/foo.sh"
  [ -f ".vbw-planning/.locks/03-01-T1.lock" ]

  run bash "$SCRIPTS_DIR/lock-lite.sh" release "03-01-T1"
  [ "$status" -eq 0 ]
  [ "$output" = "released" ]
  [ ! -f ".vbw-planning/.locks/03-01-T1.lock" ]
}

@test "lock-lite.sh check detects file conflict" {
  cd "$TEST_TEMP_DIR"
  jq '.v3_lock_lite = true' ".vbw-planning/config.json" > ".vbw-planning/config.tmp" && mv ".vbw-planning/config.tmp" ".vbw-planning/config.json"

  # First task acquires lock on scripts/foo.sh
  bash "$SCRIPTS_DIR/lock-lite.sh" acquire "03-01-T1" "scripts/foo.sh"

  # Second task checks for conflict on same file
  run bash "$SCRIPTS_DIR/lock-lite.sh" check "03-01-T2" "scripts/foo.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"conflicts:1"* ]]
}

@test "lock-lite.sh check returns clear when no conflict" {
  cd "$TEST_TEMP_DIR"
  jq '.v3_lock_lite = true' ".vbw-planning/config.json" > ".vbw-planning/config.tmp" && mv ".vbw-planning/config.tmp" ".vbw-planning/config.json"

  bash "$SCRIPTS_DIR/lock-lite.sh" acquire "03-01-T1" "scripts/foo.sh"

  run bash "$SCRIPTS_DIR/lock-lite.sh" check "03-01-T2" "scripts/bar.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "clear" ]
}

@test "lock-lite.sh conflict emits file_conflict metric" {
  cd "$TEST_TEMP_DIR"
  jq '.v3_lock_lite = true' ".vbw-planning/config.json" > ".vbw-planning/config.tmp" && mv ".vbw-planning/config.tmp" ".vbw-planning/config.json"
  jq '.v3_metrics = true' ".vbw-planning/config.json" > ".vbw-planning/config.tmp" && mv ".vbw-planning/config.tmp" ".vbw-planning/config.json"

  bash "$SCRIPTS_DIR/lock-lite.sh" acquire "03-01-T1" "scripts/foo.sh"

  # Acquire with conflict triggers metric
  bash "$SCRIPTS_DIR/lock-lite.sh" acquire "03-01-T2" "scripts/foo.sh"

  [ -f ".vbw-planning/.metrics/run-metrics.jsonl" ]
  grep -q "file_conflict" ".vbw-planning/.metrics/run-metrics.jsonl"
}

@test "lock-lite.sh release returns no_lock when lock doesn't exist" {
  cd "$TEST_TEMP_DIR"
  jq '.v3_lock_lite = true' ".vbw-planning/config.json" > ".vbw-planning/config.tmp" && mv ".vbw-planning/config.tmp" ".vbw-planning/config.json"

  run bash "$SCRIPTS_DIR/lock-lite.sh" release "nonexistent-task"
  [ "$status" -eq 0 ]
  [ "$output" = "no_lock" ]
}
