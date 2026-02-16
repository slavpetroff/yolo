#!/usr/bin/env bats
# protocol-file-coord-refs.bats -- Validate protocol files reference file-based coordination

setup() {
  load '../test_helper/common'
}

@test "execute-protocol.md references dept-orchestrate.sh" {
  run grep -c 'dept-orchestrate.sh' "$PROJECT_ROOT/references/execute-protocol.md"
  assert_success
  [ "$output" -ge 1 ]
}

@test "execute-protocol.md references dept-cleanup.sh" {
  run grep -c 'dept-cleanup.sh' "$PROJECT_ROOT/references/execute-protocol.md"
  assert_success
  [ "$output" -ge 1 ]
}

@test "execute-protocol.md references run_in_background" {
  run grep -c 'run_in_background' "$PROJECT_ROOT/references/execute-protocol.md"
  assert_success
  [ "$output" -ge 1 ]
}

@test "execute-protocol.md preserves single-dept Task tool path" {
  run grep 'Task tool' "$PROJECT_ROOT/references/execute-protocol.md"
  assert_success
}

@test "multi-dept-protocol.md contains dept-status references" {
  run grep -c 'dept-status' "$PROJECT_ROOT/references/multi-dept-protocol.md"
  assert_success
  [ "$output" -ge 2 ]
}

@test "multi-dept-protocol.md contains Coordination Files section" {
  run grep 'Coordination Files' "$PROJECT_ROOT/references/multi-dept-protocol.md"
  assert_success
}

@test "cross-team-protocol.md references dept-gate.sh at least 3 times" {
  run grep -c 'dept-gate.sh' "$PROJECT_ROOT/references/cross-team-protocol.md"
  assert_success
  [ "$output" -ge 3 ]
}

@test "company-hierarchy.md references background Task subagent" {
  run grep 'background Task subagent' "$PROJECT_ROOT/references/company-hierarchy.md"
  assert_success
}

@test "multi-dept-protocol.md contains Polling Mechanism section" {
  run grep 'Polling Mechanism' "$PROJECT_ROOT/references/multi-dept-protocol.md"
  assert_success
}

@test "no protocol files reference spawnTeam for coordination" {
  run grep -r 'spawnTeam' "$PROJECT_ROOT/references/execute-protocol.md" "$PROJECT_ROOT/references/multi-dept-protocol.md" "$PROJECT_ROOT/references/cross-team-protocol.md" "$PROJECT_ROOT/references/company-hierarchy.md"
  assert_failure
}
