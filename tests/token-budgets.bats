#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning/.metrics"
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning/.events"
  # Enable flags
  jq '.v2_token_budgets = true | .v3_metrics = true | .v3_event_log = true' \
    "$TEST_TEMP_DIR/.yolo-planning/config.json" > "$TEST_TEMP_DIR/.yolo-planning/config.json.tmp" \
    && mv "$TEST_TEMP_DIR/.yolo-planning/config.json.tmp" "$TEST_TEMP_DIR/.yolo-planning/config.json"
  # Copy token budgets config
  mkdir -p "$TEST_TEMP_DIR/config"
  cp "$CONFIG_DIR/token-budgets.json" "$TEST_TEMP_DIR/config/"
}

teardown() {
  teardown_temp_dir
}

generate_chars() {
  local target=$1
  for i in $(seq 1 "$((target / 54 + 1))"); do
    printf "Line %04d of content for testing token budget enforce\n" "$i"
  done | head -c "$target"
}

# --- Token budget enforcement (Rust binary outputs JSON metadata) ---

@test "token-budget: reports within_budget for small content" {
  cd "$TEST_TEMP_DIR"
  CONTENT=$(generate_chars 4000)
  echo "$CONTENT" > "$TEST_TEMP_DIR/small.txt"
  run "$YOLO_BIN" token-budget scout "$TEST_TEMP_DIR/small.txt"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result == "within_budget"'
}

@test "token-budget: reports correct chars_used" {
  cd "$TEST_TEMP_DIR"
  generate_chars 4000 > "$TEST_TEMP_DIR/sized.txt"
  run "$YOLO_BIN" token-budget scout "$TEST_TEMP_DIR/sized.txt"
  [ "$status" -eq 0 ]
  CHARS=$(echo "$output" | jq -r '.chars_used')
  [ "$CHARS" -ge 3900 ]
  [ "$CHARS" -le 4100 ]
}

@test "token-budget: includes role in output" {
  cd "$TEST_TEMP_DIR"
  echo "test" > "$TEST_TEMP_DIR/tiny.txt"
  run "$YOLO_BIN" token-budget scout "$TEST_TEMP_DIR/tiny.txt"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.role == "scout"'
}

@test "token-budget: dev role accepted" {
  cd "$TEST_TEMP_DIR"
  echo "test" > "$TEST_TEMP_DIR/tiny.txt"
  run "$YOLO_BIN" token-budget dev "$TEST_TEMP_DIR/tiny.txt"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.role == "dev"'
}

@test "token-budget: reports chars_max in output" {
  cd "$TEST_TEMP_DIR"
  echo "test" > "$TEST_TEMP_DIR/tiny.txt"
  run "$YOLO_BIN" token-budget dev "$TEST_TEMP_DIR/tiny.txt"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.chars_max > 0'
}

@test "token-budget: skip when flag disabled" {
  cd "$TEST_TEMP_DIR"
  jq '.v2_token_budgets = false' ".yolo-planning/config.json" > ".yolo-planning/config.json.tmp" \
    && mv ".yolo-planning/config.json.tmp" ".yolo-planning/config.json"
  echo "test" > "$TEST_TEMP_DIR/tiny.txt"
  run "$YOLO_BIN" token-budget scout "$TEST_TEMP_DIR/tiny.txt"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result == "skip"'
}

@test "token-budget: reads from stdin" {
  cd "$TEST_TEMP_DIR"
  run bash -c "echo 'hello world' | \"$YOLO_BIN\" token-budget scout"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result' >/dev/null
}

# --- Per-task budget tests ---

@test "token-budget: accepts contract metadata args" {
  cd "$TEST_TEMP_DIR"
  jq -n '{phase:2, plan:1, task_count:3, must_haves:["a","b","c"], allowed_paths:["f1","f2","f3","f4"], depends_on:[]}' \
    > "$TEST_TEMP_DIR/contract.json"
  generate_chars 10000 > "$TEST_TEMP_DIR/task-context.txt"
  run "$YOLO_BIN" token-budget dev "$TEST_TEMP_DIR/task-context.txt" "$TEST_TEMP_DIR/contract.json" 1
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result' >/dev/null
}

@test "token-budget: handles missing contract file gracefully" {
  cd "$TEST_TEMP_DIR"
  generate_chars 10000 > "$TEST_TEMP_DIR/fallback-context.txt"
  run "$YOLO_BIN" token-budget dev "$TEST_TEMP_DIR/fallback-context.txt" "$TEST_TEMP_DIR/nonexistent.json" 1
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result' >/dev/null
}

@test "token-budget: output includes was_truncated field" {
  cd "$TEST_TEMP_DIR"
  echo "test" > "$TEST_TEMP_DIR/tiny.txt"
  run "$YOLO_BIN" token-budget dev "$TEST_TEMP_DIR/tiny.txt"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'has("was_truncated")'
}

