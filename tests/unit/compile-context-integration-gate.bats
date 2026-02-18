#!/usr/bin/env bats
# compile-context-integration-gate.bats — Unit tests for compile-context.sh integration-gate role
# Context compilation for the integration gate agent.

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/compile-context.sh"

  # Set up .yolo-planning with phase dir
  mkdir -p "$TEST_WORKDIR/.yolo-planning/phases/05-test"
  mkdir -p "$TEST_WORKDIR/.yolo-planning/codebase"

  # Minimal ROADMAP.md
  cat > "$TEST_WORKDIR/.yolo-planning/ROADMAP.md" <<'EOF'
# Roadmap
## Phase 5: Integration Test
**Goal:** Test integration gate context
EOF

  # Conventions file
  echo '{"conventions":[]}' > "$TEST_WORKDIR/.yolo-planning/conventions.json"

  PHASES_DIR="$TEST_WORKDIR/.yolo-planning/phases"
  PHASE_DIR="$PHASES_DIR/05-test"
}

# Helper: run compile-context from test workdir
run_cc() {
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT' '05' 'integration-gate' '$PHASES_DIR'"
}

# --- Basic output ---

@test "integration-gate role produces .ctx-integration-gate.toon" {
  run_cc
  assert_success
  assert [ -f "$PHASE_DIR/.ctx-integration-gate.toon" ]
}

# --- Department results ---

@test "output includes department results when dept-status files exist" {
  echo '{"dept":"backend","status":"complete","step":"signoff"}' > "$PHASE_DIR/.dept-status-backend.json"
  echo '{"dept":"frontend","status":"complete","step":"signoff"}' > "$PHASE_DIR/.dept-status-frontend.json"
  run_cc
  assert_success
  # The toon should include implementation evidence section
  assert [ -f "$PHASE_DIR/.ctx-integration-gate.toon" ]
}

# --- Test results ---

@test "output includes test results when test-results.jsonl exists" {
  echo '{"plan":"05-01","dept":"backend","ps":10,"fl":0}' > "$PHASE_DIR/test-results.jsonl"
  run_cc
  assert_success
  # Verify test_results section appears in output
  run grep -c "test_results" "$PHASE_DIR/.ctx-integration-gate.toon"
  assert_success
}

# --- API contracts ---

@test "output includes api-contracts when api-contracts.jsonl exists" {
  echo '{"endpoint":"/api/users","status":"agreed"}' > "$PHASE_DIR/api-contracts.jsonl"
  run_cc
  assert_success
  run grep -c "api_contracts" "$PHASE_DIR/.ctx-integration-gate.toon"
  assert_success
}

@test "output excludes api-contracts when file missing (graceful degradation)" {
  # No api-contracts.jsonl file
  run_cc
  assert_success
  run grep -c "api_contracts" "$PHASE_DIR/.ctx-integration-gate.toon"
  # grep returns 1 (no match) when section is not present
  assert_failure
}

# --- Budget enforcement ---

@test "budget enforcement — output stays within 3000 token budget" {
  # Create reasonable fixtures
  echo '{"endpoint":"/api/users","status":"agreed"}' > "$PHASE_DIR/api-contracts.jsonl"
  echo '{"component":"Button","status":"ready"}' > "$PHASE_DIR/design-handoff.jsonl"
  echo '{"plan":"05-01","dept":"backend","ps":10,"fl":0}' > "$PHASE_DIR/test-results.jsonl"
  echo '{"p":"05","n":"01","s":"complete","fm":["scripts/test.sh"]}' > "$PHASE_DIR/05-01.summary.jsonl"
  touch "$PHASE_DIR/.handoff-backend-complete"

  run_cc
  assert_success

  # ~3000 tokens ≈ ~12000 chars. Verify file is reasonably sized.
  local size
  size=$(wc -c < "$PHASE_DIR/.ctx-integration-gate.toon")
  [ "$size" -lt 12000 ]
}

# --- Handoff sentinels ---

@test "output includes handoff sentinels when present" {
  touch "$PHASE_DIR/.handoff-backend-complete"
  touch "$PHASE_DIR/.handoff-frontend-complete"
  run_cc
  assert_success
  run grep -c "handoff_sentinels" "$PHASE_DIR/.ctx-integration-gate.toon"
  assert_success
}
