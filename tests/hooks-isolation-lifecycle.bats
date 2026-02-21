#!/usr/bin/env bats

load test_helper

# --- Task 1: PreToolUse security filter with command-only inputs ---
# Commit format validation was removed in the Rust migration.
# PreToolUse now runs security_filter which is fail-closed on inputs
# without extractable file_path/path/pattern fields.

@test "PreToolUse blocks command-only tool_input (fail-closed)" {
  INPUT='{"tool_input":{"command":"git commit -m \"feat(core): add feature\""}}'
  run bash -c "echo '$INPUT' | "'"$YOLO_BIN"'" hook PreToolUse"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "cannot extract file path"
}

@test "PreToolUse allows tool_input with valid file_path" {
  INPUT='{"tool_input":{"file_path":"/project/src/main.rs"}}'
  run bash -c "echo '$INPUT' | "'"$YOLO_BIN"'" hook PreToolUse"
  [ "$status" -eq 0 ]
}

@test "PreToolUse blocks tool_input with sensitive file_path" {
  INPUT='{"tool_input":{"file_path":"/project/credentials.json"}}'
  run bash -c "echo '$INPUT' | "'"$YOLO_BIN"'" hook PreToolUse"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "deny"
}

# --- Task 4: Stack detection expansion ---

@test "detect-stack finds Rust via Cargo.toml" {
  local tmpdir
  tmpdir=$(mktemp -d)
  touch "$tmpdir/Cargo.toml"
  # detect-stack resolves config/stack-mappings.json relative to project_dir arg
  mkdir -p "$tmpdir/config"
  cp "$PROJECT_ROOT/config/stack-mappings.json" "$tmpdir/config/"
  run bash -c "'$YOLO_BIN' detect-stack '$tmpdir'"
  rm -rf "$tmpdir"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.detected_stack | index("rust")' >/dev/null
}

@test "detect-stack finds Go via go.mod" {
  local tmpdir
  tmpdir=$(mktemp -d)
  echo "module example.com/test" > "$tmpdir/go.mod"
  mkdir -p "$tmpdir/config"
  cp "$PROJECT_ROOT/config/stack-mappings.json" "$tmpdir/config/"
  run bash -c "'$YOLO_BIN' detect-stack '$tmpdir'"
  rm -rf "$tmpdir"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.detected_stack | index("go")' >/dev/null
}

@test "detect-stack finds Python via pyproject.toml" {
  local tmpdir
  tmpdir=$(mktemp -d)
  touch "$tmpdir/pyproject.toml"
  mkdir -p "$tmpdir/config"
  cp "$PROJECT_ROOT/config/stack-mappings.json" "$tmpdir/config/"
  run bash -c "'$YOLO_BIN' detect-stack '$tmpdir'"
  rm -rf "$tmpdir"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.detected_stack | index("python")' >/dev/null
}

# --- Task 5: Security filter hardening ---

@test "security-filter allows .yolo-planning/ write when YOLO marker present" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning"
  touch "$TEST_TEMP_DIR/.yolo-planning/.active-agent"
  touch "$TEST_TEMP_DIR/.yolo-planning/.gsd-isolation"
  INPUT='{"tool_input":{"file_path":"'"$TEST_TEMP_DIR"'/.yolo-planning/STATE.md"}}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | "'"$YOLO_BIN"'" hook PreToolUse"
  teardown_temp_dir
  [ "$status" -eq 0 ]
}

@test "security-filter blocks .env file access" {
  INPUT='{"tool_input":{"file_path":".env"}}'
  run bash -c "echo '$INPUT' | "'"$YOLO_BIN"'" hook PreToolUse"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "sensitive"
}

# --- Task 3: Session config cache ---

@test "session config cache file is written at session start" {
  setup_temp_dir
  create_test_config
  CACHE_FILE="/tmp/yolo-config-cache-$(id -u)"
  rm -f "$CACHE_FILE" 2>/dev/null
  run bash -c "cd '$TEST_TEMP_DIR' && "'"$YOLO_BIN"'" session-start"
  [ -f "$CACHE_FILE" ]
  grep -q "YOLO_EFFORT=" "$CACHE_FILE"
  grep -q "YOLO_AUTONOMY=" "$CACHE_FILE"
  teardown_temp_dir
}

