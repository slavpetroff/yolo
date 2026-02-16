#!/usr/bin/env bats
# dept-status.bats — Unit tests for scripts/dept-status.sh
# Atomic read/write of per-department status files with flock/mkdir locking.

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/dept-status.sh"
  # Create phase dir for all tests
  PHASE_DIR="$TEST_WORKDIR/.yolo-planning/phases/02-test"
  mkdir -p "$PHASE_DIR"
}

# Helper: run dept-status with args
run_status() {
  run bash "$SUT" "$@"
}

# --- Write action ---

@test "write creates .dept-status-backend.json" {
  run_status --dept backend --phase-dir "$PHASE_DIR" --action write --status running --step planning
  assert_success
  assert_file_exists "$PHASE_DIR/.dept-status-backend.json"

  local dept status step
  dept=$(jq -r '.dept' "$PHASE_DIR/.dept-status-backend.json")
  status=$(jq -r '.status' "$PHASE_DIR/.dept-status-backend.json")
  step=$(jq -r '.step' "$PHASE_DIR/.dept-status-backend.json")

  assert_equal "$dept" "backend"
  assert_equal "$status" "running"
  assert_equal "$step" "planning"
}

# --- Read action ---

@test "read returns JSON to stdout" {
  # First write
  run_status --dept backend --phase-dir "$PHASE_DIR" --action write --status running --step planning
  assert_success

  # Then read
  run_status --dept backend --phase-dir "$PHASE_DIR" --action read
  assert_success

  # Output is valid JSON
  echo "$output" | jq . >/dev/null 2>&1
  assert_equal "$?" "0"

  local dept
  dept=$(echo "$output" | jq -r '.dept')
  assert_equal "$dept" "backend"
}

# --- Read missing file ---

@test "read exits 1 when file missing" {
  run_status --dept frontend --phase-dir "$PHASE_DIR" --action read
  assert_failure
  assert_output --partial "not found"
}

# --- started_at preservation ---

@test "started_at set on first write, preserved on update" {
  # First write
  run_status --dept backend --phase-dir "$PHASE_DIR" --action write --status pending --step critique
  assert_success
  local first_started
  first_started=$(jq -r '.started_at' "$PHASE_DIR/.dept-status-backend.json")

  sleep 1

  # Second write
  run_status --dept backend --phase-dir "$PHASE_DIR" --action write --status running --step planning
  assert_success
  local second_started
  second_started=$(jq -r '.started_at' "$PHASE_DIR/.dept-status-backend.json")

  assert_equal "$first_started" "$second_started"
}

# --- updated_at changes ---

@test "updated_at changes on every write" {
  # First write
  run_status --dept backend --phase-dir "$PHASE_DIR" --action write --status pending --step critique
  assert_success
  local first_updated
  first_updated=$(jq -r '.updated_at' "$PHASE_DIR/.dept-status-backend.json")

  sleep 1

  # Second write
  run_status --dept backend --phase-dir "$PHASE_DIR" --action write --status running --step planning
  assert_success
  local second_updated
  second_updated=$(jq -r '.updated_at' "$PHASE_DIR/.dept-status-backend.json")

  # updated_at should have changed
  [ "$first_updated" != "$second_updated" ]
}

# --- Plans tracking ---

@test "plans-complete and plans-total tracked" {
  run_status --dept backend --phase-dir "$PHASE_DIR" --action write --status running --step implementation --plans-complete 2 --plans-total 3
  assert_success

  local pc pt
  pc=$(jq '.plans_complete' "$PHASE_DIR/.dept-status-backend.json")
  pt=$(jq '.plans_total' "$PHASE_DIR/.dept-status-backend.json")

  assert_equal "$pc" "2"
  assert_equal "$pt" "3"
}

# --- Error field ---

@test "error field stored on write" {
  run_status --dept backend --phase-dir "$PHASE_DIR" --action write --status failed --step implementation --error "Build failed: missing dependency"
  assert_success

  local err
  err=$(jq -r '.error' "$PHASE_DIR/.dept-status-backend.json")
  assert_equal "$err" "Build failed: missing dependency"
}

# --- Missing required args ---

@test "missing required args exits 1" {
  run_status --dept backend
  assert_failure

  run_status --action write
  assert_failure
}

# --- Write without --status ---

@test "write action without --status exits 1" {
  run_status --dept backend --phase-dir "$PHASE_DIR" --action write --step planning
  assert_failure
  assert_output --partial "--status required"
}

# --- Separate dept files ---

@test "different departments create separate files" {
  run_status --dept backend --phase-dir "$PHASE_DIR" --action write --status running --step planning
  assert_success
  run_status --dept frontend --phase-dir "$PHASE_DIR" --action write --status pending --step critique
  assert_success

  assert_file_exists "$PHASE_DIR/.dept-status-backend.json"
  assert_file_exists "$PHASE_DIR/.dept-status-frontend.json"

  local be_status fe_status
  be_status=$(jq -r '.status' "$PHASE_DIR/.dept-status-backend.json")
  fe_status=$(jq -r '.status' "$PHASE_DIR/.dept-status-frontend.json")

  assert_equal "$be_status" "running"
  assert_equal "$fe_status" "pending"
}
