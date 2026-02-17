#!/usr/bin/env bats
# graceful-degradation.bats -- Integration tests: configuration cascade, documentation coverage, regression

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  mk_test_workdir
  RESOLVE="$SCRIPTS_DIR/resolve-team-mode.sh"
  PATTERNS="$PROJECT_ROOT/references/teammate-api-patterns.md"
  LEAD="$AGENTS_DIR/yolo-lead.md"
}

# --- Configuration Cascade Validation (real script execution) ---

@test "auto mode with env var selects teammate (config cascade)" {
  export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
  echo '{"team_mode":"auto","agent_teams":true}' > "$TEST_WORKDIR/cfg.json"
  run bash "$RESOLVE" "$TEST_WORKDIR/cfg.json"
  assert_success
  assert_line 'team_mode=teammate'
  assert_line 'auto_detected=true'
}

@test "auto mode without env var falls back to task (config cascade)" {
  unset CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS 2>/dev/null || true
  echo '{"team_mode":"auto","agent_teams":true}' > "$TEST_WORKDIR/cfg.json"
  run bash "$RESOLVE" "$TEST_WORKDIR/cfg.json"
  assert_success
  assert_line 'team_mode=task'
  assert_line 'fallback_notice=true'
}

@test "auto mode with agent_teams=false falls back to task (config cascade)" {
  export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
  echo '{"team_mode":"auto","agent_teams":false}' > "$TEST_WORKDIR/cfg.json"
  run bash "$RESOLVE" "$TEST_WORKDIR/cfg.json"
  assert_success
  assert_line 'team_mode=task'
  assert_line 'fallback_notice=true'
}

@test "teammate mode without env var falls back to task (config cascade)" {
  unset CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS 2>/dev/null || true
  echo '{"team_mode":"teammate","agent_teams":true}' > "$TEST_WORKDIR/cfg.json"
  run bash "$RESOLVE" "$TEST_WORKDIR/cfg.json"
  assert_success
  assert_line 'team_mode=task'
  assert_line 'fallback_notice=true'
}

# --- Documentation Coverage Tests ---

@test "teammate-api-patterns.md documents all 3 fallback tiers" {
  run grep -c '### Tier' "$PATTERNS"
  assert_success
  [ "$output" -ge 3 ]
}

@test "yolo-lead.md documents all circuit breaker states" {
  run grep -c 'Closed\|Open\|Half-Open' "$LEAD"
  assert_success
  [ "$output" -ge 3 ]
}

@test "yolo-lead.md has all Phase 4 resilience sections" {
  run grep '## Fallback Behavior' "$LEAD"
  assert_success
  run grep '## Agent Health Tracking' "$LEAD"
  assert_success
  run grep '## Circuit Breaker' "$LEAD"
  assert_success
  run grep '## Shutdown Protocol Enforcement' "$LEAD"
  assert_success
}
