#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  export YOLO_BIN="${YOLO_BIN:-$HOME/.cargo/bin/yolo}"
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning/.events"
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning/.metrics"
}

teardown() {
  teardown_temp_dir
}

@test "metrics-report: shows segmentation section header" {
  cd "$TEST_TEMP_DIR"
  # Create gate events with autonomy field (as emitted by hard-gate.sh)
  cat > .yolo-planning/.events/event-log.jsonl << 'EVENTS'
{"ts":"2026-01-01T00:00:00Z","event":"gate_passed","phase":1,"autonomy":"standard","data":{"gate":"contract_compliance"}}
{"ts":"2026-01-01T00:01:00Z","event":"gate_passed","phase":1,"autonomy":"standard","data":{"gate":"commit_hygiene"}}
EVENTS
  run "$YOLO_BIN" metrics-report
  [ "$status" -eq 0 ]
  [[ "$output" == *"Profile x Autonomy Breakdown"* ]]
}

@test "metrics-report: shows no segmented data when empty" {
  cd "$TEST_TEMP_DIR"
  # Empty events file — no autonomy data
  echo '{"ts":"2026-01-01T00:00:00Z","event":"phase_start","phase":1}' > .yolo-planning/.events/event-log.jsonl
  run "$YOLO_BIN" metrics-report
  [ "$status" -eq 0 ]
  [[ "$output" == *"No segmented data available"* ]]
}

@test "metrics-report: counts events by autonomy" {
  cd "$TEST_TEMP_DIR"
  # Create events with different autonomy values
  cat > .yolo-planning/.events/event-log.jsonl << 'EVENTS'
{"ts":"2026-01-01T00:00:00Z","event":"gate_passed","phase":1,"autonomy":"standard","data":{"gate":"contract_compliance"}}
{"ts":"2026-01-01T00:01:00Z","event":"gate_failed","phase":1,"autonomy":"yolo","data":{"gate":"commit_hygiene"}}
{"ts":"2026-01-01T00:02:00Z","event":"gate_passed","phase":1,"autonomy":"standard","data":{"gate":"required_checks"}}
EVENTS
  run "$YOLO_BIN" metrics-report
  [ "$status" -eq 0 ]
  [[ "$output" == *"Profile x Autonomy"* ]]
  # Should have the table header
  [[ "$output" == *"Gate Events"* ]]
}
