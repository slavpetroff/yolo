#!/usr/bin/env bats

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

@test "log-event: task_blocked includes next_action in data" {
  cd "$TEST_TEMP_DIR"
  bash "$SCRIPTS_DIR/log-event.sh" task_blocked 1 1 \
    task_id=1-1-T1 reason="dependency missing" next_action=escalate_lead
  LINE=$(head -1 .yolo-planning/.events/event-log.jsonl)
  echo "$LINE" | jq -e '.event == "task_blocked"'
  echo "$LINE" | jq -e '.data.next_action == "escalate_lead"'
  echo "$LINE" | jq -e '.data.reason == "dependency missing"'
}

@test "log-event: task_blocked works without next_action" {
  cd "$TEST_TEMP_DIR"
  bash "$SCRIPTS_DIR/log-event.sh" task_blocked 1 1 \
    task_id=1-1-T1 reason="simple block"
  LINE=$(head -1 .yolo-planning/.events/event-log.jsonl)
  echo "$LINE" | jq -e '.event == "task_blocked"'
  echo "$LINE" | jq -e '.data.reason == "simple block"'
}

@test "log-event: task_blocked next_action values are preserved" {
  cd "$TEST_TEMP_DIR"
  bash "$SCRIPTS_DIR/log-event.sh" task_blocked 1 1 next_action=retry
  bash "$SCRIPTS_DIR/log-event.sh" task_blocked 1 1 next_action=reassign
  bash "$SCRIPTS_DIR/log-event.sh" task_blocked 1 1 next_action=manual_fix
  LINE1=$(sed -n '1p' .yolo-planning/.events/event-log.jsonl)
  LINE2=$(sed -n '2p' .yolo-planning/.events/event-log.jsonl)
  LINE3=$(sed -n '3p' .yolo-planning/.events/event-log.jsonl)
  echo "$LINE1" | jq -e '.data.next_action == "retry"'
  echo "$LINE2" | jq -e '.data.next_action == "reassign"'
  echo "$LINE3" | jq -e '.data.next_action == "manual_fix"'
}
