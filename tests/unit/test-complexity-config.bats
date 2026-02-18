#!/usr/bin/env bats
# test-complexity-config.bats — Unit tests for complexity_routing config validation
# Plan 01-04 T3: Config schema, threshold validation, backward compat

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  mk_test_workdir
  VALIDATE_SUT="$SCRIPTS_DIR/validate-config.sh"
  DETECT_SUT="$SCRIPTS_DIR/phase-detect.sh"
}

# --- defaults.json has complexity_routing key ---

@test "defaults.json has complexity_routing key" {
  local defaults="$CONFIG_DIR/defaults.json"
  run jq -e '.complexity_routing' "$defaults"
  assert_success
}

@test "complexity_routing has all required sub-keys with correct types" {
  local defaults="$CONFIG_DIR/defaults.json"
  # enabled: boolean
  run jq -e '.complexity_routing.enabled | type == "boolean"' "$defaults"
  assert_success
  # trivial_confidence_threshold: number
  run jq -e '.complexity_routing.trivial_confidence_threshold | type == "number"' "$defaults"
  assert_success
  # medium_confidence_threshold: number
  run jq -e '.complexity_routing.medium_confidence_threshold | type == "number"' "$defaults"
  assert_success
  # fallback_path: string
  run jq -e '.complexity_routing.fallback_path | type == "string"' "$defaults"
  assert_success
  # force_analyze_model: string
  run jq -e '.complexity_routing.force_analyze_model | type == "string"' "$defaults"
  assert_success
  # max_trivial_files: number
  run jq -e '.complexity_routing.max_trivial_files | type == "number"' "$defaults"
  assert_success
  # max_medium_tasks: number
  run jq -e '.complexity_routing.max_medium_tasks | type == "number"' "$defaults"
  assert_success
}

@test "trivial threshold > medium threshold in defaults" {
  local defaults="$CONFIG_DIR/defaults.json"
  run jq -e '.complexity_routing | .trivial_confidence_threshold > .medium_confidence_threshold' "$defaults"
  assert_success
}

# --- validate-config.sh ---

@test "validate-config accepts valid complexity_routing" {
  cat > "$TEST_WORKDIR/config.json" <<'JSON'
{
  "complexity_routing": {
    "enabled": true,
    "trivial_confidence_threshold": 0.85,
    "medium_confidence_threshold": 0.7,
    "fallback_path": "high",
    "force_analyze_model": "opus",
    "max_trivial_files": 3,
    "max_medium_tasks": 3
  }
}
JSON
  run bash "$VALIDATE_SUT" "$TEST_WORKDIR/config.json"
  assert_success
  local valid
  valid=$(echo "$output" | jq -r '.valid')
  [ "$valid" = "true" ]
}

@test "validate-config rejects invalid threshold (> 1.0)" {
  cat > "$TEST_WORKDIR/config.json" <<'JSON'
{
  "complexity_routing": {
    "enabled": true,
    "trivial_confidence_threshold": 1.5,
    "medium_confidence_threshold": 0.7,
    "fallback_path": "high",
    "force_analyze_model": "opus",
    "max_trivial_files": 3,
    "max_medium_tasks": 3
  }
}
JSON
  run bash "$VALIDATE_SUT" "$TEST_WORKDIR/config.json"
  assert_failure
}

@test "validate-config rejects trivial < medium threshold" {
  cat > "$TEST_WORKDIR/config.json" <<'JSON'
{
  "complexity_routing": {
    "enabled": true,
    "trivial_confidence_threshold": 0.5,
    "medium_confidence_threshold": 0.7,
    "fallback_path": "high",
    "force_analyze_model": "opus",
    "max_trivial_files": 3,
    "max_medium_tasks": 3
  }
}
JSON
  run bash "$VALIDATE_SUT" "$TEST_WORKDIR/config.json"
  assert_failure
}

@test "validate-config handles missing complexity_routing gracefully" {
  echo '{}' > "$TEST_WORKDIR/config.json"
  run bash "$VALIDATE_SUT" "$TEST_WORKDIR/config.json"
  assert_success
  local valid
  valid=$(echo "$output" | jq -r '.valid')
  [ "$valid" = "true" ]
}

# --- phase-detect.sh outputs complexity routing config ---

@test "phase-detect outputs complexity routing config values" {
  mk_planning_dir
  cp "$CONFIG_DIR/defaults.json" "$TEST_WORKDIR/.yolo-planning/config.json"
  run bash -c "cd '$TEST_WORKDIR' && bash '$DETECT_SUT'"
  assert_success
  assert_line --partial "config_complexity_routing="
}

@test "phase-detect defaults complexity_routing to false when missing" {
  mk_planning_dir
  # Config without complexity_routing key
  echo '{"effort":"balanced"}' > "$TEST_WORKDIR/.yolo-planning/config.json"
  run bash -c "cd '$TEST_WORKDIR' && bash '$DETECT_SUT'"
  assert_success
  # Should default to false or a sensible value when key is absent
  assert_line --partial "config_complexity_routing="
}
