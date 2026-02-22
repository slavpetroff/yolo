#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config

  YOLO_BIN="${YOLO_BIN:-$HOME/.cargo/bin/yolo}"

  # Create a valid plan file
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

@test "review-plan approves valid plan" {
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" review-plan "$TEST_TEMP_DIR/phases/01-test/01-01-PLAN.md" "$TEST_TEMP_DIR/phases/01-test"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"verdict"'
  echo "$output" | grep -q '"approve"'
}

@test "review-plan rejects plan without frontmatter" {
  cd "$TEST_TEMP_DIR"
  cat > "$TEST_TEMP_DIR/phases/01-test/01-02-PLAN.md" << 'PLAN'
# No Frontmatter Plan
## Tasks
### Task 1: Do thing
**Files:** `README.md`
PLAN

  run "$YOLO_BIN" review-plan "$TEST_TEMP_DIR/phases/01-test/01-02-PLAN.md" "$TEST_TEMP_DIR/phases/01-test"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q '"reject"'
}

@test "review-plan warns about missing must_haves" {
  cd "$TEST_TEMP_DIR"
  cat > "$TEST_TEMP_DIR/phases/01-test/01-03-PLAN.md" << 'PLAN'
---
phase: "01"
plan: "03"
title: "Empty must_haves plan"
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

  run "$YOLO_BIN" review-plan "$TEST_TEMP_DIR/phases/01-test/01-03-PLAN.md" "$TEST_TEMP_DIR/phases/01-test"
  echo "$output" | grep -q '"findings"'
}

@test "review-plan checks task count" {
  cd "$TEST_TEMP_DIR"
  cat > "$TEST_TEMP_DIR/phases/01-test/01-04-PLAN.md" << 'PLAN'
---
phase: "01"
plan: "04"
title: "Too many tasks plan"
wave: 1
depends_on: []
must_haves:
  - "done"
---
# Plan With Many Tasks
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
### Task 7: Seventh
**Files:** `README.md`
Content.
PLAN

  run "$YOLO_BIN" review-plan "$TEST_TEMP_DIR/phases/01-test/01-04-PLAN.md" "$TEST_TEMP_DIR/phases/01-test"
  echo "$output" | grep -q '"findings"'
}

@test "review-plan validates file paths" {
  cd "$TEST_TEMP_DIR"
  cat > "$TEST_TEMP_DIR/phases/01-test/01-05-PLAN.md" << 'PLAN'
---
phase: "01"
plan: "05"
title: "Bad file paths plan"
wave: 1
depends_on: []
must_haves:
  - "done"
---
# Plan With Nonexistent Files
## Tasks
### Task 1: Do thing
**Files:** `nonexistent/path/to/file.rs`
Content here.
PLAN

  run "$YOLO_BIN" review-plan "$TEST_TEMP_DIR/phases/01-test/01-05-PLAN.md" "$TEST_TEMP_DIR/phases/01-test"
  echo "$output" | grep -q '"findings"'
}
