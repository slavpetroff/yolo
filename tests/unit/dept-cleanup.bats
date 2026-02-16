#!/usr/bin/env bats
# dept-cleanup.bats — Unit tests for scripts/dept-cleanup.sh
# Safe removal of coordination files from phase directory after completion.

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/dept-cleanup.sh"
  PHASE_DIR="$TEST_WORKDIR/.yolo-planning/phases/02-test"
  mkdir -p "$PHASE_DIR"
}

# --- Removes coordination files ---

@test "removes coordination files" {
  touch "$PHASE_DIR/.dept-status-backend.json"
  touch "$PHASE_DIR/.dept-status-frontend.json"
  touch "$PHASE_DIR/.handoff-ux-complete"
  touch "$PHASE_DIR/.dept-lock-backend"
  touch "$PHASE_DIR/.phase-orchestration.json"
  run bash "$SUT" --phase-dir "$PHASE_DIR" --reason complete
  assert_success
  assert_file_not_exists "$PHASE_DIR/.dept-status-backend.json"
  assert_file_not_exists "$PHASE_DIR/.dept-status-frontend.json"
  assert_file_not_exists "$PHASE_DIR/.handoff-ux-complete"
  assert_file_not_exists "$PHASE_DIR/.dept-lock-backend"
  assert_file_not_exists "$PHASE_DIR/.phase-orchestration.json"
  assert_output --partial "removed"
}

# --- Preserves plan files ---

@test "preserves plan files" {
  touch "$PHASE_DIR/.dept-status-backend.json"
  echo '{"p":"02-01"}' > "$PHASE_DIR/02-01.plan.jsonl"
  run bash "$SUT" --phase-dir "$PHASE_DIR" --reason complete
  assert_success
  assert_file_exists "$PHASE_DIR/02-01.plan.jsonl"
}

# --- Preserves summary files ---

@test "preserves summary files" {
  touch "$PHASE_DIR/.dept-status-backend.json"
  echo '{"p":"02-01"}' > "$PHASE_DIR/02-01.summary.jsonl"
  run bash "$SUT" --phase-dir "$PHASE_DIR" --reason complete
  assert_success
  assert_file_exists "$PHASE_DIR/02-01.summary.jsonl"
}

# --- Empty dir ---

@test "handles empty dir gracefully" {
  run bash "$SUT" --phase-dir "$PHASE_DIR" --reason complete
  assert_success
  assert_output --partial "No coordination files"
}

# --- Nonexistent dir ---

@test "handles nonexistent dir gracefully" {
  run bash "$SUT" --phase-dir "$TEST_WORKDIR/nonexistent" --reason failure
  assert_success
  assert_output --partial "WARNING"
}

# --- Preserves .toon and .md files ---

@test "preserves .toon and .md files" {
  touch "$PHASE_DIR/.dept-status-backend.json"
  echo 'architecture content' > "$PHASE_DIR/architecture.toon"
  echo '# Decisions' > "$PHASE_DIR/decisions.md"
  run bash "$SUT" --phase-dir "$PHASE_DIR" --reason complete
  assert_success
  assert_file_exists "$PHASE_DIR/architecture.toon"
  assert_file_exists "$PHASE_DIR/decisions.md"
}

# --- Outputs count ---

@test "outputs count of removed files" {
  touch "$PHASE_DIR/.dept-status-backend.json"
  touch "$PHASE_DIR/.handoff-ux-complete"
  run bash "$SUT" --phase-dir "$PHASE_DIR" --reason timeout
  assert_success
  assert_output --partial "2 coordination files"
}
