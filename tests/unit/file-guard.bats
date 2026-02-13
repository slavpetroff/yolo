#!/usr/bin/env bats
# file-guard.bats — Unit tests for scripts/file-guard.sh
# PreToolUse hook, fail-OPEN (exit 0 on errors)

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  load '../test_helper/mock_stdin'
  mk_test_workdir
  mk_planning_dir
  SUT="$SCRIPTS_DIR/file-guard.sh"
}

# Helper: create a phase dir with a plan but no summary (manually to avoid seq bug)
mk_active_plan() {
  local dir="$TEST_WORKDIR/.yolo-planning/phases/01-setup"
  mkdir -p "$dir"
  cp "$FIXTURES_DIR/plans/valid-plan.jsonl" "$dir/01-01.plan.jsonl"
  echo "$dir"
}

# Helper: create a completed plan (plan + summary)
mk_completed_plan() {
  local dir="$TEST_WORKDIR/.yolo-planning/phases/01-setup"
  mkdir -p "$dir"
  cp "$FIXTURES_DIR/plans/valid-plan.jsonl" "$dir/01-01.plan.jsonl"
  cp "$FIXTURES_DIR/summaries/valid-summary.jsonl" "$dir/01-01.summary.jsonl"
  echo "$dir"
}

# --- Fail-open on edge cases ---

@test "exits 0 on empty stdin" {
  run bash -c "echo -n '' | bash '$SUT'"
  assert_success
}

@test "exits 0 when file_path is missing" {
  run bash -c "echo '{\"tool_input\":{\"content\":\"hello\"}}' | bash '$SUT'"
  assert_success
}

@test "exits 0 when no .yolo-planning/phases directory exists" {
  rm -rf "$TEST_WORKDIR/.yolo-planning/phases"
  run bash -c "echo '{\"tool_input\":{\"file_path\":\"src/foo.ts\"}}' | bash '$SUT'"
  assert_success
}

@test "exits 0 when no active plan exists (all plans have summaries)" {
  mk_completed_plan
  run bash -c "echo '{\"tool_input\":{\"file_path\":\"src/unknown.ts\"}}' | bash '$SUT'"
  assert_success
}

@test "exits 0 when active plan has empty fm array" {
  local dir="$TEST_WORKDIR/.yolo-planning/phases/01-setup"
  mkdir -p "$dir"
  cp "$FIXTURES_DIR/plans/no-fm-plan.jsonl" "$dir/01-01.plan.jsonl"
  run bash -c "echo '{\"tool_input\":{\"file_path\":\"src/anything.ts\"}}' | bash '$SUT'"
  assert_success
}

# --- Planning artifacts always allowed ---

@test "allows .yolo-planning/ paths regardless of plan" {
  mk_active_plan
  run bash -c "echo '{\"tool_input\":{\"file_path\":\".yolo-planning/state.json\"}}' | bash '$SUT'"
  assert_success
}

@test "allows SUMMARY.md regardless of plan" {
  mk_active_plan
  run bash -c "echo '{\"tool_input\":{\"file_path\":\".yolo-planning/phases/01-setup/01-01-SUMMARY.md\"}}' | bash '$SUT'"
  assert_success
}

@test "allows STATE.md and CLAUDE.md regardless of plan" {
  mk_active_plan
  run bash -c "echo '{\"tool_input\":{\"file_path\":\"CLAUDE.md\"}}' | bash '$SUT'"
  assert_success
}

# --- JSONL plan format: declared files allowed, undeclared blocked ---

@test "allows file declared in JSONL plan fm array" {
  mk_active_plan
  run bash -c "echo '{\"tool_input\":{\"file_path\":\"src/foo.ts\"}}' | bash '$SUT'"
  assert_success
}

@test "blocks file NOT declared in JSONL plan fm array" {
  mk_active_plan
  run bash -c "echo '{\"tool_input\":{\"file_path\":\"src/unknown.ts\"}}' | bash '$SUT'"
  assert_failure 2
}

# --- Path normalization ---

@test "normalizes ./prefix to match declared files" {
  mk_active_plan
  run bash -c "echo '{\"tool_input\":{\"file_path\":\"./src/foo.ts\"}}' | bash '$SUT'"
  assert_success
}

@test "normalizes absolute path to match declared files" {
  mk_active_plan
  run bash -c "echo '{\"tool_input\":{\"file_path\":\"$TEST_WORKDIR/src/foo.ts\"}}' | bash '$SUT'"
  assert_success
}

# --- Legacy MD plan format ---

@test "falls back to legacy MD plan when no JSONL plan exists" {
  local dir="$TEST_WORKDIR/.yolo-planning/phases/01-setup"
  mkdir -p "$dir"
  # Create a legacy MD plan with files_modified in YAML frontmatter
  cat > "$dir/01-01-PLAN.md" <<'PLAN'
---
title: Setup
files_modified:
  - "src/legacy.ts"
  - "lib/utils.ts"
---
# Plan
PLAN
  run bash -c "echo '{\"tool_input\":{\"file_path\":\"src/legacy.ts\"}}' | bash '$SUT'"
  assert_success

  run bash -c "echo '{\"tool_input\":{\"file_path\":\"src/not-declared.ts\"}}' | bash '$SUT'"
  assert_failure 2
}

# --- JSONL plan is preferred over legacy MD ---

@test "uses JSONL plan when both formats exist without summaries" {
  local dir="$TEST_WORKDIR/.yolo-planning/phases/01-setup"
  mkdir -p "$dir"
  # Create JSONL plan (declares src/foo.ts, src/bar.ts, config/app.json)
  cp "$FIXTURES_DIR/plans/valid-plan.jsonl" "$dir/01-01.plan.jsonl"
  # Also create a legacy MD plan with different files (no JSONL summary for either)
  cat > "$dir/01-02-PLAN.md" <<'PLAN'
---
title: Extra
files_modified:
  - "src/md-only.ts"
---
# Plan
PLAN
  # JSONL plan is found first; src/foo.ts should pass
  run bash -c "echo '{\"tool_input\":{\"file_path\":\"src/foo.ts\"}}' | bash '$SUT'"
  assert_success
}
