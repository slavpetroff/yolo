#!/usr/bin/env bats
# validate-config.bats — RED phase tests for scripts/validate-config.sh
# Plan 04-03 T5: Validates config.json schema including qa_gates fields.

setup() {
  load 'test_helper/common'
  load 'test_helper/fixtures'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/validate-config.sh"
}

@test "valid config with qa_gates passes" {
  cat > "$TEST_WORKDIR/config.json" <<'JSON'
{
  "qa_gates": {
    "post_task": true,
    "post_plan": true,
    "post_phase": true,
    "timeout_seconds": 300,
    "failure_threshold": "critical"
  }
}
JSON
  run bash "$SUT" "$TEST_WORKDIR/config.json"
  assert_success
  local valid
  valid=$(echo "$output" | jq -r '.valid')
  [ "$valid" = "true" ]
}

@test "config without qa_gates key passes (backward compat)" {
  echo '{}' > "$TEST_WORKDIR/config.json"
  run bash "$SUT" "$TEST_WORKDIR/config.json"
  assert_success
  local valid
  valid=$(echo "$output" | jq -r '.valid')
  [ "$valid" = "true" ]
}

@test "rejects non-boolean post_task" {
  cat > "$TEST_WORKDIR/config.json" <<'JSON'
{"qa_gates":{"post_task":"yes"}}
JSON
  run bash "$SUT" "$TEST_WORKDIR/config.json"
  assert_failure
  assert_output --partial "boolean"
}

@test "rejects non-boolean post_plan" {
  cat > "$TEST_WORKDIR/config.json" <<'JSON'
{"qa_gates":{"post_plan":"yes"}}
JSON
  run bash "$SUT" "$TEST_WORKDIR/config.json"
  assert_failure
  assert_output --partial "boolean"
}

@test "rejects zero timeout_seconds" {
  cat > "$TEST_WORKDIR/config.json" <<'JSON'
{"qa_gates":{"timeout_seconds":0}}
JSON
  run bash "$SUT" "$TEST_WORKDIR/config.json"
  assert_failure
  assert_output --partial "positive"
}

@test "rejects invalid failure_threshold" {
  cat > "$TEST_WORKDIR/config.json" <<'JSON'
{"qa_gates":{"failure_threshold":"high"}}
JSON
  run bash "$SUT" "$TEST_WORKDIR/config.json"
  assert_failure
  # Must mention the invalid value or allowed values (critical, warning, info)
  assert_output --partial "failure_threshold"
}

@test "accumulates multiple errors" {
  cat > "$TEST_WORKDIR/config.json" <<'JSON'
{"qa_gates":{"post_task":"yes","timeout_seconds":-1,"failure_threshold":"bad"}}
JSON
  run bash "$SUT" "$TEST_WORKDIR/config.json"
  assert_failure
  # Should accumulate all errors
  local error_count
  error_count=$(echo "$output" | jq '.errors | length')
  [ "$error_count" = "3" ]
}

@test "rejects wrong argument count" {
  run bash "$SUT"
  assert_failure
  assert_output --partial "Usage"
}
