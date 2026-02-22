#!/usr/bin/env bats
# Integration tests for feature-flag-gated code paths.
#
# Tests that v2_hard_gates and v3_schema_validation flags actually change
# runtime behavior -- not just dependency warnings (covered by
# flag-dependency-validation.bats).
#
# v2_hard_gates: tested via `yolo hard-gate` CLI command
# v3_schema_validation: tested via session-start config cache export

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning/phases/01-test"
}

teardown() {
  teardown_temp_dir
}

# ---------------------------------------------------------------------------
# Task 1: v2_hard_gates integration tests
# ---------------------------------------------------------------------------
# When v2_hard_gates=false, hard-gate skips all evaluation and returns
# {"result":"skip","evidence":"v2_hard_gates=false"} with exit 0.
# When v2_hard_gates=true, hard-gate evaluates the gate and returns
# pass (exit 0) or fail (exit 2) depending on conditions.

@test "v2_hard_gates disabled: hard-gate skips evaluation (exit 0, result=skip)" {
  cd "$TEST_TEMP_DIR"
  # Default config has v2_hard_gates=false
  run "$YOLO_BIN" hard-gate contract_compliance 01 01 1 nonexistent.json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result == "skip"'
  echo "$output" | jq -e '.evidence == "v2_hard_gates=false"'
}

@test "v2_hard_gates disabled: any gate type returns skip" {
  cd "$TEST_TEMP_DIR"
  for gate_type in contract_compliance protected_file required_checks commit_hygiene artifact_persistence verification_threshold forbidden_commands; do
    run "$YOLO_BIN" hard-gate "$gate_type" 01 01 1 dummy.json
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.result == "skip"'
  done
}

@test "v2_hard_gates enabled: contract_compliance fails on missing contract file (exit 2)" {
  cd "$TEST_TEMP_DIR"
  jq '.v2_hard_gates = true | .v2_hard_contracts = true' .yolo-planning/config.json > .yolo-planning/config.json.tmp \
    && mv .yolo-planning/config.json.tmp .yolo-planning/config.json
  run "$YOLO_BIN" hard-gate contract_compliance 01 01 1 nonexistent.json
  [ "$status" -eq 2 ]
  echo "$output" | jq -e '.result == "fail"'
  echo "$output" | jq -e '.evidence == "contract file not found"'
}

@test "v2_hard_gates enabled: contract_compliance passes with valid contract" {
  cd "$TEST_TEMP_DIR"
  jq '.v2_hard_gates = true | .v2_hard_contracts = true' .yolo-planning/config.json > .yolo-planning/config.json.tmp \
    && mv .yolo-planning/config.json.tmp .yolo-planning/config.json

  # Build a valid contract with correct hash.
  # Rust uses serde_json::to_string_pretty which sorts keys alphabetically,
  # so we use jq -S to match that ordering for the hash computation.
  local contract_path="$TEST_TEMP_DIR/contract.json"
  local base_json='{"task_count":3,"forbidden_paths":[]}'
  local pretty
  pretty=$(echo "$base_json" | jq -S '.')
  local hash
  hash=$(printf '%s\n' "$pretty" | shasum -a 256 | cut -d' ' -f1)
  echo "$base_json" | jq -S --arg h "$hash" '. + {contract_hash: $h}' > "$contract_path"

  run "$YOLO_BIN" hard-gate contract_compliance 01 01 1 "$contract_path"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result == "pass"'
}

@test "v2_hard_gates enabled: contract_compliance fails on task out of range" {
  cd "$TEST_TEMP_DIR"
  jq '.v2_hard_gates = true | .v2_hard_contracts = true' .yolo-planning/config.json > .yolo-planning/config.json.tmp \
    && mv .yolo-planning/config.json.tmp .yolo-planning/config.json

  # Contract with task_count=2, but we request task 5.
  # Use jq -S to sort keys alphabetically (matches Rust serde_json::to_string_pretty).
  local contract_path="$TEST_TEMP_DIR/contract.json"
  local base_json='{"task_count":2,"forbidden_paths":[]}'
  local pretty
  pretty=$(echo "$base_json" | jq -S '.')
  local hash
  hash=$(printf '%s\n' "$pretty" | shasum -a 256 | cut -d' ' -f1)
  echo "$base_json" | jq -S --arg h "$hash" '. + {contract_hash: $h}' > "$contract_path"

  run "$YOLO_BIN" hard-gate contract_compliance 01 01 5 "$contract_path"
  [ "$status" -eq 2 ]
  echo "$output" | jq -e '.result == "fail"'
  echo "$output" | jq -e '.evidence | contains("outside range")'
}

