#!/usr/bin/env bats
# compaction-instructions.bats — Unit tests for scripts/compaction-instructions.sh
# PreCompact hook: agent-specific summarization priorities

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  load '../test_helper/mock_stdin'
  mk_test_workdir
  mk_planning_dir
  SUT="$SCRIPTS_DIR/compaction-instructions.sh"
}

# --- 1. Outputs valid JSON ---

@test "outputs valid hookSpecificOutput JSON" {
  run bash -c "cd '$TEST_WORKDIR' && echo '{\"agent_name\":\"yolo-dev\",\"matcher\":\"auto\"}' | bash '$SUT'"
  assert_success
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null
}

# --- 2. Dev agent priorities include commit hashes ---

@test "dev agent priorities include commit hashes and file paths" {
  run bash -c "cd '$TEST_WORKDIR' && echo '{\"agent_name\":\"yolo-dev\",\"matcher\":\"auto\"}' | bash '$SUT'"
  assert_success
  assert_output --partial "commit hashes"
  assert_output --partial "file paths"
}

# --- 3. QA agent priorities include pass/fail ---

@test "qa agent priorities include pass/fail status" {
  run bash -c "cd '$TEST_WORKDIR' && echo '{\"agent_name\":\"yolo-qa\",\"matcher\":\"auto\"}' | bash '$SUT'"
  assert_success
  assert_output --partial "pass/fail"
}

# --- 4. Manual compaction noted ---

@test "notes when user requested manual compaction" {
  run bash -c "cd '$TEST_WORKDIR' && echo '{\"agent_name\":\"yolo-dev\",\"matcher\":\"manual\"}' | bash '$SUT'"
  assert_success
  assert_output --partial "User requested compaction"
}

# --- 5. Auto compaction noted ---

@test "notes automatic compaction at context limit" {
  run bash -c "cd '$TEST_WORKDIR' && echo '{\"agent_name\":\"yolo-dev\",\"matcher\":\"auto\"}' | bash '$SUT'"
  assert_success
  assert_output --partial "automatic compaction"
}

# --- 6. Writes compaction marker ---

@test "creates .compaction-marker file" {
  run bash -c "cd '$TEST_WORKDIR' && echo '{\"agent_name\":\"yolo-dev\",\"matcher\":\"auto\"}' | bash '$SUT'"
  assert_success
  assert_file_exists "$TEST_WORKDIR/.yolo-planning/.compaction-marker"
}
