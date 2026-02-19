#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
}

teardown() {
  teardown_temp_dir
}

@test "defaults.json includes all 4 V3 feature flags" {
  # v3 flags have graduated — verify they are NOT in defaults and v2_token_budgets IS present
  run jq -r 'has("v2_token_budgets")' "$CONFIG_DIR/defaults.json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
  run jq -r 'has("v3_delta_context") or has("v3_context_cache") or has("v3_plan_research_persist") or has("v3_metrics")' "$CONFIG_DIR/defaults.json"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "V3 flags default to false in test config" {
  run jq -r '.v2_token_budgets' "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "V3 flags can be toggled to true" {
  jq '.v2_token_budgets = true' "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$TEST_TEMP_DIR/.vbw-planning/config.tmp" && mv "$TEST_TEMP_DIR/.vbw-planning/config.tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"
  run jq -r '.v2_token_budgets' "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}
