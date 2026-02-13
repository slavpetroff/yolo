#!/usr/bin/env bats
# skill-hook-dispatch.bats — Unit tests for scripts/skill-hook-dispatch.sh
# Pre/PostToolUse skill dispatch based on config.json skill_hooks

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  load '../test_helper/mock_stdin'
  mk_test_workdir
  mk_planning_dir
  SUT="$SCRIPTS_DIR/skill-hook-dispatch.sh"
}

# --- 1. Exits 0 with no event type ---

@test "exits 0 when no event type argument provided" {
  run bash "$SUT"
  assert_success
}

# --- 2. Exits 0 with empty stdin ---

@test "exits 0 when stdin is empty" {
  run bash -c "cd '$TEST_WORKDIR' && echo '' | bash '$SUT' PostToolUse"
  assert_success
}

# --- 3. Exits 0 when config has no skill_hooks ---

@test "exits 0 when config.json has no skill_hooks" {
  run bash -c "cd '$TEST_WORKDIR' && echo '{\"tool_name\":\"Write\"}' | bash '$SUT' PostToolUse"
  assert_success
}

# --- 4. Exits 0 with skill_hooks but no matching event ---

@test "exits 0 when skill_hooks exist but event type does not match" {
  # Add skill_hooks to config
  jq '. + {"skill_hooks":{"test-skill":{"event":"PostToolUse","tools":"Write|Edit"}}}' \
    "$TEST_WORKDIR/.yolo-planning/config.json" > "$TEST_WORKDIR/.yolo-planning/config.json.tmp" \
    && mv "$TEST_WORKDIR/.yolo-planning/config.json.tmp" "$TEST_WORKDIR/.yolo-planning/config.json"
  run bash -c "cd '$TEST_WORKDIR' && echo '{\"tool_name\":\"Write\"}' | bash '$SUT' PreToolUse"
  assert_success
}

# --- 5. Exits 0 when tool_name does not match ---

@test "exits 0 when tool_name does not match skill_hooks tools pattern" {
  jq '. + {"skill_hooks":{"test-skill":{"event":"PostToolUse","tools":"Write|Edit"}}}' \
    "$TEST_WORKDIR/.yolo-planning/config.json" > "$TEST_WORKDIR/.yolo-planning/config.json.tmp" \
    && mv "$TEST_WORKDIR/.yolo-planning/config.json.tmp" "$TEST_WORKDIR/.yolo-planning/config.json"
  run bash -c "cd '$TEST_WORKDIR' && echo '{\"tool_name\":\"Bash\"}' | bash '$SUT' PostToolUse"
  assert_success
}

# --- 6. Exits 0 when no tool_name in input ---

@test "exits 0 when input JSON lacks tool_name" {
  run bash -c "cd '$TEST_WORKDIR' && echo '{\"other\":\"field\"}' | bash '$SUT' PostToolUse"
  assert_success
}
