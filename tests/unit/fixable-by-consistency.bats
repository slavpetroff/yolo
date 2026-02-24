#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="${BATS_TEST_DIRNAME}/../.."
}

# --- Three-way fixable_by consistency: CLI, protocol, agent ---

@test "check-regression fixable_by is manual in Rust CLI source" {
  run grep -q '"fixable_by": "manual"' "$PROJECT_ROOT/yolo-mcp-server/src/commands/check_regression.rs"
  [ "$status" -eq 0 ]
}

@test "check-regression fixable_by is manual in execute protocol Step 3d table" {
  # Step 3d CLI classification table line
  run grep 'check-regression.*"manual"' "$PROJECT_ROOT/skills/execute-protocol/SKILL.md"
  [ "$status" -eq 0 ]
  # Must NOT say architect
  run grep 'check-regression.*"architect"' "$PROJECT_ROOT/skills/execute-protocol/SKILL.md"
  [ "$status" -ne 0 ]
}

@test "check-regression fixable_by is manual in QA agent definition" {
  run grep 'check-regression.*manual' "$PROJECT_ROOT/agents/yolo-qa.md"
  [ "$status" -eq 0 ]
}
