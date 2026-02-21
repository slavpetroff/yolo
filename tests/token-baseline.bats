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

@test "token-baseline: exits 0 with no event data" {
  cd "$TEST_TEMP_DIR"
  # Remove event/metrics dirs so files don't exist
  rm -rf ".yolo-planning/.events" ".yolo-planning/.metrics"
  run "$YOLO_BIN" token-baseline
  [ "$status" -eq 0 ]
  [[ "$output" == *"No event data"* ]]
}

@test "token-baseline: measure counts overages per phase" {
  cd "$TEST_TEMP_DIR"
  # 2 overages in phase 1, 1 in phase 2
  echo '{"ts":"2026-02-13T10:00:00Z","event":"token_overage","phase":1,"data":{"role":"dev","lines_total":"500","lines_max":"800","lines_truncated":"100"}}' >> .yolo-planning/.metrics/run-metrics.jsonl
  echo '{"ts":"2026-02-13T10:01:00Z","event":"token_overage","phase":1,"data":{"role":"dev","lines_total":"600","lines_max":"800","lines_truncated":"50"}}' >> .yolo-planning/.metrics/run-metrics.jsonl
  echo '{"ts":"2026-02-13T10:02:00Z","event":"token_overage","phase":2,"data":{"role":"qa","lines_total":"400","lines_max":"600","lines_truncated":"30"}}' >> .yolo-planning/.metrics/run-metrics.jsonl

  run "$YOLO_BIN" token-baseline measure
  [ "$status" -eq 0 ]

  # Parse JSON output
  phase1_overages=$(echo "$output" | jq '.phases["1"].overages')
  phase2_overages=$(echo "$output" | jq '.phases["2"].overages')
  [ "$phase1_overages" -eq 2 ]
  [ "$phase2_overages" -eq 1 ]
}

@test "token-baseline: measure computes truncated lines sum" {
  cd "$TEST_TEMP_DIR"
  echo '{"ts":"2026-02-13T10:00:00Z","event":"token_overage","phase":1,"data":{"role":"dev","lines_total":"500","lines_max":"800","lines_truncated":"100"}}' >> .yolo-planning/.metrics/run-metrics.jsonl
  echo '{"ts":"2026-02-13T10:01:00Z","event":"token_overage","phase":1,"data":{"role":"dev","lines_total":"600","lines_max":"800","lines_truncated":"50"}}' >> .yolo-planning/.metrics/run-metrics.jsonl
  echo '{"ts":"2026-02-13T10:02:00Z","event":"token_overage","phase":2,"data":{"role":"qa","lines_total":"400","lines_max":"600","lines_truncated":"30"}}' >> .yolo-planning/.metrics/run-metrics.jsonl

  run "$YOLO_BIN" token-baseline measure
  [ "$status" -eq 0 ]

  total_truncated=$(echo "$output" | jq '.totals.truncated_chars')
  [ "$total_truncated" -eq 180 ]
}

@test "token-baseline: measure --save stores baseline" {
  cd "$TEST_TEMP_DIR"
  echo '{"ts":"2026-02-13T10:00:00Z","event":"token_overage","phase":1,"data":{"role":"dev","lines_total":"500","lines_max":"800","lines_truncated":"100"}}' >> .yolo-planning/.metrics/run-metrics.jsonl
  echo '{"ts":"2026-02-13T10:00:00Z","event_id":"e1","event":"task_started","phase":1}' >> .yolo-planning/.events/event-log.jsonl

  run "$YOLO_BIN" token-baseline measure --save
  [ "$status" -eq 0 ]

  # Baseline file should exist and be valid JSON
  [ -f ".yolo-planning/.baselines/token-baseline.json" ]
  run jq -e '.timestamp' .yolo-planning/.baselines/token-baseline.json
  [ "$status" -eq 0 ]
  run jq -e '.phases' .yolo-planning/.baselines/token-baseline.json
  [ "$status" -eq 0 ]
  run jq -e '.totals' .yolo-planning/.baselines/token-baseline.json
  [ "$status" -eq 0 ]
}

@test "token-baseline: compare shows deltas against baseline" {
  cd "$TEST_TEMP_DIR"
  # Create baseline with known values
  mkdir -p .yolo-planning/.baselines
  cat > .yolo-planning/.baselines/token-baseline.json <<'JSON'
{"timestamp":"2026-02-10T00:00:00Z","phases":{"1":{"overages":3,"truncated_chars":200,"tasks":10,"escalations":1,"overages_per_task":0.3}},"totals":{"overages":3,"truncated_chars":200,"tasks":10,"escalations":1,"overages_per_task":0.3},"budget_utilization":{}}
JSON

  # Create current data with fewer overages (better)
  echo '{"ts":"2026-02-13T10:00:00Z","event":"token_overage","phase":1,"data":{"role":"dev","lines_total":"300","lines_max":"800","lines_truncated":"50"}}' >> .yolo-planning/.metrics/run-metrics.jsonl
  echo '{"ts":"2026-02-13T10:00:00Z","event_id":"e1","event":"task_started","phase":1}' >> .yolo-planning/.events/event-log.jsonl

  run "$YOLO_BIN" token-baseline compare
  [ "$status" -eq 0 ]

  # Current has 1 overage vs baseline 3 = delta -2 = better
  direction=$(echo "$output" | jq -r '.deltas.overages.direction')
  [ "$direction" = "better" ]
  delta=$(echo "$output" | jq '.deltas.overages.delta')
  [ "$delta" -eq -2 ]
}

