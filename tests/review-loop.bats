#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config

  YOLO_BIN="${YOLO_BIN:-$HOME/.cargo/bin/yolo}"

  # Create a valid plan file (used by approve test)
  mkdir -p "$TEST_TEMP_DIR/phases/01-test"
  cat > "$TEST_TEMP_DIR/phases/01-test/01-01-PLAN.md" << 'PLAN'
---
phase: "01"
plan: "01"
title: "Test plan"
wave: 1
depends_on: []
must_haves:
  - "thing works"
---
# Test Plan
## Tasks
### Task 1: Do thing
**Files:** `README.md`
Content here.
PLAN

  # Create referenced file so file_paths check passes
  touch "$TEST_TEMP_DIR/README.md"
}

teardown() {
  teardown_temp_dir
}

# --- Review-plan output fields for feedback loop ---

@test "review-plan reject verdict includes suggested_fix on findings" {
  cd "$TEST_TEMP_DIR"
  # Plan with empty must_haves triggers high severity -> reject
  cat > "$TEST_TEMP_DIR/phases/01-test/01-02-PLAN.md" << 'PLAN'
---
phase: "01"
plan: "02"
title: "Missing must_haves plan"
wave: 1
depends_on: []
must_haves: []
---
# Plan With No Must Haves
## Tasks
### Task 1: Do thing
**Files:** `README.md`
Content here.
PLAN

  run "$YOLO_BIN" review-plan "$TEST_TEMP_DIR/phases/01-test/01-02-PLAN.md" "$TEST_TEMP_DIR/phases/01-test"
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.verdict == "reject"'
  # Every finding must have suggested_fix (string) and auto_fixable (boolean)
  echo "$output" | jq -e '.findings | length > 0'
  echo "$output" | jq -e '.findings | all(has("suggested_fix"))'
  echo "$output" | jq -e '.findings | all(.suggested_fix | type == "string")'
  echo "$output" | jq -e '.findings | all(has("auto_fixable"))'
  echo "$output" | jq -e '.findings | all(.auto_fixable | type == "boolean")'
}

@test "review-plan conditional verdict has findings with auto_fixable" {
  cd "$TEST_TEMP_DIR"
  # Plan with >5 tasks triggers medium severity (task_count) -> conditional
  cat > "$TEST_TEMP_DIR/phases/01-test/01-03-PLAN.md" << 'PLAN'
---
phase: "01"
plan: "03"
title: "Big plan"
wave: 1
depends_on: []
must_haves:
  - "done"
---
# Big Plan
## Tasks
### Task 1: First
**Files:** `README.md`
Content.
### Task 2: Second
**Files:** `README.md`
Content.
### Task 3: Third
**Files:** `README.md`
Content.
### Task 4: Fourth
**Files:** `README.md`
Content.
### Task 5: Fifth
**Files:** `README.md`
Content.
### Task 6: Sixth
**Files:** `README.md`
Content.
PLAN

  run "$YOLO_BIN" review-plan "$TEST_TEMP_DIR/phases/01-test/01-03-PLAN.md" "$TEST_TEMP_DIR/phases/01-test"
  [ "$status" -eq 2 ]
  echo "$output" | jq -e '.verdict == "conditional"'
  echo "$output" | jq -e '.findings | length > 0'
  echo "$output" | jq -e '.findings | all(has("auto_fixable"))'
  echo "$output" | jq -e '.findings | all(.auto_fixable | type == "boolean")'
}

@test "review-plan approve verdict has no findings" {
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" review-plan "$TEST_TEMP_DIR/phases/01-test/01-01-PLAN.md" "$TEST_TEMP_DIR/phases/01-test"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.verdict == "approve"'
  echo "$output" | jq -e '.findings | length == 0'
}

@test "review loop events accepted by log-event" {
  cd "$TEST_TEMP_DIR"
  # Enable v3_event_log so log-event actually writes (exit 0)
  cat > "$TEST_TEMP_DIR/.yolo-planning/config.json" << 'CONF'
{
  "v3_event_log": true,
  "v2_typed_protocol": false
}
CONF

  run "$YOLO_BIN" log-event review_loop_start 1
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.ok == true'
  echo "$output" | jq -e '.delta.written == true'

  run "$YOLO_BIN" log-event review_loop_cycle 1 cycle=1 verdict=reject
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.ok == true'
  echo "$output" | jq -e '.delta.written == true'

  run "$YOLO_BIN" log-event review_loop_end 1
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.ok == true'
  echo "$output" | jq -e '.delta.written == true'
}
