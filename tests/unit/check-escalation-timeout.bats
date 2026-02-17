#!/usr/bin/env bats
# check-escalation-timeout.bats — Unit tests for scripts/check-escalation-timeout.sh
# Plan 05-04 T1 (escalation timeout detection)

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/check-escalation-timeout.sh"
  PHASE_DIR="$TEST_WORKDIR/phase-test"
  mkdir -p "$PHASE_DIR"
  CONFIG_FILE="$TEST_WORKDIR/config.json"
  echo '{"escalation":{"timeout_seconds":300,"auto_owner_on_timeout":true,"max_round_trips":2}}' > "$CONFIG_FILE"
}

# Helper: create .execution-state.json with given escalations array
mk_state_with_escalations() {
  local escalations_json="$1"
  cat > "$PHASE_DIR/.execution-state.json" <<EOF
{"phase":5,"phase_name":"test","status":"running","escalations":$escalations_json}
EOF
}

# Helper: get ISO timestamp N seconds ago
seconds_ago() {
  local secs="$1"
  local epoch=$(($(date +%s) - secs))
  # Try GNU date first, then BSD date
  date -u -d "@$epoch" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
    date -u -r "$epoch" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
    echo "2026-01-01T00:00:00Z"
}

@test "no escalations array returns empty result" {
  cat > "$PHASE_DIR/.execution-state.json" <<'EOF'
{"phase":5,"phase_name":"test","status":"running"}
EOF
  run bash "$SUT" --phase-dir "$PHASE_DIR" --config "$CONFIG_FILE"
  assert_success
  local timed_out active resolved
  timed_out=$(echo "$output" | jq '.timed_out | length')
  active=$(echo "$output" | jq '.active | length')
  resolved=$(echo "$output" | jq '.resolved')
  [ "$timed_out" -eq 0 ]
  [ "$active" -eq 0 ]
  [ "$resolved" -eq 0 ]
}

@test "no pending escalations returns clean result" {
  local ts
  ts=$(seconds_ago 60)
  mk_state_with_escalations "[{\"id\":\"E1\",\"task\":\"T1\",\"status\":\"resolved\",\"last_escalated_at\":\"$ts\"},{\"id\":\"E2\",\"task\":\"T2\",\"status\":\"resolved\",\"last_escalated_at\":\"$ts\"}]"
  run bash "$SUT" --phase-dir "$PHASE_DIR" --config "$CONFIG_FILE"
  assert_success
  local resolved
  resolved=$(echo "$output" | jq '.resolved')
  [ "$resolved" -eq 2 ]
}

@test "pending escalation within timeout returns active" {
  local ts
  ts=$(seconds_ago 60)
  mk_state_with_escalations "[{\"id\":\"E1\",\"task\":\"T1\",\"status\":\"pending\",\"last_escalated_at\":\"$ts\"}]"
  run bash "$SUT" --phase-dir "$PHASE_DIR" --config "$CONFIG_FILE"
  assert_success
  local active_count active_id
  active_count=$(echo "$output" | jq '.active | length')
  active_id=$(echo "$output" | jq -r '.active[0].id')
  [ "$active_count" -eq 1 ]
  [ "$active_id" = "E1" ]
}

@test "pending escalation past timeout returns timed_out" {
  local ts
  ts=$(seconds_ago 400)
  mk_state_with_escalations "[{\"id\":\"E1\",\"task\":\"T1\",\"status\":\"pending\",\"last_escalated_at\":\"$ts\"}]"
  run bash "$SUT" --phase-dir "$PHASE_DIR" --config "$CONFIG_FILE"
  assert_failure
  local timed_count timed_id
  timed_count=$(echo "$output" | jq '.timed_out | length')
  timed_id=$(echo "$output" | jq -r '.timed_out[0].id')
  [ "$timed_count" -eq 1 ]
  [ "$timed_id" = "E1" ]
}

@test "config fallback to 300 when escalation key missing" {
  echo '{}' > "$CONFIG_FILE"
  local ts
  ts=$(seconds_ago 60)
  mk_state_with_escalations "[{\"id\":\"E1\",\"task\":\"T1\",\"status\":\"pending\",\"last_escalated_at\":\"$ts\"}]"
  run bash "$SUT" --phase-dir "$PHASE_DIR" --config "$CONFIG_FILE"
  assert_success
  local active_count
  active_count=$(echo "$output" | jq '.active | length')
  [ "$active_count" -eq 1 ]
}

@test "missing state file returns empty result" {
  rm -f "$PHASE_DIR/.execution-state.json"
  run bash "$SUT" --phase-dir "$PHASE_DIR" --config "$CONFIG_FILE"
  assert_success
  local timed_out active resolved
  timed_out=$(echo "$output" | jq '.timed_out | length')
  active=$(echo "$output" | jq '.active | length')
  resolved=$(echo "$output" | jq '.resolved')
  [ "$timed_out" -eq 0 ]
  [ "$active" -eq 0 ]
  [ "$resolved" -eq 0 ]
}

@test "mixed states: some active, some timed_out, some resolved" {
  local ts_recent ts_old
  ts_recent=$(seconds_ago 60)
  ts_old=$(seconds_ago 500)
  mk_state_with_escalations "[{\"id\":\"E1\",\"task\":\"T1\",\"status\":\"pending\",\"last_escalated_at\":\"$ts_recent\"},{\"id\":\"E2\",\"task\":\"T2\",\"status\":\"pending\",\"last_escalated_at\":\"$ts_old\"},{\"id\":\"E3\",\"task\":\"T3\",\"status\":\"resolved\",\"last_escalated_at\":\"$ts_recent\"}]"
  run bash "$SUT" --phase-dir "$PHASE_DIR" --config "$CONFIG_FILE"
  assert_failure
  local timed_count active_count resolved
  timed_count=$(echo "$output" | jq '.timed_out | length')
  active_count=$(echo "$output" | jq '.active | length')
  resolved=$(echo "$output" | jq '.resolved')
  [ "$timed_count" -eq 1 ]
  [ "$active_count" -eq 1 ]
  [ "$resolved" -eq 1 ]
}
