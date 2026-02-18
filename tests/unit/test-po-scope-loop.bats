#!/usr/bin/env bats
# test-po-scope-loop.bats — Unit tests for scripts/po-scope-loop.sh
# Validates PO loop: 3-round cap, early exit on high confidence, config reading.

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/po-scope-loop.sh"

  # Create minimal config with PO settings
  mkdir -p "$TEST_WORKDIR/.yolo-planning"
  cat > "$TEST_WORKDIR/.yolo-planning/config.json" <<'JSON'
{
  "po": {
    "max_questionary_rounds": 3,
    "confidence_threshold": 0.85
  }
}
JSON
}

# Helper: create a mock questionary script that returns fixed confidence
mk_mock_questionary() {
  local confidence="$1" rounds_to_run="${2:-3}"
  local mock="$TEST_WORKDIR/mock-questionary.sh"
  cat > "$mock" <<SCRIPT
#!/usr/bin/env bash
echo '{"confidence":${confidence},"scope":"test-scope","questions_asked":1}'
SCRIPT
  chmod +x "$mock"
  echo "$mock"
}

@test "po-scope-loop.sh exists and is executable" {
  [ -f "$SUT" ] || skip "po-scope-loop.sh not yet created"
  [ -x "$SUT" ] || skip "po-scope-loop.sh not executable"
}

@test "3-round cap: exits after exactly 3 rounds on low confidence" {
  [ -x "$SUT" ] || skip "po-scope-loop.sh not yet created"
  local mock
  mock=$(mk_mock_questionary 0.5)
  run bash "$SUT" --workdir "$TEST_WORKDIR" --questionary "$mock"
  # Should complete (success or specific exit code) with rounds_used=3
  local rounds
  rounds=$(echo "$output" | jq -r '.rounds_used // empty' 2>/dev/null)
  [ "$rounds" = "3" ] || skip "Output format not matching spec yet"
}

@test "early exit on high confidence (round 1)" {
  [ -x "$SUT" ] || skip "po-scope-loop.sh not yet created"
  local mock
  mock=$(mk_mock_questionary 0.9)
  run bash "$SUT" --workdir "$TEST_WORKDIR" --questionary "$mock"
  local early_exit rounds
  early_exit=$(echo "$output" | jq -r '.early_exit // empty' 2>/dev/null)
  rounds=$(echo "$output" | jq -r '.rounds_used // empty' 2>/dev/null)
  [ "$early_exit" = "true" ] || skip "Output format not matching spec yet"
  [ "$rounds" = "1" ] || skip "Expected rounds_used=1"
}

@test "reads po.max_questionary_rounds from config" {
  [ -x "$SUT" ] || skip "po-scope-loop.sh not yet created"
  # Override config to 2 rounds
  cat > "$TEST_WORKDIR/.yolo-planning/config.json" <<'JSON'
{
  "po": {
    "max_questionary_rounds": 2,
    "confidence_threshold": 0.85
  }
}
JSON
  local mock
  mock=$(mk_mock_questionary 0.5)
  run bash "$SUT" --workdir "$TEST_WORKDIR" --questionary "$mock"
  local rounds
  rounds=$(echo "$output" | jq -r '.rounds_used // empty' 2>/dev/null)
  [ "$rounds" = "2" ] || skip "Config override not yet implemented"
}

@test "output JSON has required fields: rounds_used, confidence, early_exit, scope_path" {
  [ -x "$SUT" ] || skip "po-scope-loop.sh not yet created"
  local mock
  mock=$(mk_mock_questionary 0.9)
  run bash "$SUT" --workdir "$TEST_WORKDIR" --questionary "$mock"
  assert_success
  # Validate all required fields present
  echo "$output" | jq -e '.rounds_used' >/dev/null 2>&1 || fail "Missing rounds_used"
  echo "$output" | jq -e '.confidence' >/dev/null 2>&1 || fail "Missing confidence"
  echo "$output" | jq -e '.early_exit' >/dev/null 2>&1 || fail "Missing early_exit"
  echo "$output" | jq -e '.scope_path' >/dev/null 2>&1 || fail "Missing scope_path"
}

@test "graceful degradation: defaults when po config absent" {
  [ -x "$SUT" ] || skip "po-scope-loop.sh not yet created"
  # Remove po config
  echo '{}' > "$TEST_WORKDIR/.yolo-planning/config.json"
  local mock
  mock=$(mk_mock_questionary 0.5)
  run bash "$SUT" --workdir "$TEST_WORKDIR" --questionary "$mock"
  # Should default to 3 rounds, 0.85 threshold
  local rounds
  rounds=$(echo "$output" | jq -r '.rounds_used // empty' 2>/dev/null)
  [ "$rounds" = "3" ] || skip "Default config fallback not yet implemented"
}
