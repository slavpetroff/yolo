#!/usr/bin/env bats
# dept-gate.bats — Unit tests for scripts/dept-gate.sh
# Handoff gate validation with polling and timeout for multi-department coordination.

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/dept-gate.sh"
  PHASE_DIR="$TEST_WORKDIR/.yolo-planning/phases/02-test"
  mkdir -p "$PHASE_DIR"
}

# Helper: create all UX handoff artifacts
mk_ux_handoff_artifacts() {
  touch "$PHASE_DIR/.handoff-ux-complete"
  echo '{"status":"complete","dept":"uiux"}' > "$PHASE_DIR/design-handoff.jsonl"
  echo '{"token":"primary","value":"#000"}' > "$PHASE_DIR/design-tokens.jsonl"
  echo '{"component":"Button","status":"ready"}' > "$PHASE_DIR/component-specs.jsonl"
}

# Helper: create dept-status complete file
mk_dept_complete() {
  local dept="$1"
  echo "{\"dept\":\"$dept\",\"status\":\"complete\",\"step\":\"signoff\"}" > "$PHASE_DIR/.dept-status-${dept}.json"
}

# --- UX-complete gate ---

@test "ux-complete gate passes with all artifacts" {
  mk_ux_handoff_artifacts
  run bash "$SUT" --gate ux-complete --phase-dir "$PHASE_DIR" --no-poll
  assert_success
}

@test "ux-complete gate fails without sentinel file" {
  # Create artifacts but NOT the sentinel
  echo '{"status":"complete"}' > "$PHASE_DIR/design-handoff.jsonl"
  echo '{"token":"primary"}' > "$PHASE_DIR/design-tokens.jsonl"
  echo '{"component":"Button"}' > "$PHASE_DIR/component-specs.jsonl"
  run bash "$SUT" --gate ux-complete --phase-dir "$PHASE_DIR" --no-poll
  assert_failure
}

@test "ux-complete gate fails without design-handoff.jsonl" {
  touch "$PHASE_DIR/.handoff-ux-complete"
  echo '{"token":"primary"}' > "$PHASE_DIR/design-tokens.jsonl"
  echo '{"component":"Button"}' > "$PHASE_DIR/component-specs.jsonl"
  run bash "$SUT" --gate ux-complete --phase-dir "$PHASE_DIR" --no-poll
  assert_failure
}

# --- All-depts gate ---

@test "all-depts gate passes when all complete" {
  mk_dept_complete backend
  mk_dept_complete frontend
  echo '{"p":"02-01","n":"test","s":"complete"}' > "$PHASE_DIR/02-01.summary.jsonl"
  run bash "$SUT" --gate all-depts --phase-dir "$PHASE_DIR" --no-poll
  assert_success
}

@test "all-depts gate fails when one dept incomplete" {
  mk_dept_complete backend
  echo '{"dept":"frontend","status":"running","step":"planning"}' > "$PHASE_DIR/.dept-status-frontend.json"
  echo '{"p":"02-01","n":"test","s":"complete"}' > "$PHASE_DIR/02-01.summary.jsonl"
  run bash "$SUT" --gate all-depts --phase-dir "$PHASE_DIR" --no-poll
  assert_failure
}

# --- Timeout ---

@test "timeout exits 1 with TIMEOUT message" {
  run bash "$SUT" --gate ux-complete --phase-dir "$PHASE_DIR" --timeout 1 --poll-interval 0.3
  assert_failure
  assert_output --partial "TIMEOUT"
}

# --- API-contract gate ---

@test "api-contract gate passes with agreed entry" {
  echo '{"endpoint":"/api/users","status":"agreed"}' > "$PHASE_DIR/api-contracts.jsonl"
  run bash "$SUT" --gate api-contract --phase-dir "$PHASE_DIR" --no-poll
  assert_success
}

@test "api-contract gate fails with only proposed entries" {
  echo '{"endpoint":"/api/users","status":"proposed"}' > "$PHASE_DIR/api-contracts.jsonl"
  run bash "$SUT" --gate api-contract --phase-dir "$PHASE_DIR" --no-poll
  assert_failure
}

# --- Unknown gate ---

@test "unknown gate name exits with error" {
  run bash "$SUT" --gate nonexistent --phase-dir "$PHASE_DIR" --no-poll
  assert_failure
  assert_output --partial "Unknown gate"
}