@test "token-budget: output includes output_length field" {
  cd "$TEST_TEMP_DIR"
  echo "test" > "$TEST_TEMP_DIR/tiny.txt"
  run "$YOLO_BIN" token-budget dev "$TEST_TEMP_DIR/tiny.txt"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'has("output_length")'
}

# --- Metrics report (already uses $YOLO_BIN) ---

@test "metrics-report: produces markdown with no data" {
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" metrics-report
  [ "$status" -eq 0 ]
  [[ "$output" == *"Metrics Report"* ]] || [[ "$output" == *"Observability Report"* ]]
}

@test "metrics-report: produces summary table with event data" {
  cd "$TEST_TEMP_DIR"
  echo '{"ts":"2026-01-01","event":"task_started","phase":1}' >> ".yolo-planning/.events/event-log.jsonl"
  echo '{"ts":"2026-01-01","event":"task_completed_confirmed","phase":1}' >> ".yolo-planning/.events/event-log.jsonl"
  echo '{"ts":"2026-01-01","event":"gate_passed","phase":1}' >> ".yolo-planning/.events/event-log.jsonl"
  run "$YOLO_BIN" metrics-report
  [ "$status" -eq 0 ]
  [[ "$output" == *"Summary"* ]]
  [[ "$output" == *"Tasks started"* ]]
  [[ "$output" == *"Tasks confirmed"* ]]
}

@test "metrics-report: includes gate failure rate" {
  cd "$TEST_TEMP_DIR"
  echo '{"ts":"2026-01-01","event":"gate_passed","phase":1}' >> ".yolo-planning/.events/event-log.jsonl"
  echo '{"ts":"2026-01-01","event":"gate_passed","phase":1}' >> ".yolo-planning/.events/event-log.jsonl"
  echo '{"ts":"2026-01-01","event":"gate_failed","phase":1}' >> ".yolo-planning/.events/event-log.jsonl"
  run "$YOLO_BIN" metrics-report
  [ "$status" -eq 0 ]
  [[ "$output" == *"Gate Failure Rate"* ]]
  [[ "$output" == *"33%"* ]]
}

@test "metrics-report: computes median task latency" {
  cd "$TEST_TEMP_DIR"
  echo '{"ts":"2026-01-01T10:00:00Z","event":"task_started","phase":1,"data":{"task_id":"t1"}}' >> ".yolo-planning/.events/event-log.jsonl"
  echo '{"ts":"2026-01-01T10:05:00Z","event":"task_completed_confirmed","phase":1,"data":{"task_id":"t1"}}' >> ".yolo-planning/.events/event-log.jsonl"
  echo '{"ts":"2026-01-01T10:10:00Z","event":"task_started","phase":1,"data":{"task_id":"t2"}}' >> ".yolo-planning/.events/event-log.jsonl"
  echo '{"ts":"2026-01-01T10:20:00Z","event":"task_completed_confirmed","phase":1,"data":{"task_id":"t2"}}' >> ".yolo-planning/.events/event-log.jsonl"
  run "$YOLO_BIN" metrics-report
  [ "$status" -eq 0 ]
  [[ "$output" == *"Median latency"* ]]
  [[ "$output" != *"Median latency: N/A"* ]]
}

@test "metrics-report: shows profile info in summary" {
  cd "$TEST_TEMP_DIR"
  echo '{"ts":"2026-01-01","event":"task_started","phase":1}' >> ".yolo-planning/.events/event-log.jsonl"
  run "$YOLO_BIN" metrics-report
  [ "$status" -eq 0 ]
  [[ "$output" == *"effort=balanced"* ]]
  [[ "$output" == *"autonomy=standard"* ]]
}

# --- Config flag ---

@test "defaults.json includes v2_token_budgets flag" {
  run jq '.v2_token_budgets' "$CONFIG_DIR/defaults.json"
  [ "$output" = "true" ]
}

# --- Token budgets config ---

@test "token-budgets.json has all 5 roles" {
  run jq '.budgets | keys | length' "$CONFIG_DIR/token-budgets.json"
  [ "$output" = "5" ]
}

@test "token-budgets.json docs cap is lowest" {
  DOCS=$(jq '.budgets.docs.max_chars' "$CONFIG_DIR/token-budgets.json")
  DEV=$(jq '.budgets.dev.max_chars' "$CONFIG_DIR/token-budgets.json")
  [ "$DOCS" -lt "$DEV" ]
}

# --- Protocol integration ---

@test "execute-protocol references token budgets" {
  run grep -c "token-budget" "$PROJECT_ROOT/skills/execute-protocol/SKILL.md"
  [ "$output" -ge 1 ]
}

@test "execute-protocol references metrics report" {
  run grep -c "metrics-report" "$PROJECT_ROOT/skills/execute-protocol/SKILL.md"
  [ "$output" -ge 1 ]
}
