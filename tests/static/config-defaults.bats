#!/usr/bin/env bats
# config-defaults.bats — Validate config file schemas

setup() {
  load '../test_helper/common'
}

@test "defaults.json is valid JSON with required keys" {
  local defaults="$CONFIG_DIR/defaults.json"
  [ -f "$defaults" ]
  run jq empty "$defaults"
  assert_success
  # Check essential keys exist
  run jq -e '.effort' "$defaults"
  assert_success
  run jq -e '.autonomy' "$defaults"
  assert_success
}

@test "model-profiles.json has quality/balanced/budget profiles" {
  local profiles="$CONFIG_DIR/model-profiles.json"
  [ -f "$profiles" ]
  run jq -e '.quality' "$profiles"
  assert_success
  run jq -e '.balanced' "$profiles"
  assert_success
  run jq -e '.budget' "$profiles"
  assert_success
}

@test "model-profiles.json has all 26 agent roles per profile" {
  local profiles="$CONFIG_DIR/model-profiles.json"
  local agents=(
    lead dev qa qa-code scout debugger architect senior security critic tester
    owner
    fe-architect fe-lead fe-senior fe-dev fe-tester fe-qa fe-qa-code
    ux-architect ux-lead ux-senior ux-dev ux-tester ux-qa ux-qa-code
  )
  for profile in quality balanced budget; do
    for agent in "${agents[@]}"; do
      run jq -e --arg p "$profile" --arg a "$agent" '.[$p] | has($a)' "$profiles"
      assert_success
    done
  done
}

@test "defaults.json has all 4 approval_gates keys" {
  local defaults="$CONFIG_DIR/defaults.json"
  for gate in qa_fail security_warn code_review manual_qa; do
    run jq -e --arg g "$gate" '.approval_gates | has($g)' "$defaults"
    assert_success
  done
}

@test "defaults.json has department config keys" {
  local defaults="$CONFIG_DIR/defaults.json"
  run jq -e 'has("departments") and (.departments | has("backend"))' "$defaults"
  assert_success
  run jq -e 'has("department_workflow")' "$defaults"
  assert_success
  run jq -e 'has("cross_team_handoff")' "$defaults"
  assert_success
}

@test "defaults.json departments.backend is true" {
  local defaults="$CONFIG_DIR/defaults.json"
  run jq -r '.departments.backend' "$defaults"
  assert_success
  assert_output "true"
}

@test "stack-mappings.json is valid JSON" {
  local mappings="$CONFIG_DIR/stack-mappings.json"
  [ -f "$mappings" ]
  run jq empty "$mappings"
  assert_success
}
