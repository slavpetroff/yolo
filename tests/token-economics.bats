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

@test "report-tokens: exits 0 with no data and shows help message" {
  cd "$TEST_TEMP_DIR"
  # Remove metrics/events so no data exists
  rm -rf ".yolo-planning/.events" ".yolo-planning/.metrics"
  run "$YOLO_BIN" report-tokens
  [ "$status" -eq 0 ]
  [[ "$output" == *"No token"* ]] || [[ "$output" == *"no data"* ]] || [[ "$output" == *"No agent_token_usage"* ]]
}

@test "report-tokens: shows per-agent token breakdown" {
  cd "$TEST_TEMP_DIR"
  seed_agent_token_event "dev" 1 5000 1200 3000 800
  seed_agent_token_event "architect" 1 8000 2000 5000 1000
  seed_agent_token_event "qa" 2 3000 800 2000 500

  run "$YOLO_BIN" report-tokens
  [ "$status" -eq 0 ]
  [[ "$output" == *"Per-Agent"* ]]
  [[ "$output" == *"dev"* ]]
  [[ "$output" == *"architect"* ]]
  [[ "$output" == *"qa"* ]]
}

@test "report-tokens: calculates cache hit rate" {
  cd "$TEST_TEMP_DIR"
  # cache_read=7000, cache_write=1000, input=2000 => total=10000, rate=70%
  seed_agent_token_event "dev" 1 2000 500 7000 1000

  run "$YOLO_BIN" report-tokens
  [ "$status" -eq 0 ]
  [[ "$output" == *"Cache Hit"* ]]
  [[ "$output" == *"70"* ]]
}

@test "report-tokens: identifies waste agents" {
  cd "$TEST_TEMP_DIR"
  # input=50000, output=2000 => 25:1 ratio, should flag as waste
  seed_agent_token_event "bloated-agent" 1 50000 2000 1000 500

  run "$YOLO_BIN" report-tokens
  [ "$status" -eq 0 ]
  [[ "$output" == *"Waste"* ]] || [[ "$output" == *"waste"* ]] || [[ "$output" == *"bloated-agent"* ]]
}

@test "report-tokens: computes ROI per task" {
  cd "$TEST_TEMP_DIR"
  git init --quiet
  git config user.email "test@test.com"
  git config user.name "Test"
  touch dummy && git add dummy && git commit -m "test(init): seed" --quiet
  # 5 tasks completed, total tokens = 100000 => 20000 tokens/task
  seed_agent_token_event "dev" 1 60000 15000 20000 5000
  seed_task_completed 1 "t1"
  seed_task_completed 1 "t2"
  seed_task_completed 1 "t3"
  seed_task_completed 1 "t4"
  seed_task_completed 1 "t5"

  run "$YOLO_BIN" report-tokens --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.roi' > /dev/null
  tokens_per_task=$(echo "$output" | jq '.roi.tokens_per_task')
  [ "$tokens_per_task" -eq 20000 ]
}

@test "report-tokens: --json outputs valid JSON" {
  cd "$TEST_TEMP_DIR"
  seed_agent_token_event "dev" 1 5000 1200 3000 800

  run "$YOLO_BIN" report-tokens --json
  [ "$status" -eq 0 ]
  # Validate JSON
  echo "$output" | jq -e '.' > /dev/null
  # Check expected keys
  echo "$output" | jq -e '.per_agent' > /dev/null
  echo "$output" | jq -e '.cache_hit_rate' > /dev/null
  echo "$output" | jq -e '.waste' > /dev/null
  echo "$output" | jq -e '.roi' > /dev/null
}

@test "report-tokens: --phase=N filters correctly" {
  cd "$TEST_TEMP_DIR"
  seed_agent_token_event "dev" 1 5000 1200 3000 800
  seed_agent_token_event "architect" 1 8000 2000 5000 1000
  seed_agent_token_event "qa" 2 3000 800 2000 500

  run "$YOLO_BIN" report-tokens --phase=1
  [ "$status" -eq 0 ]
  # Phase 1 agents should appear
  [[ "$output" == *"dev"* ]]
  [[ "$output" == *"architect"* ]]
  # Phase 2 agent should NOT appear
  [[ "$output" != *"qa"* ]]
}

@test "report-tokens: handles empty metrics gracefully" {
  cd "$TEST_TEMP_DIR"
  # Create empty files (0 bytes)
  touch .yolo-planning/.metrics/run-metrics.jsonl
  touch .yolo-planning/.events/event-log.jsonl

  run "$YOLO_BIN" report-tokens
  [ "$status" -eq 0 ]
}

@test "report-tokens: handles tier-level cache hit fields gracefully" {
  cd "$TEST_TEMP_DIR"
  # Seed events with extra tier cache hit fields (forward-looking)
  local metrics_dir="$TEST_TEMP_DIR/.yolo-planning/.metrics"
  mkdir -p "$metrics_dir"
  printf '{"ts":"2026-02-20T10:00:00Z","event":"agent_token_usage","phase":1,"data":{"role":"dev","input_tokens":5000,"output_tokens":1200,"cache_read_tokens":3000,"cache_write_tokens":800,"tier1_cache_hit":true,"tier2_cache_hit":true}}\n' \
    >> "$metrics_dir/run-metrics.jsonl"
  printf '{"ts":"2026-02-20T10:01:00Z","event":"agent_token_usage","phase":1,"data":{"role":"architect","input_tokens":8000,"output_tokens":2000,"cache_read_tokens":5000,"cache_write_tokens":1000,"tier1_cache_hit":true,"tier2_cache_hit":false}}\n' \
    >> "$metrics_dir/run-metrics.jsonl"

  run "$YOLO_BIN" report-tokens
  [ "$status" -eq 0 ]
  # Core report still works — per-agent data present
  [[ "$output" == *"dev"* ]]
  [[ "$output" == *"architect"* ]]
}
