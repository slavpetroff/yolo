#!/usr/bin/env bats
# Migrated: rollout-stage.sh -> yolo rollout-stage (also: yolo rollout)
# CWD-sensitive: yes
# Note: Rust CLI uses named stages (canary/partial/full) instead of numbered stages.
# The advance command does not support --stage=N or --dry-run flags.

load test_helper

setup() {
  setup_temp_dir
  create_test_config
}

teardown() {
  teardown_temp_dir
}

create_event_log() {
  local count="$1"
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning/.events"
  > "$TEST_TEMP_DIR/.yolo-planning/.events/event-log.jsonl"
  for i in $(seq 1 "$count"); do
    echo "{\"ts\":\"2026-01-0${i}T00:00:00Z\",\"event_id\":\"evt-${i}\",\"event\":\"phase_end\",\"phase\":${i}}" >> "$TEST_TEMP_DIR/.yolo-planning/.events/event-log.jsonl"
  done
}

@test "rollout-stage: check reports canary with no event log" {
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" rollout-stage check
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.current_stage == "canary"'
  echo "$output" | jq -e '.completed_phases == 0'
}

@test "rollout-stage: check reports completed_phases after events" {
  cd "$TEST_TEMP_DIR"
  create_event_log 2
  run "$YOLO_BIN" rollout-stage check
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.completed_phases == 2'
}

@test "rollout-stage: check reports can_advance when not at final" {
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" rollout-stage check
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.can_advance == true'
  echo "$output" | jq -e '.next_stage == "partial"'
}

@test "rollout-stage: advance moves from canary to partial" {
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" rollout-stage advance
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.advanced == true'
  echo "$output" | jq -e '.to_stage == "partial"'
  # Config updated
  run jq -r '.rollout_stage' "$TEST_TEMP_DIR/.yolo-planning/config.json"
  [ "$output" = "partial" ]
}

@test "rollout-stage: advance sets max_agents in config" {
  cd "$TEST_TEMP_DIR"
  "$YOLO_BIN" rollout-stage advance >/dev/null
  run jq -r '.max_agents' "$TEST_TEMP_DIR/.yolo-planning/config.json"
  [ "$output" = "4" ]
  run jq -r '.rollout_scope' "$TEST_TEMP_DIR/.yolo-planning/config.json"
  [ "$output" = "expanded" ]
}

@test "rollout-stage: advance is idempotent at final stage" {
  cd "$TEST_TEMP_DIR"
  # Advance to partial
  "$YOLO_BIN" rollout-stage advance >/dev/null
  # Advance to full
  "$YOLO_BIN" rollout-stage advance >/dev/null
  # Try advance again at final
  run "$YOLO_BIN" rollout-stage advance
  [ "$status" -eq 0 ]
  [[ "$output" == *"Already at final"* ]]
}

@test "rollout-stage: status outputs stage listing" {
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" rollout-stage status
  [ "$status" -eq 0 ]
  [[ "$output" == *"Rollout Stages"* ]]
  [[ "$output" == *"canary"* ]]
  [[ "$output" == *"partial"* ]]
  [[ "$output" == *"full"* ]]
}

@test "rollout-stage: status highlights current stage" {
  cd "$TEST_TEMP_DIR"
  "$YOLO_BIN" rollout-stage advance >/dev/null
  run "$YOLO_BIN" rollout-stage status
  [ "$status" -eq 0 ]
  [[ "$output" == *">>> 2. partial"* ]]
}

@test "rollout-stage: check with missing config exits 0" {
  cd "$TEST_TEMP_DIR"
  rm -f "$TEST_TEMP_DIR/.yolo-planning/config.json"
  run "$YOLO_BIN" rollout-stage check
  [ "$status" -eq 0 ]
}

@test "rollout-stage: advance logs rollout_advance event" {
  cd "$TEST_TEMP_DIR"
  jq '.v3_event_log = true' ".yolo-planning/config.json" > ".yolo-planning/config.tmp" && mv ".yolo-planning/config.tmp" ".yolo-planning/config.json"
  "$YOLO_BIN" rollout-stage advance >/dev/null
  [ -f ".yolo-planning/.events/event-log.jsonl" ]
  grep -q "rollout_advance" ".yolo-planning/.events/event-log.jsonl"
}
