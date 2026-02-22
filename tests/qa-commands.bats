#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config

  YOLO_BIN="${YOLO_BIN:-$HOME/.cargo/bin/yolo}"

  # Create a valid SUMMARY.md
  mkdir -p "$TEST_TEMP_DIR/phases/01-test"
  cat > "$TEST_TEMP_DIR/phases/01-test/01-01-SUMMARY.md" << 'SUMMARY'
---
phase: "01"
plan: "01"
title: "Test plan"
status: complete
tasks_completed: 2
tasks_total: 2
commit_hashes:
  - "abc1234"
  - "def5678"
files_modified:
  - "README.md"
---
## What Was Built
- Thing 1
## Files Modified
- `README.md` -- updated
## Deviations
None
SUMMARY

  # Create matching PLAN.md
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
### Task 1: Do first thing
Content.
### Task 2: Do second thing
Content.
PLAN
}

teardown() {
  teardown_temp_dir
}

@test "verify-plan-completion passes for valid summary" {
  run "$YOLO_BIN" verify-plan-completion \
    "$TEST_TEMP_DIR/phases/01-test/01-01-SUMMARY.md" \
    "$TEST_TEMP_DIR/phases/01-test/01-01-PLAN.md"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.ok == true'
}

@test "verify-plan-completion fails for missing fields" {
  cat > "$TEST_TEMP_DIR/phases/01-test/01-01-SUMMARY.md" << 'SUMMARY'
---
phase: "01"
plan: "01"
title: "Test plan"
status: complete
---
## What Was Built
- Thing 1
SUMMARY
  run "$YOLO_BIN" verify-plan-completion \
    "$TEST_TEMP_DIR/phases/01-test/01-01-SUMMARY.md" \
    "$TEST_TEMP_DIR/phases/01-test/01-01-PLAN.md"
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.ok == false'
}

@test "commit-lint passes for valid commits" {
  # Create temp git repo with valid commits
  LINT_DIR=$(mktemp -d)
  cd "$LINT_DIR"
  git init
  git commit --allow-empty -m "feat(init): initial commit"
  git commit --allow-empty -m "fix(core): fix a bug"
  run "$YOLO_BIN" commit-lint "HEAD~2..HEAD"
  cd /Users/slavpetroff/Projects/vibe-better-with-claude-code-vbw
  rm -rf "$LINT_DIR"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.ok == true'
}

@test "validate-requirements checks must_haves" {
  run "$YOLO_BIN" validate-requirements \
    "$TEST_TEMP_DIR/phases/01-test/01-01-PLAN.md" \
    "$TEST_TEMP_DIR/phases/01-test"
  # May pass or fail depending on evidence, but should produce JSON
  echo "$output" | jq -e '.cmd == "validate-requirements"'
  echo "$output" | jq -e '.requirements | length > 0'
}

@test "check-regression reports test counts" {
  run "$YOLO_BIN" check-regression "$TEST_TEMP_DIR/phases/01-test"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.cmd == "check-regression"'
  echo "$output" | jq -e 'has("rust_tests")'
  echo "$output" | jq -e 'has("bats_files")'
}
