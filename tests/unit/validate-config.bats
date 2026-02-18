#!/usr/bin/env bats
# validate-config.bats — Unit tests for scripts/validate-config.sh
# Config validation for integration_gate, po.default_rejection, delivery keys.

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/validate-config.sh"
  CONFIG="$TEST_WORKDIR/config.json"
}

# Helper: write config and run validator
run_validate() {
  run bash "$SUT" "$CONFIG"
}

# --- integration_gate.enabled ---

@test "integration_gate.enabled accepts boolean true" {
  echo '{"integration_gate":{"enabled":true}}' > "$CONFIG"
  run_validate
  assert_success
  echo "$output" | jq -e '.valid == true'
}

@test "integration_gate.enabled accepts boolean false" {
  echo '{"integration_gate":{"enabled":false}}' > "$CONFIG"
  run_validate
  assert_success
  echo "$output" | jq -e '.valid == true'
}

@test "integration_gate.enabled rejects string" {
  echo '{"integration_gate":{"enabled":"yes"}}' > "$CONFIG"
  run_validate
  assert_failure
  echo "$output" | jq -e '.valid == false'
  echo "$output" | jq -e '.errors | any(test("integration_gate.enabled must be boolean"))'
}

# --- integration_gate.timeout_seconds ---

@test "integration_gate.timeout_seconds accepts 120" {
  echo '{"integration_gate":{"timeout_seconds":120}}' > "$CONFIG"
  run_validate
  assert_success
  echo "$output" | jq -e '.valid == true'
}

@test "integration_gate.timeout_seconds rejects non-number string" {
  echo '{"integration_gate":{"timeout_seconds":"fast"}}' > "$CONFIG"
  run_validate
  assert_failure
  echo "$output" | jq -e '.valid == false'
  echo "$output" | jq -e '.errors | any(test("integration_gate.timeout_seconds"))'
}

@test "integration_gate.timeout_seconds rejects below 60" {
  echo '{"integration_gate":{"timeout_seconds":30}}' > "$CONFIG"
  run_validate
  assert_failure
  echo "$output" | jq -e '.valid == false'
  echo "$output" | jq -e '.errors | any(test("integration_gate.timeout_seconds"))'
}

@test "integration_gate.timeout_seconds rejects above 3600" {
  echo '{"integration_gate":{"timeout_seconds":5000}}' > "$CONFIG"
  run_validate
  assert_failure
  echo "$output" | jq -e '.valid == false'
  echo "$output" | jq -e '.errors | any(test("integration_gate.timeout_seconds"))'
}

# --- po.default_rejection ---

@test "po.default_rejection accepts patch" {
  echo '{"po":{"default_rejection":"patch"}}' > "$CONFIG"
  run_validate
  assert_success
  echo "$output" | jq -e '.valid == true'
}

@test "po.default_rejection accepts major" {
  echo '{"po":{"default_rejection":"major"}}' > "$CONFIG"
  run_validate
  assert_success
  echo "$output" | jq -e '.valid == true'
}

@test "po.default_rejection rejects invalid values" {
  echo '{"po":{"default_rejection":"minor"}}' > "$CONFIG"
  run_validate
  assert_failure
  echo "$output" | jq -e '.valid == false'
  echo "$output" | jq -e '.errors | any(test("po.default_rejection must be one of"))'
}

# --- delivery.mode ---

@test "delivery.mode accepts auto" {
  echo '{"delivery":{"mode":"auto"}}' > "$CONFIG"
  run_validate
  assert_success
  echo "$output" | jq -e '.valid == true'
}

@test "delivery.mode accepts manual" {
  echo '{"delivery":{"mode":"manual"}}' > "$CONFIG"
  run_validate
  assert_success
  echo "$output" | jq -e '.valid == true'
}

@test "delivery.mode rejects invalid values" {
  echo '{"delivery":{"mode":"hybrid"}}' > "$CONFIG"
  run_validate
  assert_failure
  echo "$output" | jq -e '.valid == false'
  echo "$output" | jq -e '.errors | any(test("delivery.mode must be one of"))'
}

# --- delivery.present_to_user ---

@test "delivery.present_to_user accepts boolean true" {
  echo '{"delivery":{"present_to_user":true}}' > "$CONFIG"
  run_validate
  assert_success
  echo "$output" | jq -e '.valid == true'
}

@test "delivery.present_to_user rejects string" {
  echo '{"delivery":{"present_to_user":"yes"}}' > "$CONFIG"
  run_validate
  assert_failure
  echo "$output" | jq -e '.valid == false'
  echo "$output" | jq -e '.errors | any(test("delivery.present_to_user must be boolean"))'
}

# --- Full valid config ---

@test "full config with all new Phase 5 keys passes validation" {
  cat > "$CONFIG" <<'EOF'
{
  "integration_gate": {
    "enabled": true,
    "timeout_seconds": 300,
    "checks": {"api": true, "design": true, "tests": true},
    "retry_on_fail": false
  },
  "po": {
    "default_rejection": "patch"
  },
  "delivery": {
    "mode": "auto",
    "present_to_user": true
  }
}
EOF
  run_validate
  assert_success
  echo "$output" | jq -e '.valid == true'
}
