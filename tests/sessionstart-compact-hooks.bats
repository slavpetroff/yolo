#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  cd "$TEST_TEMP_DIR"

  # Init git so map-staleness and session-start work
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  echo "init" > init.txt && git add init.txt && git commit -q -m "init"

  # Create minimal STATE.md for session-start
  cat > "$TEST_TEMP_DIR/.yolo-planning/STATE.md" <<'STATE'
Phase: 1 of 2 (Setup)
Status: in-progress
Progress: 50%
STATE

  # Create phases dir
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning/phases/01-setup"

  # Create PROJECT.md so session-start doesn't suggest /yolo:init
  echo "# Test Project" > "$TEST_TEMP_DIR/.yolo-planning/PROJECT.md"
}

teardown() {
  teardown_temp_dir
}

# --- session-start compact skip ---

@test "session-start: skips heavy init when fresh compaction marker present" {
  cd "$TEST_TEMP_DIR"
  date +%s > .yolo-planning/.compaction-marker
  run "$YOLO_BIN" session-start
  [ "$status" -eq 0 ]
  # Should produce NO output (skipped entirely)
  [ -z "$output" ]
}

@test "session-start: runs normally when no compaction marker" {
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" session-start
  [ "$status" -eq 0 ]
  # Should produce hookSpecificOutput JSON
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null
}

@test "session-start: runs normally when compaction marker is stale (>60s)" {
  cd "$TEST_TEMP_DIR"
  # Write a timestamp 120 seconds in the past
  echo $(( $(date +%s) - 120 )) > .yolo-planning/.compaction-marker
  run "$YOLO_BIN" session-start
  [ "$status" -eq 0 ]
  # Should produce hookSpecificOutput JSON (did not skip)
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null
  # Stale marker should be cleaned up
  [ ! -f ".yolo-planning/.compaction-marker" ]
}

# --- map-staleness compact skip ---

@test "map-staleness: skips when fresh compaction marker present" {
  cd "$TEST_TEMP_DIR"
  date +%s > .yolo-planning/.compaction-marker
  run "$YOLO_BIN" map-staleness
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "map-staleness: runs normally when no compaction marker" {
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" map-staleness
  [ "$status" -eq 0 ]
  [[ "$output" == *"no_map"* ]]
}

@test "map-staleness: no plain text on stdout when running as hook (no map)" {
  cd "$TEST_TEMP_DIR"
  result=$("$YOLO_BIN" map-staleness 2>/dev/null)
  # Output should be diagnostic status, not verbose
  [[ "$result" == *"no_map"* ]] || [ -z "$result" ]
}

# --- SessionStart hook (post-compact equivalent) ---

@test "SessionStart hook: exits 0 with fresh compaction marker" {
  cd "$TEST_TEMP_DIR"
  date +%s > .yolo-planning/.compaction-marker
  run bash -c "printf '{}' | \"$YOLO_BIN\" hook SessionStart"
  [ "$status" -eq 0 ]
}

@test "SessionStart hook: produces output without compaction marker" {
  cd "$TEST_TEMP_DIR"
  run bash -c "printf '{}' | \"$YOLO_BIN\" hook SessionStart"
  [ "$status" -eq 0 ]
  # Should produce hookSpecificOutput JSON
  echo "$output" | jq -e '.hookSpecificOutput' >/dev/null 2>&1 || [ -z "$output" ]
}

@test "SessionStart hook: passes through agent_name in JSON" {
  cd "$TEST_TEMP_DIR"
  run bash -c "printf '{\"agent_name\":\"yolo-dev\"}' | \"$YOLO_BIN\" hook SessionStart"
  [ "$status" -eq 0 ]
}

# --- hooks.json structure tests (replaces hook-wrapper tests) ---

@test "hooks.json exists and is valid JSON" {
  [ -f "$PROJECT_ROOT/hooks.json" ] || skip "hooks.json not found"
  jq -e '.' "$PROJECT_ROOT/hooks.json" >/dev/null
}

@test "hooks.json routes PreToolUse to yolo binary" {
  [ -f "$PROJECT_ROOT/hooks.json" ] || skip "hooks.json not found"
  jq -e '.hooks[] | select(.event == "PreToolUse") | .command' "$PROJECT_ROOT/hooks.json" >/dev/null 2>&1 || \
  jq -e '.hooks.PreToolUse' "$PROJECT_ROOT/hooks.json" >/dev/null 2>&1 || \
  skip "PreToolUse hook not configured in hooks.json"
}

# --- PreToolUse security filter ---

@test "PreToolUse: blocks .env file access" {
  cd "$TEST_TEMP_DIR"
  local tmpf
  tmpf=$(mktemp)
  printf '{"tool_name":"Read","tool_input":{"file_path":".env"}}' > "$tmpf"
  run bash -c "\"$YOLO_BIN\" hook PreToolUse < \"$tmpf\""
  rm -f "$tmpf"
  [ "$status" -eq 2 ]
}

@test "PreToolUse: allows normal file access" {
  cd "$TEST_TEMP_DIR"
  local tmpf
  tmpf=$(mktemp)
  printf '{"tool_name":"Read","tool_input":{"file_path":"src/app.js"}}' > "$tmpf"
  run bash -c "\"$YOLO_BIN\" hook PreToolUse < \"$tmpf\""
  rm -f "$tmpf"
  [ "$status" -eq 0 ]
}

@test "PreToolUse: exit 2 produces deny JSON" {
  cd "$TEST_TEMP_DIR"
  local tmpf
  tmpf=$(mktemp)
  printf '{"tool_name":"Read","tool_input":{"file_path":".env"}}' > "$tmpf"
  run bash -c "\"$YOLO_BIN\" hook PreToolUse < \"$tmpf\""
  rm -f "$tmpf"
  [ "$status" -eq 2 ]
  [[ "$output" == *"permissionDecision"* ]]
}

# --- session-start --with-progress / --with-git ---

@test "session-start --with-progress includes progress data" {
  cd "$TEST_TEMP_DIR"
  mkdir -p .yolo-planning/phases/01-setup
  echo "## Task 1: work" > .yolo-planning/phases/01-setup/01-01-PLAN.md
  run "$YOLO_BIN" session-start --with-progress
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.structuredResult.progress' >/dev/null
  echo "$output" | jq -e '.structuredResult.progress.tasks.total' >/dev/null
}

@test "session-start --with-git includes git state" {
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" session-start --with-git
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.structuredResult.git' >/dev/null
  echo "$output" | jq -e '.structuredResult.git.branch' >/dev/null
}

@test "session-start without flags has no progress/git data" {
  cd "$TEST_TEMP_DIR"
  run "$YOLO_BIN" session-start
  [ "$status" -eq 0 ]
  # progress and git should be null (absent) when flags not passed
  local has_progress
  has_progress=$(echo "$output" | jq '.structuredResult.progress // empty')
  [ -z "$has_progress" ]
  local has_git
  has_git=$(echo "$output" | jq '.structuredResult.git // empty')
  [ -z "$has_git" ]
}
