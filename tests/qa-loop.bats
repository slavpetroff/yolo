#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config

  YOLO_BIN="${YOLO_BIN:-$HOME/.cargo/bin/yolo}"

  # Create a valid plan + summary pair
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
### Task 1: Do first thing
Content.
### Task 2: Do second thing
Content.
PLAN
}

teardown() {
  teardown_temp_dir
}

# --- QA command fixable_by fields for feedback loop ---

@test "verify-plan-completion failure has fixable_by on failed checks" {
  # Create invalid SUMMARY (missing required fields)
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
  # All checks must have fixable_by field
  echo "$output" | jq -e '.checks | all(has("fixable_by"))'
  # Failed checks must have fixable_by != "none"
  echo "$output" | jq -e '[.checks[] | select(.status == "fail")] | length > 0'
  echo "$output" | jq -e '[.checks[] | select(.status == "fail")] | all(.fixable_by != "none")'
}

@test "commit-lint violations have fixable_by dev and suggested_fix" {
  # Create temp git repo with bad commit messages
  LINT_DIR=$(mktemp -d)
  git init "$LINT_DIR"
  git -C "$LINT_DIR" commit --allow-empty -m "feat(init): initial commit"
  git -C "$LINT_DIR" commit --allow-empty -m "bad commit message"
  git -C "$LINT_DIR" commit --allow-empty -m "another bad one"
  cd "$LINT_DIR"
  run "$YOLO_BIN" commit-lint "HEAD~2..HEAD"
  cd /Users/slavpetroff/Projects/vibe-better-with-claude-code-vbw
  rm -rf "$LINT_DIR"
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.ok == false'
  echo "$output" | jq -e '.violations | length > 0'
  # Every violation must have fixable_by:"dev" and suggested_fix string
  echo "$output" | jq -e '.violations | all(.fixable_by == "dev")'
  echo "$output" | jq -e '.violations | all(has("suggested_fix"))'
  echo "$output" | jq -e '.violations | all(.suggested_fix | type == "string")'
}

@test "check-regression always has fixable_by manual" {
  run "$YOLO_BIN" check-regression "$TEST_TEMP_DIR/phases/01-test"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.cmd == "check-regression"'
  echo "$output" | jq -e '.fixable_by == "manual"'
}

@test "QA loop events accepted by log-event" {
  cd "$TEST_TEMP_DIR"
  # Enable v3_event_log so log-event actually writes (exit 0)
  cat > "$TEST_TEMP_DIR/.yolo-planning/config.json" << 'CONF'
{
  "v3_event_log": true,
  "v2_typed_protocol": false
}
CONF

  run "$YOLO_BIN" log-event qa_loop_start 1
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.ok == true'
  echo "$output" | jq -e '.delta.written == true'

  run "$YOLO_BIN" log-event qa_loop_cycle 1 cycle=1 failed_count=2
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.ok == true'
  echo "$output" | jq -e '.delta.written == true'

  run "$YOLO_BIN" log-event qa_loop_end 1
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.ok == true'
  echo "$output" | jq -e '.delta.written == true'
}

@test "validate-requirements has per-requirement fixable_by" {
  run "$YOLO_BIN" validate-requirements \
    "$TEST_TEMP_DIR/phases/01-test/01-01-PLAN.md" \
    "$TEST_TEMP_DIR/phases/01-test"
  # May pass or fail depending on evidence, but should produce JSON
  echo "$output" | jq -e '.cmd == "validate-requirements"'
  echo "$output" | jq -e '.requirements | length > 0'
  # Top-level fixable_by
  echo "$output" | jq -e 'has("fixable_by")'
  # Each requirement has fixable_by
  echo "$output" | jq -e '.requirements | all(has("fixable_by"))'
  echo "$output" | jq -e '.requirements | all(.fixable_by | type == "string")'
}
