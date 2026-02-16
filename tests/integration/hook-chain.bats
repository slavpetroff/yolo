#!/usr/bin/env bats
# hook-chain.bats — Integration tests: hook chain for each event type
# Verifies correct scripts fire in order by checking their side effects.

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  load '../test_helper/mock_stdin'
  mk_test_workdir
  mk_planning_dir
}

# Helper: create a phase with exact plan/summary counts
mk_phase_exact() {
  local num="$1" slug="$2" plans="$3" summaries="$4"
  local dir="$TEST_WORKDIR/.yolo-planning/phases/$(printf '%02d' "$num")-${slug}"
  mkdir -p "$dir"
  local i
  for ((i = 1; i <= plans; i++)); do
    cp "$FIXTURES_DIR/plans/valid-plan.jsonl" "$dir/$(printf '%02d-%02d' "$num" "$i").plan.jsonl"
  done
  for ((i = 1; i <= summaries; i++)); do
    cp "$FIXTURES_DIR/summaries/valid-summary.jsonl" "$dir/$(printf '%02d-%02d' "$num" "$i").summary.jsonl"
  done
  echo "$dir"
}

# --- PreToolUse: security-filter blocks .env ---

@test "PreToolUse: security-filter blocks .env file with JSON deny" {
  run bash -c "cd '$TEST_WORKDIR' && echo '{\"tool_input\":{\"file_path\":\".env\"}}' | bash '$SCRIPTS_DIR/security-filter.sh'"
  assert_success
  assert_output --partial "This file is protected"
  assert_output --partial "permissionDecision"
}

# --- PreToolUse: file-guard blocks undeclared file ---

@test "PreToolUse: file-guard blocks undeclared file with JSON deny" {
  # Create an active plan (plan without summary)
  local dir
  dir=$(mk_phase_exact 1 setup 1 0)

  # file-guard requires execution state with status=running
  echo '{"status":"running","phase":1}' > "$TEST_WORKDIR/.yolo-planning/.execution-state.json"

  run bash -c "cd '$TEST_WORKDIR' && echo '{\"tool_input\":{\"file_path\":\"src/undeclared.ts\"}}' | bash '$SCRIPTS_DIR/file-guard.sh'"
  assert_success
  assert_output --partial "not in active plan"
  assert_output --partial "permissionDecision"
}

# --- PostToolUse: validate-summary runs on Write to .summary.jsonl ---

@test "PostToolUse: validate-summary reports missing fields via hookSpecificOutput" {
  # Create a summary file missing the 'p' field
  local dir="$TEST_WORKDIR/.yolo-planning/phases/01-setup"
  mkdir -p "$dir"
  echo '{"n":"01-01","s":"complete","fm":["src/foo.ts"]}' > "$dir/01-01.summary.jsonl"

  run bash -c "cd '$TEST_WORKDIR' && echo '{\"tool_input\":{\"file_path\":\"$dir/01-01.summary.jsonl\"}}' | bash '$SCRIPTS_DIR/validate-summary.sh'"
  assert_success
  assert_output --partial "hookSpecificOutput"
  assert_output --partial "Missing 'p'"
}

# --- PostToolUse: validate-commit runs on Bash with git commit ---

@test "PostToolUse: validate-commit reports bad commit format via hookSpecificOutput" {
  run bash -c "cd '$TEST_WORKDIR' && echo '{\"tool_input\":{\"command\":\"git commit -m \\\"bad format message\\\"\"}}' | bash '$SCRIPTS_DIR/validate-commit.sh'"
  assert_success
  assert_output --partial "hookSpecificOutput"
  assert_output --partial "does not match format"
}

# --- PostToolUse: state-updater runs on Write to plan files ---

@test "PostToolUse: state-updater updates STATE.md on plan write" {
  mk_state_md 1 2
  mk_state_json 1 2 "planning"
  mk_execution_state "01" "01-01"

  local dir
  dir=$(mk_phase_exact 1 setup 1 0)

  run bash -c "cd '$TEST_WORKDIR' && echo '{\"tool_input\":{\"file_path\":\"$dir/01-01.plan.jsonl\"}}' | bash '$SCRIPTS_DIR/state-updater.sh'"
  assert_success

  run grep "^Plans:" "$TEST_WORKDIR/.yolo-planning/STATE.md"
  assert_output "Plans: 0/1"
}

# --- SubagentStart: agent-start records active agent ---

@test "SubagentStart: agent-start creates .active-agent marker" {
  run bash -c "cd '$TEST_WORKDIR' && echo '{\"agent_type\":\"yolo-dev\"}' | bash '$SCRIPTS_DIR/agent-start.sh'"
  assert_success

  assert_file_exists "$TEST_WORKDIR/.yolo-planning/.active-agent"

  run cat "$TEST_WORKDIR/.yolo-planning/.active-agent"
  assert_output "yolo-dev"
}

# --- SubagentStop: agent-stop clears active agent ---

@test "SubagentStop: agent-stop removes .active-agent marker" {
  # Create the marker first
  echo "dev" > "$TEST_WORKDIR/.yolo-planning/.active-agent"
  assert_file_exists "$TEST_WORKDIR/.yolo-planning/.active-agent"

  run bash -c "cd '$TEST_WORKDIR' && bash '$SCRIPTS_DIR/agent-stop.sh'"
  assert_success

  assert_file_not_exists "$TEST_WORKDIR/.yolo-planning/.active-agent"
}

# --- Notification: qa-gate enforces summary completeness ---

@test "Notification: qa-gate blocks when summary gap exceeds threshold" {
  mk_git_repo
  mk_planning_dir

  # Create 3 plans but only 1 summary (gap=2, exceeds grace period)
  mk_phase_exact 1 setup 3 1

  # Add a conventional commit so only the gap size matters
  mk_recent_commit "feat(01-01): add feature"

  run bash -c "cd '$TEST_WORKDIR' && echo '{\"agent_name\":\"yolo-dev\"}' | bash '$SCRIPTS_DIR/qa-gate.sh'"
  assert_failure 2
  assert_output --partial "SUMMARY.md gap detected"
}