# --- Task 2: zsh glob guard ---

@test "file-guard exits 0 when no plan files exist" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning/phases"
  INPUT='{"tool_input":{"file_path":"'"$TEST_TEMP_DIR"'/src/index.ts"}}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | "'"$YOLO_BIN"'" hook PreToolUse"
  teardown_temp_dir
  [ "$status" -eq 0 ]
}

# --- Isolation marker lifecycle (fix/isolation-marker-lifecycle) ---

@test "security-filter allows write with only .yolo-session (no .active-agent)" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning"
  touch "$TEST_TEMP_DIR/.yolo-planning/.gsd-isolation"
  echo "session" > "$TEST_TEMP_DIR/.yolo-planning/.yolo-session"
  # No .active-agent
  INPUT='{"tool_input":{"file_path":"'"$TEST_TEMP_DIR"'/.yolo-planning/milestones/default/STATE.md"}}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | "'"$YOLO_BIN"'" hook PreToolUse"
  teardown_temp_dir
  [ "$status" -eq 0 ]
}

@test "security-filter resolves markers from FILE_PATH project root" {
  setup_temp_dir
  local REPO_A="$TEST_TEMP_DIR/repo-a"
  local REPO_B="$TEST_TEMP_DIR/repo-b"
  mkdir -p "$REPO_A/.yolo-planning" "$REPO_B/.yolo-planning"
  touch "$REPO_A/.yolo-planning/.gsd-isolation"
  # Repo A has no markers — would block if CWD-based
  # Repo B has .gsd-isolation AND .yolo-session — should allow
  touch "$REPO_B/.yolo-planning/.gsd-isolation"
  echo "session" > "$REPO_B/.yolo-planning/.yolo-session"
  INPUT='{"tool_input":{"file_path":"'"$REPO_B"'/.yolo-planning/STATE.md"}}'
  run bash -c "cd '$REPO_A' && echo '$INPUT' | "'"$YOLO_BIN"'" hook PreToolUse"
  teardown_temp_dir
  [ "$status" -eq 0 ]
}

@test "security-filter allows .yolo-planning write even without markers (self-blocking removed)" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning"
  touch "$TEST_TEMP_DIR/.yolo-planning/.gsd-isolation"
  # No .active-agent, no .yolo-session — still allowed since v1.21.13
  # Self-blocking caused false blocks (orchestrator after team deletion, agents before markers set)
  INPUT='{"tool_input":{"file_path":"'"$TEST_TEMP_DIR"'/.yolo-planning/STATE.md"}}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | "'"$YOLO_BIN"'" hook PreToolUse"
  teardown_temp_dir
  [ "$status" -eq 0 ]
}

@test "agent-start handles yolo: prefixed agent_type" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning"
  INPUT='{"agent_type":"yolo:yolo-scout"}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | "'"$YOLO_BIN"'" hook SubagentStart"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/.yolo-planning/.active-agent" ]
  # Rust normalize_agent_role strips "yolo:" prefix, leaving "yolo-scout"
  [ "$(cat "$TEST_TEMP_DIR/.yolo-planning/.active-agent")" = "yolo-scout" ]
  teardown_temp_dir
}

@test "agent-start creates count file for reference counting" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning"
  # Start two agents
  echo '{"agent_type":"yolo-scout"}' | bash -c "cd '$TEST_TEMP_DIR' && "'"$YOLO_BIN"'" hook SubagentStart"
  echo '{"agent_type":"yolo-lead"}' | bash -c "cd '$TEST_TEMP_DIR' && "'"$YOLO_BIN"'" hook SubagentStart"
  [ -f "$TEST_TEMP_DIR/.yolo-planning/.active-agent-count" ]
  [ "$(cat "$TEST_TEMP_DIR/.yolo-planning/.active-agent-count")" = "2" ]
  teardown_temp_dir
}

@test "agent-stop decrements count and preserves marker when agents remain" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning"
  echo "lead" > "$TEST_TEMP_DIR/.yolo-planning/.active-agent"
  echo "2" > "$TEST_TEMP_DIR/.yolo-planning/.active-agent-count"
  run bash -c "cd '$TEST_TEMP_DIR' && echo '{}' | "'"$YOLO_BIN"'" hook SubagentStop"
  [ "$status" -eq 0 ]
  # Marker should still exist (one agent remaining)
  [ -f "$TEST_TEMP_DIR/.yolo-planning/.active-agent" ]
  [ "$(cat "$TEST_TEMP_DIR/.yolo-planning/.active-agent-count")" = "1" ]
  teardown_temp_dir
}

