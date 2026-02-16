#!/usr/bin/env bats
# resolve-tool-permissions.bats — Unit tests for tool permission resolution
# Tests config validation, permission resolution, fallbacks, error handling,
# and protected tools guard.

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  load '../test_helper/mock_stdin'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/resolve-tool-permissions.sh"
  TOOL_PERMS_CONFIG="$CONFIG_DIR/tool-permissions.json"
  # Override CLAUDE_CONFIG_DIR to avoid real skills
  export CLAUDE_CONFIG_DIR="$TEST_WORKDIR/mock-claude"
  mkdir -p "$CLAUDE_CONFIG_DIR/skills"
}

# Helper: run resolve-tool-permissions with test workdir as project-dir
run_resolve() {
  run bash "$SUT" --role "$1" --project-dir "$TEST_WORKDIR" --config "$TOOL_PERMS_CONFIG"
}

# =====================
# Config validation tests
# =====================

@test "tool-permissions.json exists and is valid JSON" {
  run jq -e '.' "$TOOL_PERMS_CONFIG"
  assert_success
}

@test "tool-permissions.json has all 7 project type entries" {
  run jq '.types | keys | length' "$TOOL_PERMS_CONFIG"
  assert_success
  assert_output "7"

  # Verify exact keys
  run jq -r '.types | keys[]' "$TOOL_PERMS_CONFIG"
  assert_success
  assert_line --index 0 "api-service"
  assert_line --index 1 "cli-tool"
  assert_line --index 2 "generic"
  assert_line --index 3 "library"
  assert_line --index 4 "mobile-app"
  assert_line --index 5 "monorepo"
  assert_line --index 6 "web-app"
}

@test "tool-permissions.json: no protected tool in any remove_tools" {
  run jq '[.types[][].remove_tools // [] | .[] | select(. == "Bash" or . == "Read" or . == "Glob" or . == "Grep" or . == "Write" or . == "Edit")] | length' "$TOOL_PERMS_CONFIG"
  assert_success
  assert_output "0"
}

@test "tool-permissions.json: generic type has empty overrides" {
  run jq '.types.generic | length' "$TOOL_PERMS_CONFIG"
  assert_success
  assert_output "0"
}

@test "tool-permissions.json: cli-tool lead removes WebFetch" {
  run jq '.types["cli-tool"].lead.remove_tools | index("WebFetch")' "$TOOL_PERMS_CONFIG"
  assert_success
  refute_output "null"
}

# =====================
# Resolution tests
# =====================

@test "generic project: dev tools unchanged" {
  # Empty TEST_WORKDIR = generic project
  run_resolve dev
  assert_success

  local output_json="$output"
  run jq -r '.project_type' <<< "$output_json"
  assert_output "generic"

  # dev base tools: Read, Glob, Grep, Write, Edit, Bash
  run jq -r '.tools | sort | join(",")' <<< "$output_json"
  assert_output "Bash,Edit,Glob,Grep,Read,Write"
}

@test "cli-tool project: lead loses WebFetch" {
  # Create bin/ + scripts/ to trigger cli-tool detection
  mkdir -p "$TEST_WORKDIR/bin" "$TEST_WORKDIR/scripts"

  run_resolve lead
  assert_success

  local output_json="$output"

  # WebFetch should NOT be in tools
  run jq '[.tools[] | select(. == "WebFetch")] | length' <<< "$output_json"
  assert_output "0"

  # WebFetch should be in disallowed_tools
  run jq '[.disallowed_tools[] | select(. == "WebFetch")] | length' <<< "$output_json"
  refute_output "0"
}

@test "library project: lead loses WebFetch" {
  # Create src/lib.rs + Cargo.toml to trigger library detection
  mkdir -p "$TEST_WORKDIR/src"
  touch "$TEST_WORKDIR/src/lib.rs"
  touch "$TEST_WORKDIR/Cargo.toml"

  run_resolve lead
  assert_success

  local output_json="$output"

  # WebFetch should NOT be in tools
  run jq '[.tools[] | select(. == "WebFetch")] | length' <<< "$output_json"
  assert_output "0"
}

@test "web-app project: architect keeps all tools" {
  # Create package.json with react dep
  echo '{"dependencies":{"react":"^18.0.0"}}' > "$TEST_WORKDIR/package.json"

  run_resolve architect
  assert_success

  local output_json="$output"

  # Architect should still have WebSearch and WebFetch
  run jq '[.tools[] | select(. == "WebSearch")] | length' <<< "$output_json"
  assert_output "1"
  run jq '[.tools[] | select(. == "WebFetch")] | length' <<< "$output_json"
  assert_output "1"
}

