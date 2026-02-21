#!/usr/bin/env bats
# Migrated: log-event.sh -> yolo log-event
# CWD-sensitive: yes

load test_helper

setup() {
  setup_temp_dir
  create_test_config
}

teardown() {
  teardown_temp_dir
}

@test "event-types: accepts V1 event type when v2_typed_protocol enabled" {
  cd "$TEST_TEMP_DIR"
  jq '.v3_event_log = true | .v2_typed_protocol = true' .yolo-planning/config.json > .yolo-planning/config.json.tmp \
    && mv .yolo-planning/config.json.tmp .yolo-planning/config.json
  run "$YOLO_BIN" log-event phase_start 1
  [ "$status" -eq 0 ]
  [ -f .yolo-planning/.events/event-log.jsonl ]
  run grep -c "phase_start" .yolo-planning/.events/event-log.jsonl
  [ "$output" = "1" ]
}

@test "event-types: accepts V2 event type when v2_typed_protocol enabled" {
  cd "$TEST_TEMP_DIR"
  jq '.v3_event_log = true | .v2_typed_protocol = true' .yolo-planning/config.json > .yolo-planning/config.json.tmp \
    && mv .yolo-planning/config.json.tmp .yolo-planning/config.json
  run "$YOLO_BIN" log-event task_claimed 1
  [ "$status" -eq 0 ]
  [ -f .yolo-planning/.events/event-log.jsonl ]
  run grep -c "task_claimed" .yolo-planning/.events/event-log.jsonl
  [ "$output" = "1" ]
}

@test "event-types: rejects unknown event type when v2_typed_protocol enabled" {
  cd "$TEST_TEMP_DIR"
  jq '.v3_event_log = true | .v2_typed_protocol = true' .yolo-planning/config.json > .yolo-planning/config.json.tmp \
    && mv .yolo-planning/config.json.tmp .yolo-planning/config.json
  run "$YOLO_BIN" log-event bogus_event 1
  [ "$status" -eq 0 ]
  # Event file should not exist or not contain the bogus event
  if [ -f .yolo-planning/.events/event-log.jsonl ]; then
    run grep -c "bogus_event" .yolo-planning/.events/event-log.jsonl
    [ "$output" = "0" ]
  fi
}

@test "event-types: allows unknown event type when v2_typed_protocol disabled" {
  cd "$TEST_TEMP_DIR"
  jq '.v3_event_log = true | .v2_typed_protocol = false' .yolo-planning/config.json > .yolo-planning/config.json.tmp \
    && mv .yolo-planning/config.json.tmp .yolo-planning/config.json
  run "$YOLO_BIN" log-event bogus_event 1
  [ "$status" -eq 0 ]
  [ -f .yolo-planning/.events/event-log.jsonl ]
  run grep -c "bogus_event" .yolo-planning/.events/event-log.jsonl
  [ "$output" = "1" ]
}

@test "event-types: all 13 V2 types accepted" {
  cd "$TEST_TEMP_DIR"
  jq '.v3_event_log = true | .v2_typed_protocol = true' .yolo-planning/config.json > .yolo-planning/config.json.tmp \
    && mv .yolo-planning/config.json.tmp .yolo-planning/config.json
  local v2_types="phase_planned task_created task_claimed task_started artifact_written gate_passed gate_failed task_completed_candidate task_completed_confirmed task_blocked task_reassigned shutdown_sent shutdown_received"
  for etype in $v2_types; do
    run "$YOLO_BIN" log-event "$etype" 1
    [ "$status" -eq 0 ]
  done
  [ -f .yolo-planning/.events/event-log.jsonl ]
  run wc -l < .yolo-planning/.events/event-log.jsonl
  local count
  count=$(echo "$output" | tr -d ' ')
  [ "$count" = "13" ]
}
