#!/usr/bin/env bats
# resolve-qa-config.bats — RED phase tests for scripts/resolve-qa-config.sh
# Plan 04-03 T3: Resolves QA gate configuration by merging project config with defaults.

setup() {
  load 'test_helper/common'
  load 'test_helper/fixtures'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/resolve-qa-config.sh"
}

@test "resolves defaults when config has no qa_gates key" {
  # Create minimal config without qa_gates
  cat > "$TEST_WORKDIR/config.json" <<'JSON'
{"effort":"balanced","autonomy":"standard"}
JSON
  run bash "$SUT" "$TEST_WORKDIR/config.json" "$FIXTURES_DIR/config/balanced-config.json"
  assert_success
  # Output should be valid JSON with default qa_gates values
  local post_task post_plan post_phase timeout threshold
  post_task=$(echo "$output" | jq -r '.post_task')
  post_plan=$(echo "$output" | jq -r '.post_plan')
  post_phase=$(echo "$output" | jq -r '.post_phase')
  timeout=$(echo "$output" | jq -r '.timeout_seconds')
  threshold=$(echo "$output" | jq -r '.failure_threshold')
  [ "$post_task" = "true" ]
  [ "$post_plan" = "true" ]
  [ "$post_phase" = "true" ]
  [ "$timeout" = "300" ]
  [ "$threshold" = "critical" ]
}

@test "per-gate override from config wins" {
  # Config overrides post_task to false
  cat > "$TEST_WORKDIR/config.json" <<'JSON'
{"qa_gates":{"post_task":false}}
JSON
  run bash "$SUT" "$TEST_WORKDIR/config.json" "$FIXTURES_DIR/config/balanced-config.json"
  assert_success
  local post_task post_plan
  post_task=$(echo "$output" | jq -r '.post_task')
  post_plan=$(echo "$output" | jq -r '.post_plan')
  [ "$post_task" = "false" ]
  # Other fields should come from defaults
  [ "$post_plan" = "true" ]
}

@test "missing qa_gates key in both files falls back to hardcoded" {
  # Both config and defaults are empty objects
  echo '{}' > "$TEST_WORKDIR/config.json"
  echo '{}' > "$TEST_WORKDIR/defaults.json"
  run bash "$SUT" "$TEST_WORKDIR/config.json" "$TEST_WORKDIR/defaults.json"
  assert_success
  # Should fall back to hardcoded defaults
  local post_task post_plan post_phase timeout threshold
  post_task=$(echo "$output" | jq -r '.post_task')
  post_plan=$(echo "$output" | jq -r '.post_plan')
  post_phase=$(echo "$output" | jq -r '.post_phase')
  timeout=$(echo "$output" | jq -r '.timeout_seconds')
  threshold=$(echo "$output" | jq -r '.failure_threshold')
  [ "$post_task" = "true" ]
  [ "$post_plan" = "true" ]
  [ "$post_phase" = "true" ]
  [ "$timeout" = "300" ]
  [ "$threshold" = "critical" ]
}

@test "invalid config path fails gracefully" {
  # Nonexistent config, valid defaults
  run bash "$SUT" "/nonexistent/config.json" "$FIXTURES_DIR/config/balanced-config.json"
  # Fail-open: should exit 0 and produce valid JSON
  assert_success
  echo "$output" | jq -e '.' >/dev/null 2>&1
}

@test "partial override preserves unset fields" {
  # Config only sets timeout_seconds
  cat > "$TEST_WORKDIR/config.json" <<'JSON'
{"qa_gates":{"timeout_seconds":600}}
JSON
  run bash "$SUT" "$TEST_WORKDIR/config.json" "$FIXTURES_DIR/config/balanced-config.json"
  assert_success
  local timeout post_task post_plan post_phase threshold
  timeout=$(echo "$output" | jq -r '.timeout_seconds')
  post_task=$(echo "$output" | jq -r '.post_task')
  post_plan=$(echo "$output" | jq -r '.post_plan')
  post_phase=$(echo "$output" | jq -r '.post_phase')
  threshold=$(echo "$output" | jq -r '.failure_threshold')
  [ "$timeout" = "600" ]
  [ "$post_task" = "true" ]
  [ "$post_plan" = "true" ]
  [ "$post_phase" = "true" ]
  [ "$threshold" = "critical" ]
}

@test "rejects wrong argument count" {
  # Zero args
  run bash "$SUT"
  assert_failure
  assert_output --partial "Usage"
  # One arg
  run bash "$SUT" "$TEST_WORKDIR/config.json"
  assert_failure
  assert_output --partial "Usage"
}
