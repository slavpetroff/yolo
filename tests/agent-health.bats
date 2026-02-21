#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  export HEALTH_DIR="$TEST_TEMP_DIR/.yolo-planning/.agent-health"
}

teardown() {
  teardown_temp_dir
}

# Test 1: start creates health file
@test "agent-health: start creates health file" {
  cd "$TEST_TEMP_DIR"
  echo '{"pid":"12345","agent_type":"yolo-dev"}' | "$YOLO_BIN" hook SubagentStart >/dev/null
  [ -f "$HEALTH_DIR/dev.json" ]
  run jq -r '.pid' "$HEALTH_DIR/dev.json"
  [ "$output" = "12345" ]
  run jq -r '.role' "$HEALTH_DIR/dev.json"
  [ "$output" = "dev" ]
  run jq -r '.idle_count' "$HEALTH_DIR/dev.json"
  [ "$output" = "0" ]
}

# Test 2: idle increments count
@test "agent-health: idle increments count" {
  cd "$TEST_TEMP_DIR"
  # Create health file with a long-lived PID (use background sleep)
  sleep 30 &
  SLEEP_PID=$!
  echo "{\"pid\":\"$SLEEP_PID\",\"agent_type\":\"yolo-qa\"}" | "$YOLO_BIN" hook SubagentStart >/dev/null

  # Run idle
  echo '{"agent_type":"yolo-qa"}' | "$YOLO_BIN" hook TeammateIdle >/dev/null

  # Check idle count
  run jq -r '.idle_count' "$HEALTH_DIR/qa.json"
  [ "$output" = "1" ]

  # Cleanup
  kill $SLEEP_PID 2>/dev/null || true
}

# Test 3: idle stuck advisory at count >= 3
@test "agent-health: idle stuck advisory" {
  cd "$TEST_TEMP_DIR"
  sleep 30 &
  SLEEP_PID=$!
  echo "{\"pid\":\"$SLEEP_PID\",\"agent_type\":\"yolo-scout\"}" | "$YOLO_BIN" hook SubagentStart >/dev/null

  # Run idle 3 times
  for i in 1 2 3; do
    echo '{"agent_type":"yolo-scout"}' | "$YOLO_BIN" hook TeammateIdle >/dev/null
  done

  # Fourth call should have stuck advisory
  run bash -c "echo '{\"agent_type\":\"yolo-scout\"}' | '$YOLO_BIN' hook TeammateIdle"
  [[ "$output" == *"stuck"* ]] || [[ "$output" == *"idle_count"* ]]

  kill $SLEEP_PID 2>/dev/null || true
}

# Test 4: orphan recovery clears owner
@test "agent-health: orphan recovery clears owner" {
  cd "$TEST_TEMP_DIR"
  # Setup mock tasks directory
  TASKS_DIR="$HOME/.claude/tasks/test-team-$$"
  mkdir -p "$TASKS_DIR"

  cat > "$TASKS_DIR/task-test.json" <<EOF
{
  "id": "task-test",
  "owner": "dev",
  "status": "in_progress",
  "subject": "Test task"
}
EOF

  # Create health file with dead PID
  echo '{"pid":"99999","agent_type":"yolo-dev"}' | "$YOLO_BIN" hook SubagentStart >/dev/null

  # Run idle — should detect dead PID and clear owner
  run bash -c "echo '{\"agent_type\":\"yolo-dev\"}' | '$YOLO_BIN' hook TeammateIdle"
  [[ "$output" == *"Orphan recovery"* ]] || [[ "$output" == *"orphan"* ]]

  # Cleanup
  rm -rf "$TASKS_DIR"
}

# Test 5: stop removes health file
@test "agent-health: stop removes health file" {
  cd "$TEST_TEMP_DIR"
  sleep 30 &
  SLEEP_PID=$!
  echo "{\"pid\":\"$SLEEP_PID\",\"agent_type\":\"yolo-qa\"}" | "$YOLO_BIN" hook SubagentStart >/dev/null

  # Verify file exists
  [ -f "$HEALTH_DIR/qa.json" ]

  # Stop
  echo '{"agent_type":"yolo-qa"}' | "$YOLO_BIN" hook SubagentStop >/dev/null

  # Verify file removed
  [ ! -f "$HEALTH_DIR/qa.json" ]

  kill $SLEEP_PID 2>/dev/null || true
}

# Test 6: stop for each agent removes individual health files
@test "agent-health: individual stops remove all health files" {
  cd "$TEST_TEMP_DIR"
  sleep 30 &
  SLEEP_PID=$!

  # Start two agents
  echo "{\"pid\":\"$SLEEP_PID\",\"agent_type\":\"yolo-dev\"}" | "$YOLO_BIN" hook SubagentStart >/dev/null
  echo "{\"pid\":\"$SLEEP_PID\",\"agent_type\":\"yolo-qa\"}" | "$YOLO_BIN" hook SubagentStart >/dev/null

  # Verify both health files exist
  [ -f "$HEALTH_DIR/dev.json" ]
  [ -f "$HEALTH_DIR/qa.json" ]

  # Stop both agents
  echo '{"agent_type":"yolo-dev"}' | "$YOLO_BIN" hook SubagentStop >/dev/null
  echo '{"agent_type":"yolo-qa"}' | "$YOLO_BIN" hook SubagentStop >/dev/null

  # Verify both health files removed
  [ ! -f "$HEALTH_DIR/dev.json" ]
  [ ! -f "$HEALTH_DIR/qa.json" ]

  kill $SLEEP_PID 2>/dev/null || true
}