@test "v2_hard_gates enabled: artifact_persistence fails on missing SUMMARY" {
  cd "$TEST_TEMP_DIR"
  jq '.v2_hard_gates = true | .v2_hard_contracts = true' .yolo-planning/config.json > .yolo-planning/config.json.tmp \
    && mv .yolo-planning/config.json.tmp .yolo-planning/config.json

  # Create plan 1 without SUMMARY, then check gate for plan 2
  touch "$TEST_TEMP_DIR/.yolo-planning/phases/01-test/1-PLAN.md"
  touch "$TEST_TEMP_DIR/.yolo-planning/phases/01-test/2-PLAN.md"
  # Missing: 1-SUMMARY.md

  run "$YOLO_BIN" hard-gate artifact_persistence 01 2 0 dummy.json
  [ "$status" -eq 2 ]
  echo "$output" | jq -e '.result == "fail"'
  echo "$output" | jq -e '.evidence | contains("plan-1")'
}

@test "v2_hard_gates enabled: artifact_persistence passes when SUMMARY exists" {
  cd "$TEST_TEMP_DIR"
  jq '.v2_hard_gates = true | .v2_hard_contracts = true' .yolo-planning/config.json > .yolo-planning/config.json.tmp \
    && mv .yolo-planning/config.json.tmp .yolo-planning/config.json

  touch "$TEST_TEMP_DIR/.yolo-planning/phases/01-test/1-PLAN.md"
  touch "$TEST_TEMP_DIR/.yolo-planning/phases/01-test/1-SUMMARY.md"
  touch "$TEST_TEMP_DIR/.yolo-planning/phases/01-test/2-PLAN.md"

  run "$YOLO_BIN" hard-gate artifact_persistence 01 2 0 dummy.json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result == "pass"'
}

@test "v2_hard_gates enabled: unknown gate type returns fail (exit 2)" {
  cd "$TEST_TEMP_DIR"
  jq '.v2_hard_gates = true | .v2_hard_contracts = true' .yolo-planning/config.json > .yolo-planning/config.json.tmp \
    && mv .yolo-planning/config.json.tmp .yolo-planning/config.json

  run "$YOLO_BIN" hard-gate totally_bogus_gate 01 01 1 dummy.json
  [ "$status" -eq 2 ]
  echo "$output" | jq -e '.result == "fail"'
  echo "$output" | jq -e '.evidence | contains("unknown gate type")'
}

@test "v2_hard_gates enabled vs disabled: same inputs produce different results" {
  cd "$TEST_TEMP_DIR"

  # Disabled: skip
  run "$YOLO_BIN" hard-gate contract_compliance 01 01 1 nonexistent.json
  [ "$status" -eq 0 ]
  local disabled_result
  disabled_result=$(echo "$output" | jq -r '.result')
  [ "$disabled_result" = "skip" ]

  # Enable the flag
  jq '.v2_hard_gates = true | .v2_hard_contracts = true' .yolo-planning/config.json > .yolo-planning/config.json.tmp \
    && mv .yolo-planning/config.json.tmp .yolo-planning/config.json

  # Enabled: fail (contract file missing)
  run "$YOLO_BIN" hard-gate contract_compliance 01 01 1 nonexistent.json
  [ "$status" -eq 2 ]
  local enabled_result
  enabled_result=$(echo "$output" | jq -r '.result')
  [ "$enabled_result" = "fail" ]

  # Confirm the behavioral difference
  [ "$disabled_result" != "$enabled_result" ]
}

