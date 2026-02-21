#!/usr/bin/env bats

# Tests for PostToolUse hook behavior with task_subject inputs.
# The Rust binary's PostToolUse handler exits 0 for all inputs
# (task verification is advisory, not blocking).

load test_helper

setup() {
  setup_temp_dir
  create_test_config

  # Create a minimal git repo inside TEST_TEMP_DIR
  cd "$TEST_TEMP_DIR"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  # Seed commit so git log works
  echo "init" > init.txt
  git add init.txt
  git commit -q -m "chore: initial commit"
}

teardown() {
  teardown_temp_dir
}

# Helper: add a recent commit with given message
add_commit() {
  local msg="$1"
  echo "$RANDOM" >> "$TEST_TEMP_DIR/dummy.txt"
  git add dummy.txt
  git commit -q -m "$msg"
}

# Helper: run PostToolUse with a task_subject via temp file
run_posttooluse() {
  local json="$1"
  local tmpf
  tmpf=$(mktemp)
  printf '%s' "$json" > "$tmpf"
  run bash -c "cd \"$TEST_TEMP_DIR\" && \"$YOLO_BIN\" hook PostToolUse < \"$tmpf\""
  rm -f "$tmpf"
}

# =============================================================================
# PostToolUse exits 0 for all task-verify scenarios
# =============================================================================

@test "PostToolUse passes with matching commit and task subject" {
  cd "$TEST_TEMP_DIR"
  add_commit "feat(07-01): create StockLotDetailView"

  run_posttooluse '{"task_subject":"Execute 07-01: Create StockLotDetailView"}'
  [ "$status" -eq 0 ]
}

@test "PostToolUse passes with non-matching task subject" {
  cd "$TEST_TEMP_DIR"
  add_commit "docs: update README"

  run_posttooluse '{"task_subject":"Implement quantum flux capacitor"}'
  [ "$status" -eq 0 ]
}

@test "PostToolUse passes with analysis-only tag" {
  cd "$TEST_TEMP_DIR"
  run_posttooluse '{"task_subject":"[analysis-only] Investigate race condition"}'
  [ "$status" -eq 0 ]
}

@test "PostToolUse passes with role-only subject" {
  cd "$TEST_TEMP_DIR"
  run_posttooluse '{"task_subject":"dev-01"}'
  [ "$status" -eq 0 ]
}

@test "PostToolUse passes with yolo-prefixed role subject" {
  cd "$TEST_TEMP_DIR"
  run_posttooluse '{"task_subject":"yolo-dev"}'
  [ "$status" -eq 0 ]
}

@test "PostToolUse passes with empty task subject (fail-open)" {
  cd "$TEST_TEMP_DIR"
  run_posttooluse '{}'
  [ "$status" -eq 0 ]
}

@test "PostToolUse passes without .yolo-planning dir (non-YOLO context)" {
  cd "$TEST_TEMP_DIR"
  rm -rf .yolo-planning
  run_posttooluse '{"task_subject":"anything"}'
  [ "$status" -eq 0 ]
}

# =============================================================================
# PostToolUse is non-blocking for all commit patterns
# =============================================================================

@test "PostToolUse passes with team-mode Execute prefix" {
  cd "$TEST_TEMP_DIR"
  add_commit "refactor(03-01): update authentication middleware"
  run_posttooluse '{"task_subject":"Execute 03-01: Update authentication middleware"}'
  [ "$status" -eq 0 ]
}

@test "PostToolUse passes with short task subject" {
  cd "$TEST_TEMP_DIR"
  add_commit "fix(07-01): resolve the bug in auth"
  run_posttooluse '{"task_subject":"Execute 07-01: Fix bug"}'
  [ "$status" -eq 0 ]
}

@test "PostToolUse passes with matching navigation commit" {
  cd "$TEST_TEMP_DIR"
  add_commit "feat(07-02): wire NavigationLink to StockLotDetailView"
  run_posttooluse '{"task_subject":"Execute 07-02: Wire navigation to StockLotDetailView"}'
  [ "$status" -eq 0 ]
}

# =============================================================================
# PostToolUse produces no blocking output
# =============================================================================

@test "PostToolUse produces no deny output for any task subject" {
  cd "$TEST_TEMP_DIR"
  add_commit "docs: update README"
  run_posttooluse '{"task_subject":"Implement something entirely different"}'
  [ "$status" -eq 0 ]
  [[ "$output" != *"permissionDecision"* ]]
}

@test "PostToolUse produces no deny output for matching commit" {
  cd "$TEST_TEMP_DIR"
  add_commit "feat(auth): implement login flow with OAuth2"
  run_posttooluse '{"task_subject":"Implement login flow"}'
  [ "$status" -eq 0 ]
  [[ "$output" != *"permissionDecision"* ]]
}

@test "PostToolUse non-blocking even after multiple calls with same subject" {
  cd "$TEST_TEMP_DIR"
  add_commit "docs: update README"

  run_posttooluse '{"task_subject":"Implement quantum flux capacitor"}'
  [ "$status" -eq 0 ]

  run_posttooluse '{"task_subject":"Implement quantum flux capacitor"}'
  [ "$status" -eq 0 ]
}

@test "PostToolUse non-blocking with different subjects" {
  cd "$TEST_TEMP_DIR"
  add_commit "docs: update README"

  run_posttooluse '{"task_subject":"Implement quantum flux capacitor"}'
  [ "$status" -eq 0 ]

  run_posttooluse '{"task_subject":"Build time machine"}'
  [ "$status" -eq 0 ]
}
