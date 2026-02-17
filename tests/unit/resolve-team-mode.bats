#!/usr/bin/env bats
# resolve-team-mode.bats — Unit tests for scripts/resolve-team-mode.sh
# Team mode resolution: config reading, fallback logic, env var validation.
# Usage: resolve-team-mode.sh [config_path]
# Returns key=value pairs: team_mode=task|teammate, fallback_notice=true|false

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  load '../test_helper/mock_stdin'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/resolve-team-mode.sh"
}

# Helper: extract a key from output (same pattern as phase-detect.bats)
get_val() {
  local key="$1"
  echo "$output" | grep "^${key}=" | head -1 | sed "s/^${key}=//"
}

# --- 1. No config file ---

@test "no config file outputs team_mode=task" {
  run bash "$SUT" "$TEST_WORKDIR/nonexistent.json"
  assert_success
  assert_line 'team_mode=task'
  assert_line 'fallback_notice=false'
}

# --- 2. Config with team_mode=task ---

@test "config with team_mode=task outputs task" {
  echo '{"team_mode":"task","agent_teams":true}' > "$TEST_WORKDIR/cfg.json"
  run bash "$SUT" "$TEST_WORKDIR/cfg.json"
  assert_success
  assert_line 'team_mode=task'
  assert_line 'fallback_notice=false'
}

# --- 3. Config with team_mode=teammate and env var set ---

@test "teammate mode with env var set outputs teammate" {
  export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
  echo '{"team_mode":"teammate","agent_teams":true}' > "$TEST_WORKDIR/cfg.json"
  run bash "$SUT" "$TEST_WORKDIR/cfg.json"
  assert_success
  assert_line 'team_mode=teammate'
  assert_line 'fallback_notice=false'
}

# --- 4. Config missing team_mode field defaults to auto ---

@test "config missing team_mode field defaults to auto (resolves to teammate when env var set)" {
  export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
  echo '{"agent_teams":true}' > "$TEST_WORKDIR/cfg.json"
  run bash "$SUT" "$TEST_WORKDIR/cfg.json"
  assert_success
  assert_line 'team_mode=teammate'
  assert_line 'auto_detected=true'
}

@test "config missing team_mode field defaults to auto (resolves to task when env var unset)" {
  unset CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS
  echo '{"agent_teams":true}' > "$TEST_WORKDIR/cfg.json"
  run bash "$SUT" "$TEST_WORKDIR/cfg.json"
  assert_success
  assert_line 'team_mode=task'
  assert_line 'fallback_notice=true'
}

# --- 5. Teammate mode with agent_teams=false downgrades ---

@test "teammate mode with agent_teams=false downgrades to task" {
  export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
  echo '{"team_mode":"teammate","agent_teams":false}' > "$TEST_WORKDIR/cfg.json"
  run bash "$SUT" "$TEST_WORKDIR/cfg.json"
  assert_success
  assert_line 'team_mode=task'
  assert_line 'fallback_notice=true'
}

# --- 6. Teammate mode without env var downgrades ---

@test "teammate mode without env var downgrades to task" {
  unset CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS 2>/dev/null || true
  echo '{"team_mode":"teammate","agent_teams":true}' > "$TEST_WORKDIR/cfg.json"
  run bash "$SUT" "$TEST_WORKDIR/cfg.json"
  assert_success
  assert_line 'team_mode=task'
  assert_line 'fallback_notice=true'
}

# --- 7. Teammate with agent_teams=false AND no env var downgrades ---

@test "teammate with agent_teams=false and no env var downgrades to task" {
  unset CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS 2>/dev/null || true
  echo '{"team_mode":"teammate","agent_teams":false}' > "$TEST_WORKDIR/cfg.json"
  run bash "$SUT" "$TEST_WORKDIR/cfg.json"
  assert_success
  assert_line 'team_mode=task'
  assert_line 'fallback_notice=true'
}

# --- 8. Task mode unaffected by missing env var ---

@test "task mode is never downgraded regardless of env var" {
  unset CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS 2>/dev/null || true
  echo '{"team_mode":"task","agent_teams":true}' > "$TEST_WORKDIR/cfg.json"
  run bash "$SUT" "$TEST_WORKDIR/cfg.json"
  assert_success
  assert_line 'team_mode=task'
  assert_line 'fallback_notice=false'
}

