#!/usr/bin/env bats
# shutdown-protocol.bats -- Static validation: shutdown protocol documentation across all files

setup() {
  load '../test_helper/common'
  PATTERNS="$PROJECT_ROOT/references/teammate-api-patterns.md"
  SCHEMAS="$PROJECT_ROOT/references/handoff-schemas.md"
  EXEC_PROTO="$PROJECT_ROOT/references/execute-protocol.md"
}

@test "yolo-lead.md contains Shutdown Protocol Enforcement section" {
  run grep '## Shutdown Protocol Enforcement' "$AGENTS_DIR/yolo-lead.md"
  assert_success
}

@test "yolo-dev.md contains Shutdown Response section" {
  run grep '## Shutdown Response' "$AGENTS_DIR/yolo-dev.md"
  assert_success
}

@test "teammate-api-patterns.md shutdown mentions deadline_seconds" {
  run grep 'deadline_seconds' "$PATTERNS"
  assert_success
}

@test "teammate-api-patterns.md shutdown mentions timeout handling" {
  run grep -i 'timeout' "$PATTERNS"
  assert_success
}

@test "execute-protocol.md references shutdown protocol" {
  run grep 'shutdown' "$EXEC_PROTO"
  assert_success
}

@test "handoff-schemas.md contains shutdown_request schema" {
  run grep 'shutdown_request' "$SCHEMAS"
  assert_success
}

@test "handoff-schemas.md contains shutdown_response schema" {
  run grep 'shutdown_response' "$SCHEMAS"
  assert_success
}

@test "8 teammate agents reference Shutdown Response" {
  local count=0
  for agent in yolo-senior.md yolo-architect.md yolo-tester.md yolo-qa.md yolo-qa-code.md yolo-security.md yolo-fe-dev.md yolo-ux-dev.md; do
    if grep -q 'Shutdown Response' "$AGENTS_DIR/$agent"; then
      count=$((count + 1))
    fi
  done
  [ "$count" -eq 8 ]
}

@test "FE and UX Leads reference Shutdown Protocol Enforcement" {
  run grep 'Shutdown Protocol Enforcement' "$AGENTS_DIR/yolo-fe-lead.md"
  assert_success
  run grep 'Shutdown Protocol Enforcement' "$AGENTS_DIR/yolo-ux-lead.md"
  assert_success
}

@test "shutdown protocol mentions 30s deadline" {
  run grep '30s\|30 second\|deadline_seconds.*30' "$AGENTS_DIR/yolo-lead.md"
  assert_success
}
