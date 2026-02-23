#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  # Create test config with nested values
  mkdir -p "$TEST_TEMP_DIR/cfg"
  cat > "$TEST_TEMP_DIR/cfg/config.json" <<'EOF'
{
  "effort": "balanced",
  "agent_max_turns": {
    "scout": 15,
    "qa": 25,
    "dev": 75
  },
  "auto_commit": true
}
EOF
}

teardown() {
  teardown_temp_dir
}

@test "reads top-level key" {
  run "$YOLO_BIN" config-read effort unused "$TEST_TEMP_DIR/cfg/config.json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.value == "balanced"'
  echo "$output" | jq -e '.source == "config"'
}

@test "reads nested key with dot-notation" {
  run "$YOLO_BIN" config-read agent_max_turns.scout unused "$TEST_TEMP_DIR/cfg/config.json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.value == 15'
  echo "$output" | jq -e '.source == "config"'
}

@test "returns default when key missing" {
  run "$YOLO_BIN" config-read nonexistent fallback "$TEST_TEMP_DIR/cfg/config.json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.value == "fallback"'
  echo "$output" | jq -e '.source == "default"'
}

@test "returns source missing when no key no default" {
  # With only the key arg, config path defaults to .yolo-planning/config.json
  # Create that file in TEST_TEMP_DIR so config exists but key doesn't
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning"
  echo '{"effort":"balanced"}' > "$TEST_TEMP_DIR/.yolo-planning/config.json"
  run bash -c "cd '$TEST_TEMP_DIR' && '$YOLO_BIN' config-read nonexistent_key"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.source == "missing"'
  echo "$output" | jq -e '.value == null'
}

@test "handles missing config file" {
  run bash -c "cd '$TEST_TEMP_DIR' && '$YOLO_BIN' config-read effort"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.source == "missing"'
  echo "$output" | jq -e '.value == null'
}