@test "agent-stop removes marker when last agent stops" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning"
  echo "scout" > "$TEST_TEMP_DIR/.yolo-planning/.active-agent"
  echo "1" > "$TEST_TEMP_DIR/.yolo-planning/.active-agent-count"
  run bash -c "cd '$TEST_TEMP_DIR' && echo '{}' | "'"$YOLO_BIN"'" hook SubagentStop"
  [ "$status" -eq 0 ]
  # Both marker and count should be gone
  [ ! -f "$TEST_TEMP_DIR/.yolo-planning/.active-agent" ]
  [ ! -f "$TEST_TEMP_DIR/.yolo-planning/.active-agent-count" ]
  teardown_temp_dir
}

@test "prompt-preflight creates .yolo-session for expanded command content" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning"
  touch "$TEST_TEMP_DIR/.yolo-planning/.gsd-isolation"
  # Simulate expanded slash command with YAML frontmatter containing name: yolo:vibe
  INPUT='{"prompt":"---\nname: yolo:vibe\ndescription: Main entry point\n---\n# YOLO Vibe\nPlan mode..."}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | "'"$YOLO_BIN"'" hook UserPromptSubmit"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/.yolo-planning/.yolo-session" ]
  teardown_temp_dir
}

@test "prompt-preflight does NOT delete .yolo-session on plain text follow-up" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning"
  touch "$TEST_TEMP_DIR/.yolo-planning/.gsd-isolation"
  echo "session" > "$TEST_TEMP_DIR/.yolo-planning/.yolo-session"
  # Plain text follow-up (e.g., user answering a question)
  INPUT='{"prompt":"yes, go ahead"}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | "'"$YOLO_BIN"'" hook UserPromptSubmit"
  [ "$status" -eq 0 ]
  # Marker should still exist
  [ -f "$TEST_TEMP_DIR/.yolo-planning/.yolo-session" ]
  teardown_temp_dir
}

@test "prompt-preflight preserves .yolo-session on non-YOLO slash command" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning"
  touch "$TEST_TEMP_DIR/.yolo-planning/.gsd-isolation"
  echo "session" > "$TEST_TEMP_DIR/.yolo-planning/.yolo-session"
  # Non-YOLO slash command — marker persists since v1.21.13
  # Removal caused false blocks when users sent follow-up messages
  INPUT='{"prompt":"/gsd:status"}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | "'"$YOLO_BIN"'" hook UserPromptSubmit"
  [ "$status" -eq 0 ]
  # Marker should still exist (removal handled by session-stop.sh)
  [ -f "$TEST_TEMP_DIR/.yolo-planning/.yolo-session" ]
  teardown_temp_dir
}

@test "prompt-preflight does NOT create .yolo-session from plain text containing name: yolo:" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning"
  touch "$TEST_TEMP_DIR/.yolo-planning/.gsd-isolation"
  INPUT='{"prompt":"Please explain this YAML fragment: name: yolo:vibe"}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | "'"$YOLO_BIN"'" hook UserPromptSubmit"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TEMP_DIR/.yolo-planning/.yolo-session" ]
  teardown_temp_dir
}

@test "agent-start does nothing when agent fields are missing" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning"
  INPUT='{}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | "'"$YOLO_BIN"'" hook SubagentStart"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TEMP_DIR/.yolo-planning/.active-agent" ]
  [ ! -f "$TEST_TEMP_DIR/.yolo-planning/.active-agent-count" ]
  teardown_temp_dir
}

@test "agent-start resets non-numeric count and increments safely" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning"
  echo "abc" > "$TEST_TEMP_DIR/.yolo-planning/.active-agent-count"
  INPUT='{"agent_type":"yolo-scout"}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | "'"$YOLO_BIN"'" hook SubagentStart"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_TEMP_DIR/.yolo-planning/.active-agent")" = "scout" ]
  [ "$(cat "$TEST_TEMP_DIR/.yolo-planning/.active-agent-count")" = "1" ]
  teardown_temp_dir
}

