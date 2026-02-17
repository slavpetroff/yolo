#!/usr/bin/env bats
# session-start.bats — Unit tests for scripts/session-start.sh
# SessionStart hook: project state detection, context injection

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  load '../test_helper/mock_stdin'
  mk_test_workdir

  SUT="$SCRIPTS_DIR/session-start.sh"

  # Isolate from real HOME caches
  export CLAUDE_CONFIG_DIR="$TEST_WORKDIR/mock-claude"
  mkdir -p "$CLAUDE_CONFIG_DIR"

  # Create a mock plugin.json so the script can read local version
  mkdir -p "$TEST_WORKDIR/mock-plugin/.claude-plugin"
  echo '{"version":"1.0.0"}' > "$TEST_WORKDIR/mock-plugin/.claude-plugin/plugin.json"
}

# Helper: run session-start.sh from TEST_WORKDIR with curl stubbed out
run_session_start() {
  # Stub curl to avoid network calls; stub git to avoid git errors
  run bash -c "cd '$TEST_WORKDIR' && CLAUDE_CONFIG_DIR='$CLAUDE_CONFIG_DIR' PATH='$TEST_WORKDIR/bin:$PATH' bash '$SUT'"
}

setup_stub_bin() {
  mkdir -p "$TEST_WORKDIR/bin"
  # Stub curl to return nothing (prevents network calls)
  printf '#!/bin/bash\nexit 1\n' > "$TEST_WORKDIR/bin/curl"
  chmod +x "$TEST_WORKDIR/bin/curl"
  # Stub git for non-repo contexts
  printf '#!/bin/bash\nexit 1\n' > "$TEST_WORKDIR/bin/git"
  chmod +x "$TEST_WORKDIR/bin/git"
}

# --- 1. No .yolo-planning directory ---

@test "outputs 'No .yolo-planning/' when directory is missing" {
  setup_stub_bin
  # Ensure welcomed marker exists so we skip first-run
  touch "$CLAUDE_CONFIG_DIR/.yolo-welcomed"
  run_session_start
  assert_success
  assert_output --partial "No .yolo-planning/ directory found"
}

# --- 2. Always exits 0 ---

@test "always exits 0 even without planning dir" {
  setup_stub_bin
  touch "$CLAUDE_CONFIG_DIR/.yolo-welcomed"
  run_session_start
  assert_success
}

# --- 3. Outputs valid JSON ---

@test "outputs valid JSON with hookSpecificOutput" {
  setup_stub_bin
  touch "$CLAUDE_CONFIG_DIR/.yolo-welcomed"
  run_session_start
  assert_success
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null
}

# --- 4. Detects YOLO project ---

@test "detects YOLO project when .yolo-planning exists" {
  setup_stub_bin
  mk_planning_dir
  touch "$CLAUDE_CONFIG_DIR/.yolo-welcomed"
  # Create PROJECT.md and a phase so the script has something to parse
  echo "# Project" > "$TEST_WORKDIR/.yolo-planning/PROJECT.md"
  mk_state_json 1 3 "executing"
  mkdir -p "$TEST_WORKDIR/.yolo-planning/phases/01-setup"
  run_session_start
  assert_success
  assert_output --partial "YOLO project detected"
}

# --- 5. Parses config.json values ---

@test "includes config values in context output" {
  setup_stub_bin
  mk_planning_dir
  touch "$CLAUDE_CONFIG_DIR/.yolo-welcomed"
  echo "# Project" > "$TEST_WORKDIR/.yolo-planning/PROJECT.md"
  mk_state_json 1 2 "executing"
  mkdir -p "$TEST_WORKDIR/.yolo-planning/phases/01-setup"
  run_session_start
  assert_success
  assert_output --partial "effort=balanced"
}

# --- 6. Parses state.json ---

@test "includes phase info from state.json" {
  setup_stub_bin
  mk_planning_dir
  touch "$CLAUDE_CONFIG_DIR/.yolo-welcomed"
  echo "# Project" > "$TEST_WORKDIR/.yolo-planning/PROJECT.md"
  mk_state_json 2 4 "planning"
  mkdir -p "$TEST_WORKDIR/.yolo-planning/phases/02-build"
  run_session_start
  assert_success
  assert_output --partial "Phase: 2/4"
  assert_output --partial "planning"
}

# --- 7. Cleans compaction marker ---

@test "removes .compaction-marker at session start" {
  setup_stub_bin
  mk_planning_dir
  touch "$CLAUDE_CONFIG_DIR/.yolo-welcomed"
  touch "$TEST_WORKDIR/.yolo-planning/.compaction-marker"
  run_session_start
  assert_success
  assert_file_not_exists "$TEST_WORKDIR/.yolo-planning/.compaction-marker"
}

# --- 8. Auto-migrates config when model_profile missing ---

@test "auto-migrates config.json to add model_profile" {
  setup_stub_bin
  mk_planning_dir
  touch "$CLAUDE_CONFIG_DIR/.yolo-welcomed"
  # Overwrite config with one that lacks model_profile
  echo '{"effort":"balanced","autonomy":"standard"}' > "$TEST_WORKDIR/.yolo-planning/config.json"
  run_session_start
  assert_success
  run jq -r '.model_profile' "$TEST_WORKDIR/.yolo-planning/config.json"
  assert_output "quality"
}

# --- 8b. Auto-migrates config when team_mode missing ---

@test "auto-migrates config.json to add team_mode" {
  setup_stub_bin
  mk_planning_dir
  touch "$CLAUDE_CONFIG_DIR/.yolo-welcomed"
  # Overwrite config with one that has model_profile but lacks team_mode
  echo '{"effort":"balanced","autonomy":"standard","model_profile":"balanced"}' > "$TEST_WORKDIR/.yolo-planning/config.json"
  run_session_start
  assert_success
  run jq -r '.team_mode' "$TEST_WORKDIR/.yolo-planning/config.json"
  assert_output "auto"
}

# --- 9. Next action suggests /yolo:init when PROJECT.md missing ---

@test "suggests /yolo:init when PROJECT.md is missing" {
  setup_stub_bin
  mk_planning_dir
  touch "$CLAUDE_CONFIG_DIR/.yolo-welcomed"
  run_session_start
  assert_success
  assert_output --partial "/yolo:init"
}

# --- 10. First-run welcome message ---

@test "outputs welcome message on first run" {
  setup_stub_bin
  # Do NOT create .yolo-welcomed marker
  run_session_start
  assert_success
  assert_output --partial "FIRST RUN"
  assert_output --partial "Welcome to YOLO"
  # Verify marker was created
  assert_file_exists "$CLAUDE_CONFIG_DIR/.yolo-welcomed"
}
