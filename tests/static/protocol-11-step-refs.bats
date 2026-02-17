#!/usr/bin/env bats
# protocol-11-step-refs.bats -- Static validation: zero stale 10-step references in codebase

setup() {
  load '../test_helper/common'
}

@test "zero 10-step references in agent files" {
  run grep -rl '10-step' "$AGENTS_DIR"/
  assert_failure "Found stale 10-step reference in agent files: $output"
}

@test "zero 10-step references in reference files" {
  local REFS_DIR="$PROJECT_ROOT/references"
  run grep -rl '10-step' "$REFS_DIR"/
  assert_failure "Found stale 10-step reference in reference files: $output"
}

@test "zero 10-step references in command files" {
  run grep -rl '10-step' "$COMMANDS_DIR"/
  assert_failure "Found stale 10-step reference in command files: $output"
}

@test "zero 10-step references in department protocol files" {
  local DEPT_DIR="$PROJECT_ROOT/references/departments"
  run grep -rl '10-step' "$DEPT_DIR"/
  assert_failure "Found stale 10-step reference in department files: $output"
}

@test "yolo-lead.md references 11-step" {
  run grep '11-step' "$AGENTS_DIR/yolo-lead.md"
  assert_success
}

@test "yolo-fe-lead.md references 11-step" {
  run grep '11-step' "$AGENTS_DIR/yolo-fe-lead.md"
  assert_success
}

@test "yolo-ux-lead.md references 11-step" {
  run grep '11-step' "$AGENTS_DIR/yolo-ux-lead.md"
  assert_success
}

@test "cross-team-protocol.md uses 11-step throughout" {
  local REFS_DIR="$PROJECT_ROOT/references"
  run grep -c '11-step' "$REFS_DIR/cross-team-protocol.md"
  assert_success
  [[ "$output" -ge 6 ]] || fail "Expected at least 6 occurrences of 11-step in cross-team-protocol.md, got $output"
}

@test "execute-protocol.md header says 11-step" {
  local REFS_DIR="$PROJECT_ROOT/references"
  run grep '11-step' "$REFS_DIR/execute-protocol.md"
  assert_success
}

@test "backend.toon says 11-step" {
  local DEPT_DIR="$PROJECT_ROOT/references/departments"
  run grep '11-step' "$DEPT_DIR/backend.toon"
  assert_success
}

@test "frontend.toon says 11-step" {
  local DEPT_DIR="$PROJECT_ROOT/references/departments"
  run grep '11-step' "$DEPT_DIR/frontend.toon"
  assert_success
}

@test "uiux.toon says 11-step" {
  local DEPT_DIR="$PROJECT_ROOT/references/departments"
  run grep '11-step' "$DEPT_DIR/uiux.toon"
  assert_success
}
