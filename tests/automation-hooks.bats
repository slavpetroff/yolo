#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
}

teardown() {
  teardown_temp_dir
}

# Helper: enable a feature flag in test config
enable_flag() {
  local flag="$1"
  local config="$TEST_TEMP_DIR/.yolo-planning/config.json"
  local tmp="$config.tmp"
  jq --arg f "$flag" '.[$f] = true' "$config" > "$tmp" && mv "$tmp" "$config"
}

# =============================================================================
# Post-edit test validation (v4_post_edit_test_check)
# =============================================================================

@test "post-edit: no output when feature flag disabled (default)" {
  INPUT='{"tool_name":"Write","tool_input":{"file_path":"/project/src/main.rs"}}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | '$YOLO_BIN' hook PostToolUse"
  [ "$status" -eq 0 ]
  # With flag disabled, test_validation returns null — no advisory
  # (validate_summary also returns null for non-SUMMARY files)
  [ -z "$output" ] || ! echo "$output" | grep -q "test file"
}

@test "post-edit: advisory when editing source file with no test (flag enabled)" {
  enable_flag "v4_post_edit_test_check"
  INPUT='{"tool_name":"Write","tool_input":{"file_path":"/project/src/main.rs"}}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | '$YOLO_BIN' hook PostToolUse"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "No test file found"
}

@test "post-edit: advisory when editing source file with existing test" {
  enable_flag "v4_post_edit_test_check"
  # Create a source file and its test
  mkdir -p "$TEST_TEMP_DIR/src" "$TEST_TEMP_DIR/tests"
  touch "$TEST_TEMP_DIR/src/dispatcher.rs"
  touch "$TEST_TEMP_DIR/tests/dispatcher.bats"
  INPUT="{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TEST_TEMP_DIR/src/dispatcher.rs\"}}"
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | '$YOLO_BIN' hook PostToolUse"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Test file exists"
}

@test "post-edit: no output for non-Write/Edit PostToolUse events" {
  enable_flag "v4_post_edit_test_check"
  INPUT='{"tool_name":"Bash","tool_input":{"command":"ls"}}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | '$YOLO_BIN' hook PostToolUse"
  [ "$status" -eq 0 ]
  [ -z "$output" ] || ! echo "$output" | grep -q "test file"
}

@test "post-edit: skips non-source files (markdown, json, tests)" {
  enable_flag "v4_post_edit_test_check"
  # Markdown
  INPUT='{"tool_name":"Write","tool_input":{"file_path":"/project/README.md"}}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | '$YOLO_BIN' hook PostToolUse"
  [ "$status" -eq 0 ]
  [ -z "$output" ] || ! echo "$output" | grep -q "test file"

  # Test file
  INPUT='{"tool_name":"Write","tool_input":{"file_path":"/project/tests/foo.bats"}}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | '$YOLO_BIN' hook PostToolUse"
  [ "$status" -eq 0 ]
  [ -z "$output" ] || ! echo "$output" | grep -q "test file"
}

@test "post-edit: always exits 0 (advisory)" {
  enable_flag "v4_post_edit_test_check"
  INPUT='{"tool_name":"Write","tool_input":{"file_path":"/project/src/main.rs"}}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | '$YOLO_BIN' hook PostToolUse"
  [ "$status" -eq 0 ]
}

# =============================================================================
# Session-start cache warming (v4_session_cache_warm)
# =============================================================================

@test "cache-warm: no cache file when flag disabled (default)" {
  INPUT='{}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | '$YOLO_BIN' hook SessionStart"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TEMP_DIR/.yolo-planning/.context-cache/tier1.md" ]
}

@test "cache-warm: cache file created when flag enabled" {
  enable_flag "v4_session_cache_warm"
  # Create codebase files for tier 1
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning/codebase"
  echo "Convention rules" > "$TEST_TEMP_DIR/.yolo-planning/codebase/CONVENTIONS.md"
  echo "Stack: Rust" > "$TEST_TEMP_DIR/.yolo-planning/codebase/STACK.md"
  INPUT='{}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | '$YOLO_BIN' hook SessionStart"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/.yolo-planning/.context-cache/tier1.md" ]
}

@test "cache-warm: cache file contains tier 1 content" {
  enable_flag "v4_session_cache_warm"
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning/codebase"
  echo "Convention rules" > "$TEST_TEMP_DIR/.yolo-planning/codebase/CONVENTIONS.md"
  echo "Stack: Rust" > "$TEST_TEMP_DIR/.yolo-planning/codebase/STACK.md"
  INPUT='{}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | '$YOLO_BIN' hook SessionStart"
  [ "$status" -eq 0 ]
  local cache="$TEST_TEMP_DIR/.yolo-planning/.context-cache/tier1.md"
  [ -f "$cache" ]
  grep -q "TIER 1: SHARED BASE" "$cache"
  grep -q "cached:" "$cache"
}

@test "cache-warm: session start always succeeds even with cache warming" {
  enable_flag "v4_session_cache_warm"
  # No codebase files — cache warming should silently skip
  INPUT='{}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | '$YOLO_BIN' hook SessionStart"
  [ "$status" -eq 0 ]
}
