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

# --- 4. Config missing team_mode field defaults to task ---

@test "config missing team_mode field defaults to task" {
  echo '{"agent_teams":true}' > "$TEST_WORKDIR/cfg.json"
  run bash "$SUT" "$TEST_WORKDIR/cfg.json"
  assert_success
  assert_line 'team_mode=task'
  assert_line 'fallback_notice=false'
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

# --- 9. Output format: exactly 2 lines ---

@test "outputs exactly 2 lines" {
  run bash "$SUT" "$TEST_WORKDIR/nonexistent.json"
  assert_success
  local line_count
  line_count=$(echo "$output" | wc -l | tr -d ' ')
  [ "$line_count" -eq 2 ]
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
