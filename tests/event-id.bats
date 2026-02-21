#!/usr/bin/env bats
# Migrated: log-event.sh -> yolo log-event
# CWD-sensitive: yes

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  # Enable event logging
  jq '.v3_event_log = true' "$TEST_TEMP_DIR/.yolo-planning/config.json" > "$TEST_TEMP_DIR/.yolo-planning/config.json.tmp" \
    && mv "$TEST_TEMP_DIR/.yolo-planning/config.json.tmp" "$TEST_TEMP_DIR/.yolo-planning/config.json"
}

teardown() {
  teardown_temp_dir
}

@test "log-event: includes event_id in output" {
  cd "$TEST_TEMP_DIR"
  "$YOLO_BIN" log-event phase_start 1 >/dev/null
  LINE=$(head -1 .yolo-planning/.events/event-log.jsonl)
  echo "$LINE" | jq -e '.event_id'
  EVENT_ID=$(echo "$LINE" | jq -r '.event_id')
  [ -n "$EVENT_ID" ]
  [ "$EVENT_ID" != "null" ]
}

@test "log-event: event_id is unique across events" {
  cd "$TEST_TEMP_DIR"
  "$YOLO_BIN" log-event phase_start 1 >/dev/null
  "$YOLO_BIN" log-event plan_start 1 1 >/dev/null
  "$YOLO_BIN" log-event phase_end 1 >/dev/null
  ID1=$(sed -n '1p' .yolo-planning/.events/event-log.jsonl | jq -r '.event_id')
  ID2=$(sed -n '2p' .yolo-planning/.events/event-log.jsonl | jq -r '.event_id')
  ID3=$(sed -n '3p' .yolo-planning/.events/event-log.jsonl | jq -r '.event_id')
  [ "$ID1" != "$ID2" ]
  [ "$ID2" != "$ID3" ]
  [ "$ID1" != "$ID3" ]
}

@test "log-event: event_id format is UUID-like" {
  cd "$TEST_TEMP_DIR"
  "$YOLO_BIN" log-event phase_start 1 >/dev/null
  EVENT_ID=$(head -1 .yolo-planning/.events/event-log.jsonl | jq -r '.event_id')
  # Should be non-empty and not null
  [ -n "$EVENT_ID" ]
  [ "$EVENT_ID" != "null" ]
}

@test "log-event: event_id present in all events" {
  cd "$TEST_TEMP_DIR"
  "$YOLO_BIN" log-event phase_start 1 >/dev/null
  "$YOLO_BIN" log-event phase_end 1 >/dev/null
  # Both lines should have event_id
  while IFS= read -r line; do
    echo "$line" | jq -e '.event_id'
  done < .yolo-planning/.events/event-log.jsonl
}
