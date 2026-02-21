#!/usr/bin/env bats
# Migrated: session-start.sh -> yolo session-start
# CWD-sensitive: yes

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning/phases/01-test"
}

teardown() {
  teardown_temp_dir
}

@test "flag-deps: no warnings when all flags default false" {
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" session-start
  [ "$status" -eq 0 ]
  [[ "$output" != *"WARNING"* ]]
}

@test "flag-deps: warns when v2_hard_gates without v2_hard_contracts" {
  cd "$TEST_TEMP_DIR"
  jq '.v2_hard_gates = true | .v2_hard_contracts = false' .yolo-planning/config.json > .yolo-planning/config.json.tmp \
    && mv .yolo-planning/config.json.tmp .yolo-planning/config.json
  run "$YOLO_BIN" session-start
  [ "$status" -eq 0 ]
  [[ "$output" == *"v2_hard_gates requires v2_hard_contracts"* ]]
}

@test "flag-deps: no warning when both v2_hard_gates and v2_hard_contracts enabled" {
  cd "$TEST_TEMP_DIR"
  jq '.v2_hard_gates = true | .v2_hard_contracts = true' .yolo-planning/config.json > .yolo-planning/config.json.tmp \
    && mv .yolo-planning/config.json.tmp .yolo-planning/config.json
  run "$YOLO_BIN" session-start
  [ "$status" -eq 0 ]
  [[ "$output" != *"v2_hard_gates requires v2_hard_contracts"* ]]
}

@test "flag-deps: warns when v3_event_recovery without v3_event_log" {
  cd "$TEST_TEMP_DIR"
  jq '.v3_event_recovery = true | .v3_event_log = false' .yolo-planning/config.json > .yolo-planning/config.json.tmp \
    && mv .yolo-planning/config.json.tmp .yolo-planning/config.json
  run "$YOLO_BIN" session-start
  [ "$status" -eq 0 ]
  [[ "$output" == *"v3_event_recovery requires v3_event_log"* ]]
}

@test "flag-deps: warns when v2_two_phase_completion without v3_event_log" {
  cd "$TEST_TEMP_DIR"
  jq '.v2_two_phase_completion = true | .v3_event_log = false' .yolo-planning/config.json > .yolo-planning/config.json.tmp \
    && mv .yolo-planning/config.json.tmp .yolo-planning/config.json
  run "$YOLO_BIN" session-start
  [ "$status" -eq 0 ]
  [[ "$output" == *"v2_two_phase_completion requires v3_event_log"* ]]
}

@test "flag-deps: multiple warnings when multiple deps unsatisfied" {
  cd "$TEST_TEMP_DIR"
  jq '.v2_hard_gates = true | .v2_hard_contracts = false | .v3_event_recovery = true | .v3_event_log = false' \
    .yolo-planning/config.json > .yolo-planning/config.json.tmp \
    && mv .yolo-planning/config.json.tmp .yolo-planning/config.json
  run "$YOLO_BIN" session-start
  [ "$status" -eq 0 ]
  [[ "$output" == *"v2_hard_gates requires v2_hard_contracts"* ]]
  [[ "$output" == *"v3_event_recovery requires v3_event_log"* ]]
}
