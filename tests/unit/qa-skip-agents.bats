#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="${BATS_TEST_DIRNAME}/../.."
}

# --- qa_skip_agents regression tests ---

@test "qa_skip_agents key exists in defaults.json" {
  run jq -e 'has("qa_skip_agents")' "$PROJECT_ROOT/config/defaults.json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "qa_skip_agents is an array containing docs" {
  run jq -e '.qa_skip_agents | type == "array" and contains(["docs"])' "$PROJECT_ROOT/config/defaults.json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "config.schema.json defines qa_skip_agents as array of strings" {
  run jq -e '.properties.qa_skip_agents | .type == "array" and .items.type == "string"' "$PROJECT_ROOT/config/config.schema.json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "execute protocol SKILL.md references qa_skip_agents" {
  run grep -c 'qa_skip_agents' "$PROJECT_ROOT/skills/execute-protocol/SKILL.md"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

@test "PLAN.md template includes agent field" {
  run grep -c 'agent:' "$PROJECT_ROOT/templates/PLAN.md"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}