@test "token-baseline: compare exits 0 when no baseline exists" {
  cd "$TEST_TEMP_DIR"
  echo '{"ts":"2026-02-13T10:00:00Z","event":"token_overage","phase":1,"data":{"role":"dev","lines_total":"500","lines_max":"800","lines_truncated":"100"}}' >> .yolo-planning/.metrics/run-metrics.jsonl

  run "$YOLO_BIN" token-baseline compare
  [ "$status" -eq 0 ]
  [[ "$output" == *"No baseline"* ]]
}

@test "token-baseline: report generates markdown" {
  cd "$TEST_TEMP_DIR"
  echo '{"ts":"2026-02-13T10:00:00Z","event_id":"e1","event":"task_started","phase":1}' >> .yolo-planning/.events/event-log.jsonl
  echo '{"ts":"2026-02-13T10:00:00Z","event":"token_overage","phase":1,"data":{"role":"dev","lines_total":"500","lines_max":"800","lines_truncated":"100"}}' >> .yolo-planning/.metrics/run-metrics.jsonl

  run "$YOLO_BIN" token-baseline report
  [ "$status" -eq 0 ]
  [[ "$output" == *"Token Usage Baseline Report"* ]]
  [[ "$output" == *"Per-Phase Summary"* ]]
  [[ "$output" == *"Budget Utilization"* ]]
  [[ "$output" == *"| Phase |"* ]]
}

@test "token-baseline: report includes comparison when baseline exists" {
  cd "$TEST_TEMP_DIR"
  mkdir -p .yolo-planning/.baselines
  cat > .yolo-planning/.baselines/token-baseline.json <<'JSON'
{"timestamp":"2026-02-10T00:00:00Z","phases":{"1":{"overages":5,"truncated_chars":300,"tasks":10,"escalations":2,"overages_per_task":0.5}},"totals":{"overages":5,"truncated_chars":300,"tasks":10,"escalations":2,"overages_per_task":0.5},"budget_utilization":{}}
JSON

  echo '{"ts":"2026-02-13T10:00:00Z","event_id":"e1","event":"task_started","phase":1}' >> .yolo-planning/.events/event-log.jsonl
  echo '{"ts":"2026-02-13T10:00:00Z","event":"token_overage","phase":1,"data":{"role":"dev","lines_total":"300","lines_max":"800","lines_truncated":"50"}}' >> .yolo-planning/.metrics/run-metrics.jsonl

  run "$YOLO_BIN" token-baseline report
  [ "$status" -eq 0 ]
  [[ "$output" == *"Comparison with Baseline"* ]]
  [[ "$output" == *"Baseline from:"* ]]
  [[ "$output" == *"| Metric |"* ]]
  [[ "$output" == *"better"* ]]
}

@test "token-baseline: phase filter works" {
  cd "$TEST_TEMP_DIR"
  echo '{"ts":"2026-02-13T10:00:00Z","event_id":"e1","event":"task_started","phase":1}' >> .yolo-planning/.events/event-log.jsonl
  echo '{"ts":"2026-02-13T10:01:00Z","event_id":"e2","event":"task_started","phase":2}' >> .yolo-planning/.events/event-log.jsonl
  echo '{"ts":"2026-02-13T10:00:00Z","event":"token_overage","phase":1,"data":{"role":"dev","lines_total":"500","lines_max":"800","lines_truncated":"100"}}' >> .yolo-planning/.metrics/run-metrics.jsonl
  echo '{"ts":"2026-02-13T10:01:00Z","event":"token_overage","phase":2,"data":{"role":"qa","lines_total":"400","lines_max":"600","lines_truncated":"30"}}' >> .yolo-planning/.metrics/run-metrics.jsonl

  run "$YOLO_BIN" token-baseline report --phase=1
  [ "$status" -eq 0 ]
  [[ "$output" == *"Phase filter: 1"* ]]
  # Phase 1 should appear
  [[ "$output" == *"| 1 |"* ]]
  # Phase 2 should NOT appear in the per-phase table
  [[ "$output" != *"| 2 |"* ]]
}

@test "token-baseline: handles empty event log gracefully" {
  cd "$TEST_TEMP_DIR"
  # Create empty files (0 bytes)
  touch .yolo-planning/.events/event-log.jsonl
  touch .yolo-planning/.metrics/run-metrics.jsonl

  run "$YOLO_BIN" token-baseline measure
  [ "$status" -eq 0 ]

  total_overages=$(echo "$output" | jq '.totals.overages')
  total_tasks=$(echo "$output" | jq '.totals.tasks')
  [ "$total_overages" -eq 0 ]
  [ "$total_tasks" -eq 0 ]
}
