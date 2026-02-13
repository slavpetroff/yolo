#!/usr/bin/env bats
# bootstrap-roadmap.bats — Unit tests for scripts/bootstrap/bootstrap-roadmap.sh
# Generates ROADMAP.md and creates phase directories from phases JSON.

setup() {
  load '../../test_helper/common'
  load '../../test_helper/fixtures'
  load '../../test_helper/mock_stdin'
  mk_test_workdir
  SUT="$BOOTSTRAP_DIR/bootstrap-roadmap.sh"
  VALID_PHASES="$FIXTURES_DIR/phases/valid-phases.json"
}

# --- Argument validation ---

@test "exits 1 with usage when fewer than 3 args" {
  run bash "$SUT"
  assert_failure
  assert_output --partial "Usage:"

  run bash "$SUT" "$TEST_WORKDIR/ROADMAP.md" "Project"
  assert_failure
  assert_output --partial "Usage:"
}

@test "exits 1 when phases JSON file does not exist" {
  run bash "$SUT" "$TEST_WORKDIR/ROADMAP.md" "Project" "$TEST_WORKDIR/nonexistent.json"
  assert_failure
  assert_output --partial "not found"
}

@test "exits 1 when phases JSON is invalid" {
  echo "not json" > "$TEST_WORKDIR/bad.json"
  run bash "$SUT" "$TEST_WORKDIR/ROADMAP.md" "Project" "$TEST_WORKDIR/bad.json"
  assert_failure
  assert_output --partial "Invalid JSON"
}

# --- File generation ---

@test "generates ROADMAP.md with progress table and phase details" {
  run bash "$SUT" "$TEST_WORKDIR/.yolo-planning/ROADMAP.md" "TestProject" "$VALID_PHASES"
  assert_success
  assert_file_exist "$TEST_WORKDIR/.yolo-planning/ROADMAP.md"

  run cat "$TEST_WORKDIR/.yolo-planning/ROADMAP.md"
  assert_output --partial "# TestProject Roadmap"
  assert_output --partial "**Scope:** 2 phases"
  assert_output --partial "## Progress"
  assert_output --partial "| 1 | Pending | 0 | 0 | 0 |"
  assert_output --partial "| 2 | Pending | 0 | 0 | 0 |"
  assert_output --partial "## Phase 1: Setup"
  assert_output --partial "**Goal:** Initialize project structure"
  assert_output --partial "## Phase 2: Build Core"
  assert_output --partial "**Goal:** Implement core functionality"
  assert_output --partial "**Dependencies:** None"
  assert_output --partial "**Dependencies:** Phase 1"
}

@test "creates phase directories with correct naming convention" {
  bash "$SUT" "$TEST_WORKDIR/.yolo-planning/ROADMAP.md" "TestProject" "$VALID_PHASES"
  assert_dir_exist "$TEST_WORKDIR/.yolo-planning/phases/01-setup"
  assert_dir_exist "$TEST_WORKDIR/.yolo-planning/phases/02-build-core"
}

@test "exits 1 when phases array is empty" {
  echo "[]" > "$TEST_WORKDIR/empty-phases.json"
  run bash "$SUT" "$TEST_WORKDIR/ROADMAP.md" "Project" "$TEST_WORKDIR/empty-phases.json"
  assert_failure
  assert_output --partial "No phases defined"
}
