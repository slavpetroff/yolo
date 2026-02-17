#!/usr/bin/env bats
# agent-health-circuit-breaker.bats -- Static validation: health tracking and circuit breaker documentation
# Note (C9): These are prompt-level instructions, not executable scripts.
# Behavioral testing would require spawning actual Teammate API sessions.

setup() {
  load '../test_helper/common'
  PATTERNS="$PROJECT_ROOT/references/teammate-api-patterns.md"
  SCHEMAS="$PROJECT_ROOT/references/handoff-schemas.md"
}

@test "yolo-lead.md contains Agent Health Tracking section" {
  run grep '## Agent Health Tracking' "$AGENTS_DIR/yolo-lead.md"
  assert_success
}

@test "yolo-lead.md contains Circuit Breaker section" {
  run grep '## Circuit Breaker' "$AGENTS_DIR/yolo-lead.md"
  assert_success
}

@test "teammate-api-patterns.md contains Health Tracking section" {
  run grep '## Health Tracking' "$PATTERNS"
  assert_success
}

@test "handoff-schemas.md contains agent_health_event schema" {
  run grep 'agent_health_event' "$SCHEMAS"
  assert_success
}

@test "handoff-schemas.md contains circuit_breaker_state schema" {
  run grep 'circuit_breaker_state' "$SCHEMAS"
  assert_success
}

@test "Health Tracking documents all 4 lifecycle states" {
  for state in start idle stop disappeared; do
    run grep "$state" "$PATTERNS"
    assert_success
  done
}

@test "Circuit Breaker documents all 3 states" {
  run grep -c 'closed\|open\|half-open' "$AGENTS_DIR/yolo-lead.md"
  assert_success
  [ "$output" -ge 3 ]
}

@test "health tracking uses hardcoded 60s timeout" {
  run grep '60' "$AGENTS_DIR/yolo-lead.md"
  assert_success
}

@test "circuit breaker is per-department" {
  run grep -iE 'per-department|department isolation' "$AGENTS_DIR/yolo-lead.md"
  assert_success
}

@test "health tracking and circuit breaker are in-memory only" {
  run grep 'in-memory' "$AGENTS_DIR/yolo-lead.md"
  assert_success
}
