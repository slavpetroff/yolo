#!/usr/bin/env bats
# qa-gate.bats — Unit tests for scripts/qa-gate.sh
# Notification hook (qa-gate): exit 2 = block, exit 0 = allow

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  load '../test_helper/mock_stdin'
  mk_test_workdir
  mk_planning_dir
  mk_git_repo
  SUT="$SCRIPTS_DIR/qa-gate.sh"
}

# Helper: create a phase dir with exact plan/summary file counts (avoids macOS seq issue)
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

# --- Fail-open on edge cases ---

@test "exits 0 on empty stdin" {
  run bash -c "echo -n '' | bash '$SUT'"
  assert_success
}

@test "exits 0 when no .yolo-planning/phases directory exists" {
  rm -rf "$TEST_WORKDIR/.yolo-planning/phases"
  run bash -c "echo '{\"agent_name\":\"yolo-dev\"}' | bash '$SUT'"
  assert_success
}

@test "exits 0 when no plans exist" {
  # phases dir exists but is empty
  run bash -c "echo '{\"agent_name\":\"yolo-dev\"}' | bash '$SUT'"
  assert_success
}

# --- All summaries present ---

@test "allows idle when all plans have matching summaries" {
  mk_phase_exact 1 "setup" 2 2
  mk_recent_commit "feat(01-01): add feature"
  run bash -c "echo '{\"agent_name\":\"yolo-dev\"}' | bash '$SUT'"
  assert_success
}

# --- Summary gap detection ---

@test "blocks when summary gap > 1 even with conventional commits" {
  mk_phase_exact 1 "setup" 3 1
  mk_recent_commit "feat(01-01): add feature"
  run bash -c "echo '{\"agent_name\":\"yolo-dev\"}' | bash '$SUT'"
  assert_failure 2
}

@test "blocks when gap == 1 but no conventional commit format" {
  mk_phase_exact 1 "setup" 2 1
  mk_recent_commit "random commit message"
  run bash -c "echo '{\"agent_name\":\"yolo-dev\"}' | bash '$SUT'"
  assert_failure 2
}

# --- Grace period: gap==1 with recent conventional commit ---

@test "allows gap==1 when recent commit matches conventional format" {
  mk_phase_exact 1 "setup" 2 1
  mk_recent_commit "feat(01-01): implement auth module"
  run bash -c "echo '{\"agent_name\":\"yolo-dev\"}' | bash '$SUT'"
  assert_success
}

@test "grace period works with different commit types (fix, refactor, test)" {
  mk_phase_exact 1 "setup" 2 1
  mk_recent_commit "fix(02-03): resolve edge case"
  run bash -c "echo '{\"agent_name\":\"yolo-dev\"}' | bash '$SUT'"
  assert_success
}

@test "grace period works with chore and docs types" {
  mk_phase_exact 1 "setup" 2 1
  mk_recent_commit "chore(01-02): cleanup config"
  run bash -c "echo '{\"agent_name\":\"yolo-dev\"}' | bash '$SUT'"
  assert_success
}

# --- No grace without conventional commit format ---

@test "no grace when commit format lacks plan number pattern" {
  mk_phase_exact 1 "setup" 2 1
  mk_recent_commit "feat: add something without plan ref"
  run bash -c "echo '{\"agent_name\":\"yolo-dev\"}' | bash '$SUT'"
  assert_failure 2
}

# --- Old commits do not grant grace ---

@test "blocks when only old commits exist (> 2 hours)" {
  mk_phase_exact 1 "setup" 2 1
  mk_recent_commit "feat(01-01): old work" 7300
  run bash -c "echo '{\"agent_name\":\"yolo-dev\"}' | bash '$SUT'"
  assert_failure 2
}

# --- Multiple phases aggregate correctly ---

@test "counts plans and summaries across all phases" {
  mk_phase_exact 1 "setup" 1 1
  mk_phase_exact 2 "build" 2 1
  mk_recent_commit "feat(02-01): partial build"
  # Total: 3 plans, 2 summaries, gap=1, with conventional commit = allow
  run bash -c "echo '{\"agent_name\":\"yolo-dev\"}' | bash '$SUT'"
  assert_success
}

# --- Config-aware behavior ---

# Helper: set up qa-gate.sh in a temp dir with a mock resolve-qa-config.sh
# qa-gate.sh uses BASH_SOURCE to find resolve-qa-config.sh, so both must coexist
setup_config_aware() {
  local qa_config_json="$1"
  local gate_dir="$TEST_WORKDIR/gate-scripts"
  mkdir -p "$gate_dir"
  cp "$SUT" "$gate_dir/qa-gate.sh"

  # Create a mock resolve-qa-config.sh that outputs the given config
  cat > "$gate_dir/resolve-qa-config.sh" <<MOCK
#!/usr/bin/env bash
echo '$qa_config_json'
MOCK
  chmod +x "$gate_dir/resolve-qa-config.sh"

  echo "$gate_dir/qa-gate.sh"
}

@test "skips checks when post_task is disabled in config" {
  # Setup: summary gap > 1 that would normally block
  mk_phase_exact 1 "setup" 3 1
  mk_recent_commit "feat(01-01): add feature"

  local gate_script
  gate_script=$(setup_config_aware '{"post_task":false,"post_plan":true,"post_phase":true,"timeout_seconds":300,"failure_threshold":"critical"}')

  run bash -c "echo '{\"agent_name\":\"yolo-dev\"}' | bash '$gate_script'"
  assert_success
}

@test "runs checks normally when post_task is enabled" {
  # Setup: summary gap > 1 with no conventional commits = would block
  mk_phase_exact 1 "setup" 3 1
  mk_recent_commit "random commit message"

  local gate_script
  gate_script=$(setup_config_aware '{"post_task":true,"post_plan":true,"post_phase":true,"timeout_seconds":300,"failure_threshold":"critical"}')

  run bash -c "echo '{\"agent_name\":\"yolo-dev\"}' | bash '$gate_script'"
  assert_failure 2
}

@test "runs checks when config has no qa_gates key (backward compat)" {
  # Config with empty object (no qa_gates key)
  mk_phase_exact 1 "setup" 3 1
  mk_recent_commit "random commit message"

  # Mock resolve script returns {} (no qa_gates fields)
  local gate_script
  gate_script=$(setup_config_aware '{}')

  run bash -c "echo '{\"agent_name\":\"yolo-dev\"}' | bash '$gate_script'"
  assert_failure 2
}

@test "runs checks when resolve-qa-config.sh is missing (fail-open)" {
  # Summary gap > 1 with no conventional commits = would block
  mk_phase_exact 1 "setup" 3 1
  mk_recent_commit "random commit message"

  # Copy qa-gate.sh to a temp dir WITHOUT resolve-qa-config.sh
  local gate_dir="$TEST_WORKDIR/gate-no-resolve"
  mkdir -p "$gate_dir"
  cp "$SUT" "$gate_dir/qa-gate.sh"
  # Ensure no resolve script exists
  rm -f "$gate_dir/resolve-qa-config.sh"

  run bash -c "echo '{\"agent_name\":\"yolo-dev\"}' | bash '$gate_dir/qa-gate.sh'"
  assert_failure 2
}
