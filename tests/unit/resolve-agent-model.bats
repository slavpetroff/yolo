#!/usr/bin/env bats
# resolve-agent-model.bats — Unit tests for scripts/resolve-agent-model.sh
# Model resolution per agent.
# Usage: resolve-agent-model.sh <agent-name> <config-path> <profiles-path>
# Returns model string (opus|sonnet|haiku) on stdout.

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  load '../test_helper/mock_stdin'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/resolve-agent-model.sh"
  PROFILES="$CONFIG_DIR/model-profiles.json"
}

# Helper: run resolve-agent-model
run_resolve() {
  local agent="$1" config="$2"
  run bash "$SUT" "$agent" "$config" "$PROFILES"
}

# --- Quality profile ---

@test "quality profile: lead resolves to opus" {
  run_resolve lead "$FIXTURES_DIR/config/quality-config.json"
  assert_success
  assert_output "opus"
}

@test "quality profile: scout resolves to haiku" {
  run_resolve scout "$FIXTURES_DIR/config/quality-config.json"
  assert_success
  assert_output "haiku"
}

# --- Balanced profile ---

@test "balanced profile: lead resolves to sonnet" {
  run_resolve lead "$FIXTURES_DIR/config/balanced-config.json"
  assert_success
  assert_output "sonnet"
}

@test "balanced profile: architect resolves to opus" {
  run_resolve architect "$FIXTURES_DIR/config/balanced-config.json"
  assert_success
  assert_output "opus"
}

# --- Budget profile ---

@test "budget profile: qa resolves to haiku" {
  run_resolve qa "$FIXTURES_DIR/config/budget-config.json"
  assert_success
  assert_output "haiku"
}

# --- Model overrides from config ---

@test "applies model_overrides from config (dev → opus)" {
  run_resolve dev "$FIXTURES_DIR/config/override-config.json"
  assert_success
  assert_output "opus"
}

# --- Invalid agent name ---

@test "rejects invalid agent name" {
  run_resolve "invalid-agent" "$FIXTURES_DIR/config/balanced-config.json"
  assert_failure
  assert_output --partial "Unknown agent"
}

# --- Invalid profile ---

@test "rejects invalid profile" {
  local bad_config="$TEST_WORKDIR/bad-profile.json"
  echo '{"model_profile":"ultra"}' > "$bad_config"
  run_resolve lead "$bad_config"
  assert_failure
  assert_output --partial "Invalid model_profile"
}

# --- Invalid model value ---

@test "rejects invalid model value in override" {
  local bad_config="$TEST_WORKDIR/bad-model.json"
  echo '{"model_profile":"balanced","model_overrides":{"lead":"gpt4"}}' > "$bad_config"
  run_resolve lead "$bad_config"
  assert_failure
  assert_output --partial "Invalid model"
}

# --- Missing config file ---

@test "exits 1 on missing config file" {
  run bash "$SUT" lead "/nonexistent/config.json" "$PROFILES"
  assert_failure
  assert_output --partial "Config not found"
}

# --- Missing profiles file ---

@test "exits 1 on missing profiles file" {
  run bash "$SUT" lead "$FIXTURES_DIR/config/balanced-config.json" "/nonexistent/profiles.json"
  assert_failure
  assert_output --partial "Model profiles not found"
}

# --- Wrong argument count ---

@test "exits 1 with wrong arg count" {
  run bash "$SUT" lead
  assert_failure
  assert_output --partial "Usage:"
}