@test "unknown project type falls back to generic" {
  # Create a mock detect-stack.sh that returns unknown type
  local mock_dir="$TEST_WORKDIR/mock-scripts"
  mkdir -p "$mock_dir"
  cat > "$mock_dir/detect-stack.sh" <<'MOCKEOF'
#!/usr/bin/env bash
echo '{"project_type":"unknown-type","detected_stack":[]}'
MOCKEOF
  chmod +x "$mock_dir/detect-stack.sh"

  # Create a wrapper SUT that uses the mock detect-stack.sh
  local wrapper="$TEST_WORKDIR/wrapper-resolve.sh"
  # Replace the SCRIPT_DIR to point to mock
  sed "s|SCRIPT_DIR=.*|SCRIPT_DIR=\"$mock_dir\"|" "$SUT" > "$wrapper"
  # But we still need the agents dir and config
  sed -i.bak "s|AGENTS_DIR=.*|AGENTS_DIR=\"$AGENTS_DIR\"|" "$wrapper"
  chmod +x "$wrapper"

  run bash "$wrapper" --role dev --project-dir "$TEST_WORKDIR" --config "$TOOL_PERMS_CONFIG"
  assert_success

  local output_json="$output"
  run jq -r '.project_type' <<< "$output_json"
  assert_output "generic"

  # Dev tools should be unchanged (same as generic)
  run jq -r '.tools | sort | join(",")' <<< "$output_json"
  assert_output "Bash,Edit,Glob,Grep,Read,Write"
}

@test "role not in overrides gets base tools unchanged" {
  # cli-tool project, but dev has no overrides in cli-tool
  mkdir -p "$TEST_WORKDIR/bin" "$TEST_WORKDIR/scripts"

  run_resolve dev
  assert_success

  local output_json="$output"
  # Dev tools should be the base set (no overrides for dev in cli-tool)
  run jq -r '.tools | sort | join(",")' <<< "$output_json"
  assert_output "Bash,Edit,Glob,Grep,Read,Write"
}

# =====================
# Protected tools tests
# =====================

@test "protected tools never removed even if in config" {
  # Create temp config with Bash in remove_tools for generic.dev
  local bad_config="$TEST_WORKDIR/bad-permissions.json"
  cat > "$bad_config" <<'JSONEOF'
{
  "_description": "test config",
  "_protected_tools": ["Bash","Read","Glob","Grep","Write","Edit"],
  "types": {
    "generic": {
      "dev": {
        "add_tools": [],
        "remove_tools": ["Bash"]
      }
    },
    "web-app": {},
    "api-service": {},
    "cli-tool": {},
    "library": {},
    "mobile-app": {},
    "monorepo": {}
  }
}
JSONEOF

  run bash "$SUT" --role dev --project-dir "$TEST_WORKDIR" --config "$bad_config"
  assert_success

  local output_json="$output"
  # Bash should still be in tools
  run jq '[.tools[] | select(. == "Bash")] | length' <<< "$output_json"
  assert_output "1"
}

# =====================
# Always-disallowed tests
# =====================

@test "EnterPlanMode and ExitPlanMode always in disallowed_tools" {
  run_resolve dev
  assert_success

  local output_json="$output"
  run jq '[.disallowed_tools[] | select(. == "EnterPlanMode")] | length' <<< "$output_json"
  assert_output "1"
  run jq '[.disallowed_tools[] | select(. == "ExitPlanMode")] | length' <<< "$output_json"
  assert_output "1"
}

# =====================
# Error handling tests
# =====================

@test "exits 1 with no arguments" {
  run bash "$SUT"
  assert_failure
  assert_output --partial "Usage"
}

@test "exits 1 for nonexistent agent role" {
  run bash "$SUT" --role nonexistent-role --project-dir "$TEST_WORKDIR"
  assert_failure
  assert_output --partial "Agent file not found"
}

@test "exits 1 for missing config file" {
  run bash "$SUT" --role dev --project-dir "$TEST_WORKDIR" --config /nonexistent/config.json
  assert_failure
}

# =====================
# Output format test
# =====================

@test "output is valid JSON with expected keys" {
  run_resolve dev
  assert_success

  local output_json="$output"
  run jq -e '.role and .project_type and .base_tools and .tools and .disallowed_tools' <<< "$output_json"
  assert_success
}
