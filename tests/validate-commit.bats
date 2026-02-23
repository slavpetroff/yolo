#!/usr/bin/env bats

load test_helper

# Helper: pipe JSON to PreToolUse via a temp file to avoid quoting issues
run_pretooluse() {
  local json="$1"
  local tmpf
  tmpf=$(mktemp)
  printf '%s' "$json" > "$tmpf"
  run bash -c "\"$YOLO_BIN\" hook PreToolUse < \"$tmpf\""
  rm -f "$tmpf"
}

@test "PreToolUse passes Bash tool through (commit commands)" {
  run_pretooluse '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"feat(core): add new feature\""}}'
  [ "$status" -eq 0 ]
  [[ "$output" != *"permissionDecision"* ]]
}

@test "PreToolUse passes Bash tool through (non-commit commands)" {
  run_pretooluse '{"tool_name":"Bash","tool_input":{"command":"git status"}}'
  [ "$status" -eq 0 ]
  [[ "$output" != *"permissionDecision"* ]]
}

@test "PreToolUse passes Write tool with file_path" {
  run_pretooluse '{"tool_name":"Write","tool_input":{"file_path":"/tmp/test.txt","content":"hello"}}'
  [ "$status" -eq 0 ]
  [[ "$output" != *"permissionDecision"* ]]
}

@test "PreToolUse passes Read tool with file_path" {
  run_pretooluse '{"tool_name":"Read","tool_input":{"file_path":"/tmp/test.txt"}}'
  [ "$status" -eq 0 ]
  [[ "$output" != *"permissionDecision"* ]]
}
