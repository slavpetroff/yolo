#!/usr/bin/env bats
# generate-department-toons.bats — Unit tests for TOON generation script
# Tests scripts/generate-department-toons.sh rendering of department templates
# from project type detection results.
# RED PHASE: All tests expected to FAIL until implementation in plan 01-02.

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  load '../test_helper/mock_stdin'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/generate-department-toons.sh"

  # Override CLAUDE_CONFIG_DIR to avoid picking up real installed skills
  export CLAUDE_CONFIG_DIR="$TEST_WORKDIR/mock-claude"
  mkdir -p "$CLAUDE_CONFIG_DIR/skills"

  # Create .yolo-planning dir for output
  mkdir -p "$TEST_WORKDIR/.yolo-planning"
}

# Helper: run generate-department-toons against test project dir
run_generate() {
  run bash -c "cd '$TEST_WORKDIR' && CLAUDE_CONFIG_DIR='$CLAUDE_CONFIG_DIR' bash '$SUT' '$TEST_WORKDIR'"
}

# --- Fixture Helpers ---

mk_webapp_fixture() {
  cat > "$TEST_WORKDIR/package.json" <<'EOF'
{"dependencies":{"react":"^18","react-dom":"^18"}}
EOF
}

mk_cli_fixture() {
  mkdir -p "$TEST_WORKDIR/bin" "$TEST_WORKDIR/scripts"
  echo '#!/bin/bash' > "$TEST_WORKDIR/scripts/run.sh"
}

mk_library_fixture() {
  mkdir -p "$TEST_WORKDIR/src"
  touch "$TEST_WORKDIR/Cargo.toml" "$TEST_WORKDIR/src/lib.rs"
}

# --- Output Directory and File Creation ---

@test "creates output directory" {
  mk_webapp_fixture
  run_generate
  assert_success
  assert_file_exists "$TEST_WORKDIR/.yolo-planning/departments/backend.toon"
}

@test "generates all three department TOONs" {
  mk_webapp_fixture
  run_generate
  assert_success
  assert_file_exists "$TEST_WORKDIR/.yolo-planning/departments/backend.toon"
  assert_file_exists "$TEST_WORKDIR/.yolo-planning/departments/frontend.toon"
  assert_file_exists "$TEST_WORKDIR/.yolo-planning/departments/uiux.toon"
}

@test "creates .stack-hash file" {
  mk_webapp_fixture
  run_generate
  assert_success
  assert_file_exists "$TEST_WORKDIR/.yolo-planning/departments/.stack-hash"
}

# --- Web-app Type Conventions ---

@test "web-app backend.toon contains TypeScript" {
  mk_webapp_fixture
  run_generate
  assert_success
  assert_file_contains "$TEST_WORKDIR/.yolo-planning/departments/backend.toon" "TypeScript"
}

@test "web-app uiux.toon contains design tokens" {
  mk_webapp_fixture
  run_generate
  assert_success
  assert_file_contains "$TEST_WORKDIR/.yolo-planning/departments/uiux.toon" "design tokens"
}

# --- CLI-tool Type Conventions ---

@test "cli-tool backend.toon contains Bash" {
  mk_cli_fixture
  run_generate
  assert_success
  assert_file_contains "$TEST_WORKDIR/.yolo-planning/departments/backend.toon" "Bash"
}

@test "cli-tool uiux.toon contains help text quality" {
  mk_cli_fixture
  run_generate
  assert_success
  assert_file_contains "$TEST_WORKDIR/.yolo-planning/departments/uiux.toon" "help text quality"
}

# --- Library Type Conventions ---

@test "library backend.toon contains per detection language" {
  mk_library_fixture
  run_generate
  assert_success
  assert_file_contains "$TEST_WORKDIR/.yolo-planning/departments/backend.toon" "per detection"
}

@test "library uiux.toon contains API surface design" {
  mk_library_fixture
  run_generate
  assert_success
  assert_file_contains "$TEST_WORKDIR/.yolo-planning/departments/uiux.toon" "API surface design"
}

# --- No Raw Placeholders ---

@test "no raw placeholders in backend.toon" {
  mk_webapp_fixture
  run_generate
  assert_success
  assert_file_not_contains "$TEST_WORKDIR/.yolo-planning/departments/backend.toon" "{{"
}

@test "no raw placeholders in frontend.toon" {
  mk_webapp_fixture
  run_generate
  assert_success
  assert_file_not_contains "$TEST_WORKDIR/.yolo-planning/departments/frontend.toon" "{{"
}

@test "no raw placeholders in uiux.toon" {
  mk_webapp_fixture
  run_generate
  assert_success
  assert_file_not_contains "$TEST_WORKDIR/.yolo-planning/departments/uiux.toon" "{{"
}

# --- Idempotency ---

@test "idempotent: second run produces identical output" {
  mk_webapp_fixture
  # First run (direct call, not 'run', so files are written)
  bash -c "cd '$TEST_WORKDIR' && CLAUDE_CONFIG_DIR='$CLAUDE_CONFIG_DIR' bash '$SUT' '$TEST_WORKDIR'" >/dev/null 2>&1
  # Save copies
  cp "$TEST_WORKDIR/.yolo-planning/departments/backend.toon" "$TEST_WORKDIR/first-backend.toon"
  cp "$TEST_WORKDIR/.yolo-planning/departments/frontend.toon" "$TEST_WORKDIR/first-frontend.toon"
  cp "$TEST_WORKDIR/.yolo-planning/departments/uiux.toon" "$TEST_WORKDIR/first-uiux.toon"
  # Force second run
  bash -c "cd '$TEST_WORKDIR' && CLAUDE_CONFIG_DIR='$CLAUDE_CONFIG_DIR' bash '$SUT' '$TEST_WORKDIR' --force" >/dev/null 2>&1
  # Compare
  run diff "$TEST_WORKDIR/first-backend.toon" "$TEST_WORKDIR/.yolo-planning/departments/backend.toon"
  assert_success
  run diff "$TEST_WORKDIR/first-frontend.toon" "$TEST_WORKDIR/.yolo-planning/departments/frontend.toon"
  assert_success
  run diff "$TEST_WORKDIR/first-uiux.toon" "$TEST_WORKDIR/.yolo-planning/departments/uiux.toon"
  assert_success
}

# --- Generic Fallback ---

@test "generic type generated for empty project" {
  # Empty TEST_WORKDIR (no fixtures)
  run_generate
  assert_success
  assert_file_exists "$TEST_WORKDIR/.yolo-planning/departments/backend.toon"
}