@test "agent-start accepts team-lead alias when YOLO session marker exists" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning"
  echo "session" > "$TEST_TEMP_DIR/.yolo-planning/.yolo-session"
  INPUT='{"agent_name":"team-lead"}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | "'"$YOLO_BIN"'" hook SubagentStart"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_TEMP_DIR/.yolo-planning/.active-agent")" = "lead" ]
  [ "$(cat "$TEST_TEMP_DIR/.yolo-planning/.active-agent-count")" = "1" ]
  teardown_temp_dir
}

@test "agent-start ignores team-lead alias without YOLO context markers" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning"
  INPUT='{"agent_name":"team-lead"}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | "'"$YOLO_BIN"'" hook SubagentStart"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TEMP_DIR/.yolo-planning/.active-agent" ]
  [ ! -f "$TEST_TEMP_DIR/.yolo-planning/.active-agent-count" ]
  teardown_temp_dir
}

@test "agent-stop cleans up when count is non-numeric" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning"
  echo "scout" > "$TEST_TEMP_DIR/.yolo-planning/.active-agent"
  echo "abc" > "$TEST_TEMP_DIR/.yolo-planning/.active-agent-count"
  run bash -c "cd '$TEST_TEMP_DIR' && echo '{}' | "'"$YOLO_BIN"'" hook SubagentStop"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TEMP_DIR/.yolo-planning/.active-agent" ]
  [ ! -f "$TEST_TEMP_DIR/.yolo-planning/.active-agent-count" ]
  teardown_temp_dir
}

@test "agent-stop two sequential stops from count=2 fully clean up markers" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning"
  echo "scout" > "$TEST_TEMP_DIR/.yolo-planning/.active-agent"
  echo "2" > "$TEST_TEMP_DIR/.yolo-planning/.active-agent-count"
  # First stop: 2 -> 1, marker preserved
  run bash -c "cd '$TEST_TEMP_DIR' && echo '{}' | "'"$YOLO_BIN"'" hook SubagentStop"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/.yolo-planning/.active-agent" ]
  [ "$(cat "$TEST_TEMP_DIR/.yolo-planning/.active-agent-count")" = "1" ]
  # Second stop: 1 -> 0, full cleanup
  run bash -c "cd '$TEST_TEMP_DIR' && echo '{}' | "'"$YOLO_BIN"'" hook SubagentStop"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TEMP_DIR/.yolo-planning/.active-agent" ]
  [ ! -f "$TEST_TEMP_DIR/.yolo-planning/.active-agent-count" ]
  teardown_temp_dir
}

@test "security-filter resolves .planning marker checks from FILE_PATH root" {
  setup_temp_dir
  local REPO_A="$TEST_TEMP_DIR/repo-a"
  local REPO_B="$TEST_TEMP_DIR/repo-b"
  mkdir -p "$REPO_A/.yolo-planning" "$REPO_B/.planning" "$REPO_B/.yolo-planning"
  touch "$REPO_A/.yolo-planning/.active-agent"
  INPUT='{"tool_input":{"file_path":"'"$REPO_B"'/.planning/STATE.md"}}'
  run bash -c "cd '$REPO_A' && echo '$INPUT' | "'"$YOLO_BIN"'" hook PreToolUse"
  [ "$status" -eq 0 ]
  teardown_temp_dir
}

@test "security-filter blocks .planning write when target repo has active marker" {
  setup_temp_dir
  local REPO_A="$TEST_TEMP_DIR/repo-a"
  local REPO_B="$TEST_TEMP_DIR/repo-b"
  mkdir -p "$REPO_A/.yolo-planning" "$REPO_B/.planning" "$REPO_B/.yolo-planning"
  touch "$REPO_B/.yolo-planning/.active-agent"
  INPUT='{"tool_input":{"file_path":"'"$REPO_B"'/.planning/STATE.md"}}'
  run bash -c "cd '$REPO_A' && echo '$INPUT' | "'"$YOLO_BIN"'" hook PreToolUse"
  [ "$status" -eq 2 ]
  teardown_temp_dir
}

