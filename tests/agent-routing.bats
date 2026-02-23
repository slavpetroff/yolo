#!/usr/bin/env bats

load test_helper

setup() {
  PROJECT_ROOT="${BATS_TEST_DIRNAME}/.."
}

# --- Agent routing (subagent_type) in execute-protocol and plan.md ---

@test "execute-protocol contains subagent_type mapping table" {
  run grep -c "Agent routing (subagent_type)" "$PROJECT_ROOT/skills/execute-protocol/SKILL.md"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

@test "execute-protocol Step 3 Dev spawn has subagent_type" {
  run grep 'subagent_type: "yolo:yolo-dev"' "$PROJECT_ROOT/skills/execute-protocol/SKILL.md"
  [ "$status" -eq 0 ]
}

@test "execute-protocol Step 2b Architect spawn has subagent_type" {
  run grep 'subagent_type: "yolo:yolo-architect"' "$PROJECT_ROOT/skills/execute-protocol/SKILL.md"
  [ "$status" -eq 0 ]
}

@test "execute-protocol Step 3d QA Dev spawn has subagent_type" {
  run bash -c "grep -c 'subagent_type: \"yolo:yolo-dev\"' '$PROJECT_ROOT/skills/execute-protocol/SKILL.md'"
  [ "$status" -eq 0 ]
  [ "$output" -ge 2 ]
}

@test "plan.md Lead spawn has subagent_type" {
  run grep 'subagent_type: "yolo:yolo-lead"' "$PROJECT_ROOT/skills/vibe-modes/plan.md"
  [ "$status" -eq 0 ]
}
