#!/usr/bin/env bats
# Migrated: generate-incidents.sh -> yolo incidents
# CWD-sensitive: yes

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning/.events"
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning/phases/01-test"
}

teardown() {
  teardown_temp_dir
}

@test "generate-incidents: creates INCIDENTS.md from task_blocked events" {
  cd "$TEST_TEMP_DIR"
  cat > .yolo-planning/.events/event-log.jsonl << 'EVENTS'
{"ts":"2026-01-01T00:00:00Z","event":"task_blocked","phase":1,"data":{"task_id":"1-1-T1","reason":"dependency missing","next_action":"escalate_lead"}}
{"ts":"2026-01-01T00:01:00Z","event":"task_blocked","phase":1,"data":{"task_id":"1-1-T2","reason":"file conflict","next_action":"retry"}}
EVENTS
  run "$YOLO_BIN" incidents 1
  [ "$status" -eq 0 ]
  [ -f ".yolo-planning/phases/01-test/01-INCIDENTS.md" ]
  grep -q "Blockers (2)" ".yolo-planning/phases/01-test/01-INCIDENTS.md"
  grep -q "escalate_lead" ".yolo-planning/phases/01-test/01-INCIDENTS.md"
}

@test "generate-incidents: includes task_completion_rejected events" {
  cd "$TEST_TEMP_DIR"
  cat > .yolo-planning/.events/event-log.jsonl << 'EVENTS'
{"ts":"2026-01-01T00:00:00Z","event":"task_completion_rejected","phase":1,"data":{"task_id":"1-1-T1","reason":"tests failing"}}
EVENTS
  run "$YOLO_BIN" incidents 1
  [ "$status" -eq 0 ]
  [ -f ".yolo-planning/phases/01-test/01-INCIDENTS.md" ]
  grep -q "Rejections (1)" ".yolo-planning/phases/01-test/01-INCIDENTS.md"
}

@test "generate-incidents: exits 0 with no output when no incidents" {
  cd "$TEST_TEMP_DIR"
  echo '{"ts":"2026-01-01T00:00:00Z","event":"phase_start","phase":1}' > .yolo-planning/.events/event-log.jsonl
  run "$YOLO_BIN" incidents 1
  [ "$status" -eq 0 ]
  [ ! -f ".yolo-planning/phases/01-test/01-INCIDENTS.md" ]
}

@test "generate-incidents: filters by phase number" {
  cd "$TEST_TEMP_DIR"
  cat > .yolo-planning/.events/event-log.jsonl << 'EVENTS'
{"ts":"2026-01-01T00:00:00Z","event":"task_blocked","phase":1,"data":{"task_id":"1-1-T1","reason":"blocked"}}
{"ts":"2026-01-01T00:01:00Z","event":"task_blocked","phase":2,"data":{"task_id":"2-1-T1","reason":"other block"}}
EVENTS
  run "$YOLO_BIN" incidents 1
  [ "$status" -eq 0 ]
  [ -f ".yolo-planning/phases/01-test/01-INCIDENTS.md" ]
  grep -q "Total: 1 incidents" ".yolo-planning/phases/01-test/01-INCIDENTS.md"
}
