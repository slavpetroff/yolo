#!/usr/bin/env bats
# test-integration-delivery-flow.bats — Integration smoke tests for delivery pipeline
# Confirms cross-component compatibility between integration-gate.sh,
# validate-config.sh, and compile-context.sh.

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  mk_test_workdir

  PHASE_DIR="$TEST_WORKDIR/.yolo-planning/phases/05-test"
  mkdir -p "$PHASE_DIR"
  mkdir -p "$TEST_WORKDIR/.yolo-planning/codebase"

  # Minimal ROADMAP.md for compile-context
  cat > "$TEST_WORKDIR/.yolo-planning/ROADMAP.md" <<'EOF'
# Roadmap
## Phase 5: Delivery Pipeline
**Goal:** Integration delivery smoke tests
EOF
  echo '{"conventions":[]}' > "$TEST_WORKDIR/.yolo-planning/conventions.json"
}

# --- Config defaults ---

@test "validate-config.sh accepts full config with all Phase 5 keys" {
  cat > "$TEST_WORKDIR/config.json" <<'EOF'
{
  "integration_gate": {
    "enabled": true,
    "timeout_seconds": 300,
    "checks": {"api": true, "design": true, "tests": true},
    "retry_on_fail": false
  },
  "po": {
    "enabled": true,
    "default_rejection": "patch"
  },
  "delivery": {
    "mode": "auto",
    "present_to_user": true
  },
  "qa_gates": {
    "post_task": true,
    "post_plan": true,
    "post_phase": true,
    "timeout_seconds": 120,
    "failure_threshold": "critical"
  }
}
EOF
  run bash "$SCRIPTS_DIR/validate-config.sh" "$TEST_WORKDIR/config.json"
  assert_success
  echo "$output" | jq -e '.valid == true'
}

# --- Integration gate JSON schema ---

@test "integration-gate.sh JSON output parses correctly with jq" {
  cat > "$TEST_WORKDIR/config.json" <<'EOF'
{"departments":{"backend":true,"frontend":false,"uiux":false}}
EOF
  echo '{"dept":"backend","status":"complete","step":"signoff"}' > "$PHASE_DIR/.dept-status-backend.json"
  touch "$PHASE_DIR/.handoff-backend-complete"

  run bash "$SCRIPTS_DIR/integration-gate.sh" --phase-dir "$PHASE_DIR" --config "$TEST_WORKDIR/config.json"
  assert_success

  # Verify all fields parse and have expected types
  echo "$output" | jq -e '.gate | type == "string"'
  echo "$output" | jq -e '.departments | type == "object"'
  echo "$output" | jq -e '.cross_checks | type == "object"'
  echo "$output" | jq -e '.timeout_remaining | type == "number"'
  echo "$output" | jq -e '.dt | type == "string"'
}

# --- Compile-context integration-gate role ---

@test "compile-context.sh integration-gate role exits 0 with minimal phase dir" {
  run bash -c "cd '$TEST_WORKDIR' && bash '$SCRIPTS_DIR/compile-context.sh' '05' 'integration-gate' '$TEST_WORKDIR/.yolo-planning/phases'"
  assert_success
  assert [ -f "$PHASE_DIR/.ctx-integration-gate.toon" ]
}

# --- Integration gate error handling ---

@test "integration-gate.sh exits 1 when phase-dir does not exist" {
  cat > "$TEST_WORKDIR/config.json" <<'EOF'
{"departments":{"backend":true}}
EOF
  run bash "$SCRIPTS_DIR/integration-gate.sh" --phase-dir "/nonexistent/phase-dir" --config "$TEST_WORKDIR/config.json"
  assert_failure
}

# --- Config validation rejects bad Phase 5 config ---

@test "validate-config.sh rejects config with invalid integration_gate + delivery combo" {
  cat > "$TEST_WORKDIR/config.json" <<'EOF'
{
  "integration_gate": {
    "enabled": "yes",
    "timeout_seconds": 10
  },
  "delivery": {
    "mode": "hybrid"
  }
}
EOF
  run bash "$SCRIPTS_DIR/validate-config.sh" "$TEST_WORKDIR/config.json"
  assert_failure
  echo "$output" | jq -e '.valid == false'
  # Should have multiple errors
  echo "$output" | jq -e '(.errors | length) >= 2'
}

# --- Compile-context produces valid toon for gate consumption ---

@test "compile-context integration-gate toon is non-empty with fixtures" {
  echo '{"endpoint":"/api/users","status":"agreed"}' > "$PHASE_DIR/api-contracts.jsonl"
  echo '{"plan":"05-01","dept":"backend","ps":10,"fl":0}' > "$PHASE_DIR/test-results.jsonl"
  touch "$PHASE_DIR/.handoff-backend-complete"

  run bash -c "cd '$TEST_WORKDIR' && bash '$SCRIPTS_DIR/compile-context.sh' '05' 'integration-gate' '$TEST_WORKDIR/.yolo-planning/phases'"
  assert_success

  local size
  size=$(wc -c < "$PHASE_DIR/.ctx-integration-gate.toon")
  [ "$size" -gt 0 ]
}