# ---------------------------------------------------------------------------
# Task 2: v3_schema_validation integration tests
# ---------------------------------------------------------------------------
# validate_schema.rs is gated by v3_schema_validation but is not wired into
# any CLI command -- it is a hook module only. We test the observable effect:
# session-start writes the flag value into the config cache at
# /tmp/yolo-config-cache-{uid}, which downstream hooks read.

@test "v3_schema_validation disabled: config cache exports false" {
  cd "$TEST_TEMP_DIR"
  # Default config has v3_schema_validation=false
  run "$YOLO_BIN" session-start
  [ "$status" -eq 0 ]

  local uid
  uid=$(id -u)
  local cache_file="/tmp/yolo-config-cache-${uid}"
  [ -f "$cache_file" ]
  run grep "YOLO_V3_SCHEMA_VALIDATION" "$cache_file"
  [ "$status" -eq 0 ]
  [[ "$output" == *"YOLO_V3_SCHEMA_VALIDATION=false"* ]]
}

@test "v3_schema_validation enabled: config cache exports true" {
  cd "$TEST_TEMP_DIR"
  jq '.v3_schema_validation = true' .yolo-planning/config.json > .yolo-planning/config.json.tmp \
    && mv .yolo-planning/config.json.tmp .yolo-planning/config.json

  run "$YOLO_BIN" session-start
  [ "$status" -eq 0 ]

  local uid
  uid=$(id -u)
  local cache_file="/tmp/yolo-config-cache-${uid}"
  [ -f "$cache_file" ]
  run grep "YOLO_V3_SCHEMA_VALIDATION" "$cache_file"
  [ "$status" -eq 0 ]
  [[ "$output" == *"YOLO_V3_SCHEMA_VALIDATION=true"* ]]
}

@test "v3_schema_validation toggle: changing flag updates cache on next session-start" {
  cd "$TEST_TEMP_DIR"
  local uid
  uid=$(id -u)
  local cache_file="/tmp/yolo-config-cache-${uid}"

  # Start with false
  run "$YOLO_BIN" session-start
  [ "$status" -eq 0 ]
  run grep "YOLO_V3_SCHEMA_VALIDATION" "$cache_file"
  [[ "$output" == *"false"* ]]

  # Toggle to true
  jq '.v3_schema_validation = true' .yolo-planning/config.json > .yolo-planning/config.json.tmp \
    && mv .yolo-planning/config.json.tmp .yolo-planning/config.json

  run "$YOLO_BIN" session-start
  [ "$status" -eq 0 ]
  run grep "YOLO_V3_SCHEMA_VALIDATION" "$cache_file"
  [[ "$output" == *"true"* ]]
}

@test "v3_schema_validation: all v3 flags exported to config cache" {
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" session-start
  [ "$status" -eq 0 ]

  local uid
  uid=$(id -u)
  local cache_file="/tmp/yolo-config-cache-${uid}"
  [ -f "$cache_file" ]

  # Verify all v3 flags are present in the cache
  for flag in V3_DELTA_CONTEXT V3_CONTEXT_CACHE V3_PLAN_RESEARCH_PERSIST \
              V3_METRICS V3_CONTRACT_LITE V3_LOCK_LITE V3_VALIDATION_GATES \
              V3_SMART_ROUTING V3_EVENT_LOG V3_SCHEMA_VALIDATION \
              V3_SNAPSHOT_RESUME V3_EVENT_RECOVERY V3_MONOREPO_ROUTING; do
    run grep "YOLO_${flag}=" "$cache_file"
    [ "$status" -eq 0 ]
  done
}

@test "v2_hard_gates: flag exported to config cache" {
  cd "$TEST_TEMP_DIR"
  jq '.v2_hard_gates = true | .v2_hard_contracts = true' .yolo-planning/config.json > .yolo-planning/config.json.tmp \
    && mv .yolo-planning/config.json.tmp .yolo-planning/config.json

  run "$YOLO_BIN" session-start
  [ "$status" -eq 0 ]

  local uid
  uid=$(id -u)
  local cache_file="/tmp/yolo-config-cache-${uid}"
  [ -f "$cache_file" ]
  run grep "YOLO_V2_HARD_GATES" "$cache_file"
  [ "$status" -eq 0 ]
  [[ "$output" == *"YOLO_V2_HARD_GATES=true"* ]]
}
