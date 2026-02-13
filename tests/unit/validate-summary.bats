#!/usr/bin/env bats
# validate-summary.bats — Unit tests for scripts/validate-summary.sh
# PostToolUse/SubagentStop, non-blocking (always exit 0)

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  load '../test_helper/mock_stdin'
  mk_test_workdir
  mk_planning_dir
  SUT="$SCRIPTS_DIR/validate-summary.sh"
}

# --- Ignores non-summary files ---

@test "exits 0 for non-summary file path" {
  run bash -c "echo '{\"tool_input\":{\"file_path\":\"src/foo.ts\"}}' | bash '$SUT'"
  assert_success
  refute_output --partial "hookSpecificOutput"
}

@test "exits 0 for plan file path" {
  run bash -c "echo '{\"tool_input\":{\"file_path\":\".yolo-planning/phases/01-setup/01-01.plan.jsonl\"}}' | bash '$SUT'"
  assert_success
  refute_output --partial "hookSpecificOutput"
}

# --- JSONL validation ---

@test "valid JSONL summary passes without warning" {
  local dir="$TEST_WORKDIR/.yolo-planning/phases/01-setup"
  mkdir -p "$dir"
  cp "$FIXTURES_DIR/summaries/valid-summary.jsonl" "$dir/01-01.summary.jsonl"

  run bash -c "echo '{\"tool_input\":{\"file_path\":\"$dir/01-01.summary.jsonl\"}}' | bash '$SUT'"
  assert_success
  refute_output --partial "hookSpecificOutput"
}

@test "JSONL summary missing p field reports warning" {
  local dir="$TEST_WORKDIR/.yolo-planning/phases/01-setup"
  mkdir -p "$dir"
  cp "$FIXTURES_DIR/summaries/missing-p-summary.jsonl" "$dir/01-01.summary.jsonl"

  run bash -c "echo '{\"tool_input\":{\"file_path\":\"$dir/01-01.summary.jsonl\"}}' | bash '$SUT'"
  assert_success
  assert_output --partial "hookSpecificOutput"
  assert_output --partial "Missing 'p'"
}

@test "JSONL summary missing s field reports warning" {
  local dir="$TEST_WORKDIR/.yolo-planning/phases/01-setup"
  mkdir -p "$dir"
  echo '{"p":"01","fm":["src/foo.ts"]}' > "$dir/01-01.summary.jsonl"

  run bash -c "echo '{\"tool_input\":{\"file_path\":\"$dir/01-01.summary.jsonl\"}}' | bash '$SUT'"
  assert_success
  assert_output --partial "Missing 's'"
}

@test "JSONL summary missing fm field reports warning" {
  local dir="$TEST_WORKDIR/.yolo-planning/phases/01-setup"
  mkdir -p "$dir"
  echo '{"p":"01","s":"complete"}' > "$dir/01-01.summary.jsonl"

  run bash -c "echo '{\"tool_input\":{\"file_path\":\"$dir/01-01.summary.jsonl\"}}' | bash '$SUT'"
  assert_success
  assert_output --partial "Missing 'fm'"
}

# --- Legacy MD validation ---

@test "valid legacy MD summary passes without warning" {
  local dir="$TEST_WORKDIR/.yolo-planning/phases/01-setup"
  mkdir -p "$dir"
  cp "$FIXTURES_DIR/summaries/valid-summary.md" "$dir/01-01-SUMMARY.md"

  run bash -c "echo '{\"tool_input\":{\"file_path\":\"$dir/01-01-SUMMARY.md\"}}' | bash '$SUT'"
  assert_success
  refute_output --partial "hookSpecificOutput"
}

@test "legacy MD summary missing frontmatter reports warning" {
  local dir="$TEST_WORKDIR/.yolo-planning/phases/01-setup"
  mkdir -p "$dir"
  cp "$FIXTURES_DIR/summaries/missing-frontmatter.md" "$dir/01-01-SUMMARY.md"

  run bash -c "echo '{\"tool_input\":{\"file_path\":\"$dir/01-01-SUMMARY.md\"}}' | bash '$SUT'"
  assert_success
  assert_output --partial "Missing YAML frontmatter"
}

@test "legacy MD summary missing What Was Built reports warning" {
  local dir="$TEST_WORKDIR/.yolo-planning/phases/01-setup"
  mkdir -p "$dir"
  cat > "$dir/01-01-SUMMARY.md" <<'EOF'
---
phase: "01"
plan: "01-01"
status: complete
---

## Files Modified
- src/foo.ts
EOF

  run bash -c "echo '{\"tool_input\":{\"file_path\":\"$dir/01-01-SUMMARY.md\"}}' | bash '$SUT'"
  assert_success
  assert_output --partial "Missing '## What Was Built'"
}

@test "legacy MD summary missing Files Modified reports warning" {
  local dir="$TEST_WORKDIR/.yolo-planning/phases/01-setup"
  mkdir -p "$dir"
  cat > "$dir/01-01-SUMMARY.md" <<'EOF'
---
phase: "01"
plan: "01-01"
status: complete
---

## What Was Built
Something useful
EOF

  run bash -c "echo '{\"tool_input\":{\"file_path\":\"$dir/01-01-SUMMARY.md\"}}' | bash '$SUT'"
  assert_success
  assert_output --partial "Missing '## Files Modified'"
}

# --- Always exits 0 ---

@test "exits 0 when summary file does not exist on disk" {
  run bash -c "echo '{\"tool_input\":{\"file_path\":\".yolo-planning/nonexistent/01-01.summary.jsonl\"}}' | bash '$SUT'"
  assert_success
}
