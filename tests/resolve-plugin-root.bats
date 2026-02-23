#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
}

teardown() {
  teardown_temp_dir
}

@test "resolves via CLAUDE_PLUGIN_ROOT env" {
  export CLAUDE_PLUGIN_ROOT="$TEST_TEMP_DIR"
  run "$YOLO_BIN" resolve-plugin-root
  unset CLAUDE_PLUGIN_ROOT
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.ok == true'
  echo "$output" | jq -e '.resolved_via == "env"'
  echo "$output" | jq -e ".plugin_root == \"$TEST_TEMP_DIR\""
}

@test "resolves by walking up" {
  unset CLAUDE_PLUGIN_ROOT 2>/dev/null || true
  mkdir -p "$TEST_TEMP_DIR/config"
  echo '{}' > "$TEST_TEMP_DIR/config/defaults.json"
  mkdir -p "$TEST_TEMP_DIR/a/b/c"
  run bash -c "cd '$TEST_TEMP_DIR/a/b/c' && '$YOLO_BIN' resolve-plugin-root"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.ok == true'
  echo "$output" | jq -e '.resolved_via == "walk"'
}

@test "resolves via binary fallback" {
  unset CLAUDE_PLUGIN_ROOT 2>/dev/null || true
  # Run from temp dir with no config/defaults.json markers
  run bash -c "cd '$TEST_TEMP_DIR' && '$YOLO_BIN' resolve-plugin-root"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.ok == true'
}

@test "outputs valid JSON" {
  run "$YOLO_BIN" resolve-plugin-root
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'has("cmd")'
  echo "$output" | jq -e '.cmd == "resolve-plugin-root"'
}