# --- 9. Output format: all lines match key=value ---

@test "all output lines match key=value format" {
  run bash "$SUT" "$TEST_WORKDIR/nonexistent.json"
  assert_success
  while IFS= read -r line; do
    [[ "$line" =~ ^[a-z_]+=.+ ]] || fail "Line does not match key=value: $line"
  done <<< "$output"
}

# --- 10. Default config path when no argument ---

@test "default config path resolves .yolo-planning/config.json" {
  mkdir -p "$TEST_WORKDIR/.yolo-planning"
  echo '{"team_mode":"task","agent_teams":true}' > "$TEST_WORKDIR/.yolo-planning/config.json"
  run bash -c "cd '$TEST_WORKDIR' && bash '$SUT'"
  assert_success
  assert_line 'team_mode=task'
  assert_line 'fallback_notice=false'
}

# --- 11. Auto mode with env var set and agent_teams=true -> teammate ---

@test "auto mode with env var and agent_teams=true resolves to teammate" {
  export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
  echo '{"team_mode":"auto","agent_teams":true}' > "$TEST_WORKDIR/cfg.json"
  run bash "$SUT" "$TEST_WORKDIR/cfg.json"
  assert_success
  assert_line 'team_mode=teammate'
  assert_line 'fallback_notice=false'
  assert_line 'auto_detected=true'
}

# --- 12. Auto mode without env var -> task with fallback ---

@test "auto mode without env var falls back to task" {
  unset CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS 2>/dev/null || true
  echo '{"team_mode":"auto","agent_teams":true}' > "$TEST_WORKDIR/cfg.json"
  run bash "$SUT" "$TEST_WORKDIR/cfg.json"
  assert_success
  assert_line 'team_mode=task'
  assert_line 'fallback_notice=true'
  assert_line 'auto_detected=false'
}

# --- 13. Auto mode with env var but agent_teams=false -> task ---

@test "auto mode with agent_teams=false falls back to task" {
  export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
  echo '{"team_mode":"auto","agent_teams":false}' > "$TEST_WORKDIR/cfg.json"
  run bash "$SUT" "$TEST_WORKDIR/cfg.json"
  assert_success
  assert_line 'team_mode=task'
  assert_line 'fallback_notice=true'
  assert_line 'auto_detected=false'
}

# --- 14. Auto mode outputs exactly 3 lines ---

@test "auto mode outputs exactly 3 lines" {
  export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
  echo '{"team_mode":"auto","agent_teams":true}' > "$TEST_WORKDIR/cfg.json"
  run bash "$SUT" "$TEST_WORKDIR/cfg.json"
  assert_success
  local line_count
  line_count=$(echo "$output" | wc -l | tr -d ' ')
  [ "$line_count" -eq 3 ]
}

# --- 15. Task mode still outputs exactly 2 lines ---

@test "task mode outputs exactly 2 lines" {
  echo '{"team_mode":"task","agent_teams":true}' > "$TEST_WORKDIR/cfg.json"
  run bash "$SUT" "$TEST_WORKDIR/cfg.json"
  assert_success
  local line_count
  line_count=$(echo "$output" | wc -l | tr -d ' ')
  [ "$line_count" -eq 2 ]
}

# --- 16. Teammate mode still outputs exactly 2 lines ---

@test "teammate mode outputs exactly 2 lines" {
  export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
  echo '{"team_mode":"teammate","agent_teams":true}' > "$TEST_WORKDIR/cfg.json"
  run bash "$SUT" "$TEST_WORKDIR/cfg.json"
  assert_success
  local line_count
  line_count=$(echo "$output" | wc -l | tr -d ' ')
  [ "$line_count" -eq 2 ]
}

# --- 17. Auto mode with missing agent_teams field defaults to true ---

@test "auto mode with missing agent_teams defaults to true" {
  export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
  echo '{"team_mode":"auto"}' > "$TEST_WORKDIR/cfg.json"
  run bash "$SUT" "$TEST_WORKDIR/cfg.json"
  assert_success
  assert_line 'team_mode=teammate'
  assert_line 'auto_detected=true'
}
