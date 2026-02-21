#!/usr/bin/env bats
# Migrated: lock-lite.sh -> yolo lock
# CWD-sensitive: yes

load test_helper

setup() {
  setup_temp_dir
  create_test_config
}

teardown() {
  teardown_temp_dir
}

@test "lock: exits 0 with skip when v3_lock_lite=false" {
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" lock acquire "scripts/foo.sh"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.reason == "v3_lock_lite=false"'
}

@test "lock: acquire creates lock and returns acquired" {
  cd "$TEST_TEMP_DIR"
  jq '.v3_lock_lite = true' ".yolo-planning/config.json" > ".yolo-planning/config.tmp" && mv ".yolo-planning/config.tmp" ".yolo-planning/config.json"

  run "$YOLO_BIN" lock acquire "scripts/foo.sh" --owner=task-1
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result == "acquired"'
  [ -d ".yolo-planning/.locks" ]
}

@test "lock: lock file contains resource and owner" {
  cd "$TEST_TEMP_DIR"
  jq '.v3_lock_lite = true' ".yolo-planning/config.json" > ".yolo-planning/config.tmp" && mv ".yolo-planning/config.tmp" ".yolo-planning/config.json"

  "$YOLO_BIN" lock acquire "scripts/foo.sh" --owner=task-1 >/dev/null

  LOCK_FILE=$(ls .yolo-planning/.locks/*.lock 2>/dev/null | head -1)
  [ -n "$LOCK_FILE" ]
  run jq -r '.owner' "$LOCK_FILE"
  [ "$output" = "task-1" ]
  run jq -r '.resource' "$LOCK_FILE"
  [ "$output" = "scripts/foo.sh" ]
}

@test "lock: release removes lock file" {
  cd "$TEST_TEMP_DIR"
  jq '.v3_lock_lite = true' ".yolo-planning/config.json" > ".yolo-planning/config.tmp" && mv ".yolo-planning/config.tmp" ".yolo-planning/config.json"

  "$YOLO_BIN" lock acquire "scripts/foo.sh" --owner=task-1 >/dev/null

  run "$YOLO_BIN" lock release "scripts/foo.sh" --owner=task-1
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result == "released"'
  LOCK_COUNT=$(ls .yolo-planning/.locks/*.lock 2>/dev/null | wc -l | tr -d ' ')
  [ "$LOCK_COUNT" = "0" ]
}

@test "lock: check detects conflict from different owner" {
  cd "$TEST_TEMP_DIR"
  jq '.v3_lock_lite = true' ".yolo-planning/config.json" > ".yolo-planning/config.tmp" && mv ".yolo-planning/config.tmp" ".yolo-planning/config.json"

  # First owner acquires lock
  "$YOLO_BIN" lock acquire "scripts/foo.sh" --owner=task-1 >/dev/null

  # Second owner checks for conflict
  run "$YOLO_BIN" lock check "scripts/foo.sh" --owner=task-2
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.has_conflicts == true'
}

@test "lock: check returns no conflict for same owner" {
  cd "$TEST_TEMP_DIR"
  jq '.v3_lock_lite = true' ".yolo-planning/config.json" > ".yolo-planning/config.tmp" && mv ".yolo-planning/config.tmp" ".yolo-planning/config.json"

  "$YOLO_BIN" lock acquire "scripts/foo.sh" --owner=task-1 >/dev/null

  run "$YOLO_BIN" lock check "scripts/foo.sh" --owner=task-1
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.has_conflicts == false'
}

@test "lock: check returns clear when no locks exist" {
  cd "$TEST_TEMP_DIR"
  jq '.v3_lock_lite = true' ".yolo-planning/config.json" > ".yolo-planning/config.tmp" && mv ".yolo-planning/config.tmp" ".yolo-planning/config.json"

  run "$YOLO_BIN" lock check "scripts/bar.sh" --owner=task-2
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.has_conflicts == false'
}

@test "lock: release returns not_held when lock doesn't exist" {
  cd "$TEST_TEMP_DIR"
  jq '.v3_lock_lite = true' ".yolo-planning/config.json" > ".yolo-planning/config.tmp" && mv ".yolo-planning/config.tmp" ".yolo-planning/config.json"

  run "$YOLO_BIN" lock release "nonexistent-file" --owner=task-1
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result == "not_held"'
}