@test "security-filter allows .yolo-planning writes regardless of marker staleness" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning"
  touch "$TEST_TEMP_DIR/.yolo-planning/.gsd-isolation"
  echo "session" > "$TEST_TEMP_DIR/.yolo-planning/.yolo-session"
  touch -t 202401010101 "$TEST_TEMP_DIR/.yolo-planning/.yolo-session"
  # Self-blocking removed in v1.21.13 — stale markers no longer matter
  INPUT='{"tool_input":{"file_path":"'"$TEST_TEMP_DIR"'/.yolo-planning/STATE.md"}}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | "'"$YOLO_BIN"'" hook PreToolUse"
  [ "$status" -eq 0 ]
  teardown_temp_dir
}

@test "session-stop preserves .yolo-session and removes transient agent markers" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning"
  echo "session" > "$TEST_TEMP_DIR/.yolo-planning/.yolo-session"
  echo "scout" > "$TEST_TEMP_DIR/.yolo-planning/.active-agent"
  echo "2" > "$TEST_TEMP_DIR/.yolo-planning/.active-agent-count"
  run bash -c "cd '$TEST_TEMP_DIR' && echo '{}' | "'"$YOLO_BIN"'" hook Stop"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/.yolo-planning/.yolo-session" ]
  [ ! -f "$TEST_TEMP_DIR/.yolo-planning/.active-agent" ]
  [ ! -f "$TEST_TEMP_DIR/.yolo-planning/.active-agent-count" ]
  teardown_temp_dir
}

@test "yolo session marker survives Stop and non-YOLO slash commands" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning/milestones/default/phases/05-migration-preview-completeness"
  touch "$TEST_TEMP_DIR/.yolo-planning/.gsd-isolation"

  # Start YOLO flow
  run bash -c "cd '$TEST_TEMP_DIR' && echo '{\"prompt\":\"/yolo:verify 5\"}' | "'"$YOLO_BIN"'" hook UserPromptSubmit"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/.yolo-planning/.yolo-session" ]

  # Session Stop between turns should not clear .yolo-session
  run bash -c "cd '$TEST_TEMP_DIR' && echo '{}' | "'"$YOLO_BIN"'" hook Stop"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/.yolo-planning/.yolo-session" ]

  # Plain-text follow-up should keep marker and allow .yolo-planning write
  run bash -c "cd '$TEST_TEMP_DIR' && echo '{\"prompt\":\"it says 16 positions to move\"}' | "'"$YOLO_BIN"'" hook UserPromptSubmit"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/.yolo-planning/.yolo-session" ]

  INPUT='{"tool_input":{"file_path":"'"$TEST_TEMP_DIR"'/.yolo-planning/milestones/default/phases/05-migration-preview-completeness/05-UAT.md"}}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | "'"$YOLO_BIN"'" hook PreToolUse"
  [ "$status" -eq 0 ]

  # Non-YOLO slash command should NOT clear marker (removal handled by session-stop.sh)
  run bash -c "cd '$TEST_TEMP_DIR' && echo '{\"prompt\":\"/gsd:status\"}' | "'"$YOLO_BIN"'" hook UserPromptSubmit"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/.yolo-planning/.yolo-session" ]

  # .yolo-planning writes still allowed (self-blocking removed in v1.21.13)
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | "'"$YOLO_BIN"'" hook PreToolUse"
  [ "$status" -eq 0 ]
  teardown_temp_dir
}

@test "task-verify allows role-only task subjects like Lead" {
  setup_temp_dir
  cd "$TEST_TEMP_DIR"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  echo "hello" > file.txt
  git add file.txt
  git commit -q -m "chore(test): seed commit"
  run bash -c "echo '{\"task_subject\":\"Lead\"}' | "'"$YOLO_BIN"'" hook PostToolUse"
  [ "$status" -eq 0 ]
  teardown_temp_dir
}

@test "security-filter falls back to CWD for relative FILE_PATH" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning"
  touch "$TEST_TEMP_DIR/.yolo-planning/.gsd-isolation"
  echo "session" > "$TEST_TEMP_DIR/.yolo-planning/.yolo-session"
  # Relative path — derive_project_root falls back to ".", CWD-relative marker check
  INPUT='{"tool_input":{"file_path":".yolo-planning/STATE.md"}}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | "'"$YOLO_BIN"'" hook PreToolUse"
  teardown_temp_dir
  [ "$status" -eq 0 ]
}

