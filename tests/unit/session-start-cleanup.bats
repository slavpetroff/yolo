#!/usr/bin/env bats
# session-start-cleanup.bats -- Unit tests for orphaned .dept-status cleanup in session-start.sh

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  mk_test_workdir
  mk_git_repo
  SUT="$SCRIPTS_DIR/session-start.sh"
}

mk_stale_dept_status() {
  local name="$1" age_hours="${2:-25}"
  local file="$TEST_WORKDIR/.yolo-planning/.dept-status-${name}.json"
  echo '{"department":"'"$name"'","status":"complete"}' > "$file"
  if [ "$(uname)" = "Darwin" ]; then
    touch -t "$(date -v-${age_hours}H +%Y%m%d%H%M.%S)" "$file"
  else
    touch -d "-${age_hours} hours" "$file"
  fi
}

mk_fresh_dept_status() {
  local name="$1"
  echo '{"department":"'"$name"'","status":"complete"}' > "$TEST_WORKDIR/.yolo-planning/.dept-status-${name}.json"
}

@test "removes stale .dept-status files older than 24h" {
  mkdir -p "$TEST_WORKDIR/.yolo-planning"
  echo '{"agent_teams":true}' > "$TEST_WORKDIR/.yolo-planning/config.json"
  mk_stale_dept_status "backend" 25
  cd "$TEST_WORKDIR"
  run bash "$SUT"
  [ ! -f "$TEST_WORKDIR/.yolo-planning/.dept-status-backend.json" ]
}

@test "preserves recent .dept-status files" {
  mkdir -p "$TEST_WORKDIR/.yolo-planning"
  echo '{"agent_teams":true}' > "$TEST_WORKDIR/.yolo-planning/config.json"
  mk_fresh_dept_status "frontend"
  cd "$TEST_WORKDIR"
  run bash "$SUT"
  [ -f "$TEST_WORKDIR/.yolo-planning/.dept-status-frontend.json" ]
}

@test "skips cleanup when agent_teams=false" {
  mkdir -p "$TEST_WORKDIR/.yolo-planning"
  echo '{"agent_teams":false}' > "$TEST_WORKDIR/.yolo-planning/config.json"
  mk_stale_dept_status "backend" 25
  cd "$TEST_WORKDIR"
  run bash "$SUT"
  [ -f "$TEST_WORKDIR/.yolo-planning/.dept-status-backend.json" ]
}

@test "logs cleanup actions to stderr" {
  mkdir -p "$TEST_WORKDIR/.yolo-planning"
  echo '{"agent_teams":true}' > "$TEST_WORKDIR/.yolo-planning/config.json"
  mk_stale_dept_status "backend" 25
  cd "$TEST_WORKDIR"
  run bash -c "bash '$SUT' 2>&1"
  [[ "$output" =~ "cleaning stale dept-status" ]]
}

@test "session-start.sh still produces valid output" {
  mkdir -p "$TEST_WORKDIR/.yolo-planning"
  echo '{"agent_teams":true}' > "$TEST_WORKDIR/.yolo-planning/config.json"
  cd "$TEST_WORKDIR"
  run bash "$SUT"
  assert_success
}
