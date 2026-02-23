#!/usr/bin/env bats

load test_helper

setup() {
  PROJECT_ROOT="${BATS_TEST_DIRNAME}/.."
}

# --- Reviewer agent spawn tests (Step 2b) ---

@test "reviewer agent spawn: subagent_type yolo-reviewer appears at least 2 times" {
  run bash -c "grep -c 'subagent_type: \"yolo:yolo-reviewer\"' '$PROJECT_ROOT/skills/execute-protocol/SKILL.md'"
  [ "$status" -eq 0 ]
  [ "$output" -ge 2 ]
}

@test "reviewer agent spawn: Stage 2 reviewer section header exists" {
  run grep 'Stage 2 — Reviewer agent spawn' "$PROJECT_ROOT/skills/execute-protocol/SKILL.md"
  [ "$status" -eq 0 ]
}

@test "reviewer agent spawn: verdict parsing text exists" {
  run grep 'Verdict parsing from agent output' "$PROJECT_ROOT/skills/execute-protocol/SKILL.md"
  [ "$status" -eq 0 ]
}

# --- QA agent spawn tests (Step 3d) ---

@test "QA agent spawn: subagent_type yolo-qa appears at least 2 times" {
  run bash -c "grep -c 'subagent_type: \"yolo:yolo-qa\"' '$PROJECT_ROOT/skills/execute-protocol/SKILL.md'"
  [ "$status" -eq 0 ]
  [ "$output" -ge 2 ]
}

@test "QA agent spawn: Stage 2 QA agent section header exists" {
  run grep 'Stage 2 -- QA agent spawn' "$PROJECT_ROOT/skills/execute-protocol/SKILL.md"
  [ "$status" -eq 0 ]
}

@test "QA agent spawn: fast-path optimization text exists" {
  run grep 'Fast-path optimization' "$PROJECT_ROOT/skills/execute-protocol/SKILL.md"
  [ "$status" -eq 0 ]
}

@test "QA agent spawn: report parsing text exists" {
  run grep 'Report parsing from agent output' "$PROJECT_ROOT/skills/execute-protocol/SKILL.md"
  [ "$status" -eq 0 ]
}

# --- Feedback loop text tests ---

@test "feedback loops: review gate activation text exists" {
  run grep 'review_gate' "$PROJECT_ROOT/skills/execute-protocol/SKILL.md"
  [ "$status" -eq 0 ]
}

@test "feedback loops: QA gate activation text exists" {
  run grep 'qa_gate' "$PROJECT_ROOT/skills/execute-protocol/SKILL.md"
  [ "$status" -eq 0 ]
}

@test "feedback loops: review feedback loop cycle text exists" {
  run grep 'Enter review feedback loop' "$PROJECT_ROOT/skills/execute-protocol/SKILL.md"
  [ "$status" -eq 0 ]
}

@test "feedback loops: QA feedback loop text exists" {
  run grep 'QA feedback loop' "$PROJECT_ROOT/skills/execute-protocol/SKILL.md"
  [ "$status" -eq 0 ]
}

@test "feedback loops: review_max_cycles config text exists" {
  run grep 'review_max_cycles' "$PROJECT_ROOT/skills/execute-protocol/SKILL.md"
  [ "$status" -eq 0 ]
}

@test "feedback loops: qa_max_cycles config text exists" {
  run grep 'qa_max_cycles' "$PROJECT_ROOT/skills/execute-protocol/SKILL.md"
  [ "$status" -eq 0 ]
}

# --- Delegation mandate tests ---

@test "delegation mandate: Role reminder appears at least 3 times" {
  run bash -c "grep -c 'Role reminder:' '$PROJECT_ROOT/skills/execute-protocol/SKILL.md'"
  [ "$status" -eq 0 ]
  [ "$output" -ge 3 ]
}

@test "delegation mandate: NEVER implement tasks yourself text exists" {
  run grep 'NEVER implement tasks yourself' "$PROJECT_ROOT/skills/execute-protocol/SKILL.md"
  [ "$status" -eq 0 ]
}

@test "delegation mandate: anti-takeover language exists" {
  run grep 'NEVER Write/Edit' "$PROJECT_ROOT/skills/execute-protocol/SKILL.md"
  [ "$status" -eq 0 ]
}
