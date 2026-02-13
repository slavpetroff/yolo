#!/usr/bin/env bats
# hooks-json-integrity.bats — Validate hooks.json structure

setup() {
  load '../test_helper/common'
}

@test "hooks.json is valid JSON" {
  run jq empty "$HOOKS_JSON"
  assert_success
}

@test "hooks.json has all 11 hook event types" {
  local expected_events=(
    PostToolUse PreToolUse SubagentStart SubagentStop
    TeammateIdle TaskCompleted SessionStart PreCompact
    Stop UserPromptSubmit Notification
  )
  for event in "${expected_events[@]}"; do
    run jq -e ".hooks.\"$event\"" "$HOOKS_JSON"
    assert_success
  done
}

@test "every hook command references hook-wrapper.sh" {
  # Extract all command strings, verify each contains hook-wrapper.sh
  local commands
  commands=$(jq -r '.. | objects | select(.command?) | .command' "$HOOKS_JSON")
  while IFS= read -r cmd; do
    [[ "$cmd" == *"hook-wrapper.sh"* ]]
  done <<< "$commands"
}

@test "every hook has a timeout value" {
  # Find any hook entry without a timeout
  local missing
  missing=$(jq '[.. | objects | select(.type == "command") | select(.timeout == null)] | length' "$HOOKS_JSON")
  [ "$missing" -eq 0 ]
}

@test "PreToolUse includes security-filter.sh" {
  run jq -r '.hooks.PreToolUse[].hooks[].command' "$HOOKS_JSON"
  assert_output --partial "security-filter.sh"
}

@test "PreToolUse includes file-guard.sh" {
  run jq -r '.hooks.PreToolUse[].hooks[].command' "$HOOKS_JSON"
  assert_output --partial "file-guard.sh"
}
