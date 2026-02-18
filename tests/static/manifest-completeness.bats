#!/usr/bin/env bats
# manifest-completeness.bats — Validate all agent files have context-manifest entries

setup() {
  load '../test_helper/common'
}

@test "context-manifest.json is valid JSON" {
  local manifest="$CONFIG_DIR/context-manifest.json"
  [ -f "$manifest" ]
  run jq empty "$manifest"
  assert_success
}

@test "every agent file has a context-manifest.json role entry" {
  local manifest="$CONFIG_DIR/context-manifest.json"
  local missing=()
  for agent_file in "$AGENTS_DIR"/yolo-*.md; do
    local role
    role=$(basename "$agent_file" .md | sed 's/^yolo-//')
    if ! jq -e --arg r "$role" '.roles[$r]' "$manifest" > /dev/null 2>&1; then
      missing+=("$role")
    fi
  done
  if [ ${#missing[@]} -gt 0 ]; then
    echo "Missing manifest entries: ${missing[*]}" >&2
    return 1
  fi
}

@test "every manifest role entry has required keys" {
  local manifest="$CONFIG_DIR/context-manifest.json"
  local roles
  roles=$(jq -r '.roles | keys[]' "$manifest")
  for role in $roles; do
    run jq -e --arg r "$role" '.roles[$r] | has("files") and has("artifacts") and has("fields") and has("budget")' "$manifest"
    assert_success
  done
}

@test "manifest budget values are positive numbers" {
  local manifest="$CONFIG_DIR/context-manifest.json"
  local roles
  roles=$(jq -r '.roles | keys[]' "$manifest")
  for role in $roles; do
    run jq -e --arg r "$role" '.roles[$r].budget > 0' "$manifest"
    assert_success
  done
}

@test "manifest includes references point to existing base roles" {
  local manifest="$CONFIG_DIR/context-manifest.json"
  local roles_with_includes
  roles_with_includes=$(jq -r '.roles | to_entries[] | select(.value.includes) | .key' "$manifest")
  for role in $roles_with_includes; do
    local base_roles
    base_roles=$(jq -r --arg r "$role" '.roles[$r].includes[]' "$manifest")
    for base in $base_roles; do
      run jq -e --arg b "$base" '.roles[$b]' "$manifest"
      assert_success
    done
  done
}

@test "manifest has at least 36 role entries" {
  local manifest="$CONFIG_DIR/context-manifest.json"
  run jq '.roles | keys | length' "$manifest"
  assert_success
  [ "$output" -ge 36 ]
}
