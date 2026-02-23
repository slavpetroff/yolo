#!/usr/bin/env bats
# Migrated: resolve-agent-model.sh -> yolo resolve-model
# CWD-sensitive: no (takes config_path and profiles_path as arguments)

load test_helper

setup() {
  setup_temp_dir
  create_test_config
}

teardown() {
  teardown_temp_dir
}

@test "resolves dev model from quality profile" {
  run "$YOLO_BIN" resolve-model dev "$TEST_TEMP_DIR/.yolo-planning/config.json" "$CONFIG_DIR/model-profiles.json"
  [ "$status" -eq 0 ]
  [ "$output" = "opus" ]
}

@test "resolves researcher model from quality profile" {
  run "$YOLO_BIN" resolve-model researcher "$TEST_TEMP_DIR/.yolo-planning/config.json" "$CONFIG_DIR/model-profiles.json"
  [ "$status" -eq 0 ]
  [ "$output" = "sonnet" ]
}

@test "resolves dev model from balanced profile" {
  jq '.model_profile = "balanced"' "$TEST_TEMP_DIR/.yolo-planning/config.json" > "$TEST_TEMP_DIR/.yolo-planning/config.json.tmp"
  mv "$TEST_TEMP_DIR/.yolo-planning/config.json.tmp" "$TEST_TEMP_DIR/.yolo-planning/config.json"
  run "$YOLO_BIN" resolve-model dev "$TEST_TEMP_DIR/.yolo-planning/config.json" "$CONFIG_DIR/model-profiles.json"
  [ "$status" -eq 0 ]
  [ "$output" = "sonnet" ]
}

@test "respects per-agent override" {
  jq '.model_overrides.dev = "opus"' "$TEST_TEMP_DIR/.yolo-planning/config.json" > "$TEST_TEMP_DIR/.yolo-planning/config.json.tmp"
  mv "$TEST_TEMP_DIR/.yolo-planning/config.json.tmp" "$TEST_TEMP_DIR/.yolo-planning/config.json"

  run "$YOLO_BIN" resolve-model dev "$TEST_TEMP_DIR/.yolo-planning/config.json" "$CONFIG_DIR/model-profiles.json"
  [ "$status" -eq 0 ]
  [ "$output" = "opus" ]
}

@test "rejects invalid agent name" {
  run "$YOLO_BIN" resolve-model invalid "$TEST_TEMP_DIR/.yolo-planning/config.json" "$CONFIG_DIR/model-profiles.json"
  [ "$status" -eq 1 ]
}

@test "rejects missing config file" {
  run "$YOLO_BIN" resolve-model dev "/nonexistent/config.json" "$CONFIG_DIR/model-profiles.json"
  [ "$status" -eq 1 ]
}

@test "resolve-model --with-cost outputs JSON with cost_weight" {
  run "$YOLO_BIN" resolve-model dev "$TEST_TEMP_DIR/.yolo-planning/config.json" "$CONFIG_DIR/model-profiles.json" --with-cost
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.model' >/dev/null
  echo "$output" | jq -e '.cost_weight' >/dev/null
}

@test "resolve-model --all returns JSON object with agents" {
  run "$YOLO_BIN" resolve-model --all "$TEST_TEMP_DIR/.yolo-planning/config.json" "$CONFIG_DIR/model-profiles.json"
  [ "$status" -eq 0 ]
  local count=$(echo "$output" | jq 'keys | length')
  [ "$count" -ge 8 ]
  echo "$output" | jq -e '.lead' >/dev/null
  echo "$output" | jq -e '.dev' >/dev/null
}

@test "resolve-model --all --with-cost returns nested JSON" {
  run "$YOLO_BIN" resolve-model --all --with-cost "$TEST_TEMP_DIR/.yolo-planning/config.json" "$CONFIG_DIR/model-profiles.json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.lead.model' >/dev/null
  echo "$output" | jq -e '.lead.cost_weight' >/dev/null
}
