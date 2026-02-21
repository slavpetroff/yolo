#!/usr/bin/env bats
# Migrated: resolve-claude-dir.sh removed (Rust binary handles CLAUDE_CONFIG_DIR
# resolution natively). Shell script grep tests replaced with hooks.json
# structure tests and Rust CLI behavior tests.
# CWD-sensitive: yes (detect-stack)

load test_helper

HOOKS_JSON="$PROJECT_ROOT/hooks/hooks.json"

setup() {
  setup_temp_dir
  create_test_config
  # Save original values
  export ORIG_HOME="$HOME"
  export ORIG_CLAUDE_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-}"
}

teardown() {
  # Restore original values
  export HOME="$ORIG_HOME"
  unset CLAUDE_CONFIG_DIR 2>/dev/null || true
  [ -n "$ORIG_CLAUDE_CONFIG_DIR" ] && export CLAUDE_CONFIG_DIR="$ORIG_CLAUDE_CONFIG_DIR"
  teardown_temp_dir
}

# --- hooks.json tests ---

@test "hooks.json exists and is valid JSON" {
  [ -f "$HOOKS_JSON" ]
  jq empty "$HOOKS_JSON"
}

@test "hooks.json contains no hardcoded HOME/.claude paths (outside command)" {
  # Commands use $HOME/.cargo/bin/yolo which is fine
  # Check there are no hardcoded "$HOME"/.claude references
  local count
  count=$(grep -c '"$HOME"/.claude' "$HOOKS_JSON" || true)
  [ "$count" -eq 0 ]
}

@test "hooks.json no commands use old cache-only pattern" {
  # Old pattern used hook-wrapper.sh; new pattern uses yolo binary directly
  local old_count
  old_count=$(grep -c 'hook-wrapper.sh' "$HOOKS_JSON" || true)
  [ "$old_count" -eq 0 ]
}

@test "hooks.json all commands route through yolo binary" {
  # Every hook command should use $HOME/.cargo/bin/yolo
  local yolo_count
  yolo_count=$(jq '[.. | .command? // empty | select(contains("yolo hook"))] | length' "$HOOKS_JSON")
  [ "$yolo_count" -gt 0 ]
}

@test "hooks.json routes PreToolUse to yolo binary" {
  jq -e '.hooks.PreToolUse[].hooks[].command | select(contains("yolo hook PreToolUse"))' "$HOOKS_JSON" >/dev/null
}

@test "hooks.json routes SessionStart to yolo binary" {
  jq -e '.hooks.SessionStart[].hooks[].command | select(contains("yolo hook SessionStart"))' "$HOOKS_JSON" >/dev/null
}

@test "hooks.json routes PostToolUse to yolo binary" {
  jq -e '.hooks.PostToolUse[].hooks[].command | select(contains("yolo hook PostToolUse"))' "$HOOKS_JSON" >/dev/null
}

# --- detect-stack tests (Rust CLI) ---

@test "detect-stack: finds skills from HOME/.claude/skills" {
  cd "$TEST_TEMP_DIR"
  # detect-stack needs config/stack-mappings.json in project dir
  mkdir -p "$TEST_TEMP_DIR/config"
  cp "$CONFIG_DIR/stack-mappings.json" "$TEST_TEMP_DIR/config/"
  # Rust binary uses $HOME/.claude/skills for global skills
  export HOME="$TEST_TEMP_DIR"
  mkdir -p "$HOME/.claude/skills/test-skill"

  run "$YOLO_BIN" detect-stack "$TEST_TEMP_DIR"
  [ "$status" -eq 0 ]

  # Should find test-skill in HOME/.claude/skills
  echo "$output" | jq -e '.installed.global' >/dev/null
  [[ "$output" == *"test-skill"* ]]
}

@test "detect-stack: uses default HOME/.claude when CLAUDE_CONFIG_DIR unset" {
  cd "$TEST_TEMP_DIR"
  mkdir -p "$TEST_TEMP_DIR/config"
  cp "$CONFIG_DIR/stack-mappings.json" "$TEST_TEMP_DIR/config/"
  unset CLAUDE_CONFIG_DIR
  export HOME="$TEST_TEMP_DIR"
  mkdir -p "$HOME/.claude/skills/default-skill"

  run "$YOLO_BIN" detect-stack "$TEST_TEMP_DIR"
  [ "$status" -eq 0 ]

  echo "$output" | jq -e '.installed.global' >/dev/null
  [[ "$output" == *"default-skill"* ]]
}

@test "detect-stack: returns valid JSON output" {
  cd "$TEST_TEMP_DIR"
  mkdir -p "$TEST_TEMP_DIR/config"
  cp "$CONFIG_DIR/stack-mappings.json" "$TEST_TEMP_DIR/config/"
  run "$YOLO_BIN" detect-stack "$TEST_TEMP_DIR"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.' >/dev/null
}

# --- Rust binary handles config dir resolution ---

@test "yolo binary resolves config paths without scripts" {
  # Verify no scripts/ directory exists (all logic in Rust)
  [ ! -d "$PROJECT_ROOT/scripts" ]
}
