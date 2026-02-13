#!/usr/bin/env bats
# post-compact.bats — Unit tests for scripts/post-compact.sh
# SessionStart(compact) hook: post-compaction context restoration

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  load '../test_helper/mock_stdin'
  mk_test_workdir
  mk_planning_dir
  SUT="$SCRIPTS_DIR/post-compact.sh"
}

# --- 1. Outputs valid JSON ---

@test "outputs valid hookSpecificOutput JSON" {
  run bash -c "cd '$TEST_WORKDIR' && echo 'some context about yolo-dev agent' | bash '$SUT'"
  assert_success
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null
}

# --- 2. Detects yolo-dev role ---

@test "detects yolo-dev role and recommends plan files" {
  run bash -c "cd '$TEST_WORKDIR' && echo 'this is yolo-dev agent context' | bash '$SUT'"
  assert_success
  assert_output --partial "yolo-dev"
  assert_output --partial "plan.jsonl"
}

# --- 3. Detects yolo-lead role ---

@test "detects yolo-lead role and recommends STATE.md" {
  run bash -c "cd '$TEST_WORKDIR' && echo 'this is yolo-lead agent context' | bash '$SUT'"
  assert_success
  assert_output --partial "yolo-lead"
  assert_output --partial "STATE.md"
}

# --- 4. Detects yolo-qa role ---

@test "detects yolo-qa role and recommends summary files" {
  run bash -c "cd '$TEST_WORKDIR' && echo 'this is yolo-qa agent doing reviews' | bash '$SUT'"
  assert_success
  assert_output --partial "yolo-qa"
  assert_output --partial "summary"
}

# --- 5. Falls back to unknown for unrecognized role ---

@test "falls back to unknown role for unrecognized input" {
  run bash -c "cd '$TEST_WORKDIR' && echo 'generic session context' | bash '$SUT'"
  assert_success
  assert_output --partial "unknown"
  assert_output --partial "STATE.md"
}

# --- 6. Cleans cost tracking files ---

@test "removes .cost-ledger.json and .active-agent after compaction" {
  echo '{"dev":100}' > "$TEST_WORKDIR/.yolo-planning/.cost-ledger.json"
  echo "yolo-dev" > "$TEST_WORKDIR/.yolo-planning/.active-agent"
  run bash -c "cd '$TEST_WORKDIR' && echo 'compaction context' | bash '$SUT'"
  assert_success
  assert_file_not_exists "$TEST_WORKDIR/.yolo-planning/.cost-ledger.json"
  assert_file_not_exists "$TEST_WORKDIR/.yolo-planning/.active-agent"
}
