#!/usr/bin/env bats
# Integration tests for schema validation via migrate-config.
# Requires the yolo binary to be built.

load test_helper

setup() {
  setup_temp_dir
  # Skip all tests if binary is not available
  if [ ! -x "$YOLO_BIN" ]; then
    skip "yolo binary not found at $YOLO_BIN"
  fi
}

teardown() {
  teardown_temp_dir
}

@test "migrate-config rejects config with invalid effort type" {
  local tmp="$TEST_TEMP_DIR/mc"
  mkdir -p "$tmp"
  echo '{"effort": 123}' > "$tmp/config.json"
  cp "$CONFIG_DIR/defaults.json" "$tmp/defaults.json"
  cp "$CONFIG_DIR/config.schema.json" "$tmp/config.schema.json"
  run "$YOLO_BIN" migrate-config "$tmp/config.json" "$tmp/defaults.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"validation failed"* ]] || [[ "$output" == *"Config validation failed"* ]]
}

@test "migrate-config accepts valid config" {
  local tmp="$TEST_TEMP_DIR/mc"
  mkdir -p "$tmp"
  echo '{"effort": "balanced"}' > "$tmp/config.json"
  cp "$CONFIG_DIR/defaults.json" "$tmp/defaults.json"
  cp "$CONFIG_DIR/config.schema.json" "$tmp/config.schema.json"
  run "$YOLO_BIN" migrate-config "$tmp/config.json" "$tmp/defaults.json"
  [ "$status" -eq 0 ]
}

@test "migrate-config rejects unknown keys" {
  local tmp="$TEST_TEMP_DIR/mc"
  mkdir -p "$tmp"
  echo '{"effort": "balanced", "bogus_key": true}' > "$tmp/config.json"
  cp "$CONFIG_DIR/defaults.json" "$tmp/defaults.json"
  cp "$CONFIG_DIR/config.schema.json" "$tmp/config.schema.json"
  run "$YOLO_BIN" migrate-config "$tmp/config.json" "$tmp/defaults.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"validation failed"* ]] || [[ "$output" == *"Config validation failed"* ]]
}

@test "defaults.json validates against config.schema.json via migrate-config" {
  local tmp="$TEST_TEMP_DIR/mc"
  mkdir -p "$tmp"
  # Use defaults.json as both config and defaults — merge is identity
  cp "$CONFIG_DIR/defaults.json" "$tmp/config.json"
  cp "$CONFIG_DIR/defaults.json" "$tmp/defaults.json"
  cp "$CONFIG_DIR/config.schema.json" "$tmp/config.schema.json"
  run "$YOLO_BIN" migrate-config "$tmp/config.json" "$tmp/defaults.json"
  [ "$status" -eq 0 ]
}
