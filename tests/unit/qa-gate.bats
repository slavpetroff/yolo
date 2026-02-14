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