@test "security-filter allows relative .yolo-planning FILE_PATH without markers" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning"
  touch "$TEST_TEMP_DIR/.yolo-planning/.gsd-isolation"
  # No markers — still allowed since self-blocking removed in v1.21.13
  INPUT='{"tool_input":{"file_path":".yolo-planning/STATE.md"}}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | "'"$YOLO_BIN"'" hook PreToolUse"
  teardown_temp_dir
  [ "$status" -eq 0 ]
}

@test "prompt-preflight does NOT delete .yolo-session when prompt is a file path" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning"
  touch "$TEST_TEMP_DIR/.yolo-planning/.gsd-isolation"
  echo "session" > "$TEST_TEMP_DIR/.yolo-planning/.yolo-session"
  INPUT='{"prompt":"/home/user/project/file.txt"}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | "'"$YOLO_BIN"'" hook UserPromptSubmit"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/.yolo-planning/.yolo-session" ]
  teardown_temp_dir
}

@test "session-stop cleans up stale lock directory" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning/.active-agent-count.lock"
  run bash -c "cd '$TEST_TEMP_DIR' && echo '{}' | "'"$YOLO_BIN"'" hook Stop"
  [ "$status" -eq 0 ]
  [ ! -d "$TEST_TEMP_DIR/.yolo-planning/.active-agent-count.lock" ]
  teardown_temp_dir
}

@test "task-verify allows [analysis-only] tag in task_subject" {
  setup_temp_dir
  cd "$TEST_TEMP_DIR"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  mkdir -p .yolo-planning
  # Seed commit is old (no recent commits match)
  echo "hello" > file.txt
  git add file.txt
  git commit -q -m "chore(test): seed commit"
  # Task subject with [analysis-only] tag should be allowed even without matching commit
  run bash -c "echo '{\"task_subject\":\"Hypothesis 1: race condition in sync [analysis-only]\"}' | "'"$YOLO_BIN"'" hook PostToolUse"
  [ "$status" -eq 0 ]
  teardown_temp_dir
}

@test "task-verify allows [analysis-only] tag in task_description fallback" {
  setup_temp_dir
  cd "$TEST_TEMP_DIR"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  mkdir -p .yolo-planning
  echo "hello" > file.txt
  git add file.txt
  git commit -q -m "chore(test): seed commit"
  # Tag in description (subject empty) should also be allowed
  run bash -c "echo '{\"task_description\":\"Investigate memory leak [analysis-only]\"}' | "'"$YOLO_BIN"'" hook PostToolUse"
  [ "$status" -eq 0 ]
  teardown_temp_dir
}

@test "PostToolUse is advisory-only (always exit 0)" {
  # Rust PostToolUse validates SUMMARY.md structure only — no commit matching
  run bash -c "echo '{\"task_subject\":\"Implement caching layer for database queries\"}' | "'"$YOLO_BIN"'" hook PostToolUse"
  [ "$status" -eq 0 ]
}

@test "task-verify allows [analysis-only] even with no recent commits" {
  setup_temp_dir
  cd "$TEST_TEMP_DIR"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  mkdir -p .yolo-planning
  # Seed commit with a backdated timestamp (well outside 2-hour window)
  echo "hello" > file.txt
  git add file.txt
  GIT_AUTHOR_DATE="2020-01-01T00:00:00" GIT_COMMITTER_DATE="2020-01-01T00:00:00" \
    git commit -q -m "chore(test): ancient seed commit"
  # Without the fix, this would exit 2 ("No recent commits found") before
  # reaching the [analysis-only] check
  run bash -c "echo '{\"task_subject\":\"Hypothesis 2: deadlock in worker pool [analysis-only]\"}' | "'"$YOLO_BIN"'" hook PostToolUse"
  [ "$status" -eq 0 ]
  teardown_temp_dir
}

@test "hooks matcher includes prefixed YOLO agent names" {
  run bash -c "grep -q 'yolo:yolo-debugger' '$PROJECT_ROOT/hooks/hooks.json'"
  [ "$status" -eq 0 ]
}

@test "hooks matcher includes team role aliases" {
  run bash -c "grep -q 'team-lead' '$PROJECT_ROOT/hooks/hooks.json'"
  [ "$status" -eq 0 ]
}
