#!/usr/bin/env bats

load test_helper

setup() {
  PROJECT_ROOT="${BATS_TEST_DIRNAME}/.."
}

# --- Archive release automation (Step 8b) in archive.md ---

@test "archive.md contains Step 8b consolidated release" {
  run grep '8b\. \*\*Consolidated release' "$PROJECT_ROOT/skills/vibe-modes/archive.md"
  [ "$status" -eq 0 ]
}

@test "archive.md contains --no-release flag" {
  run grep '\-\-no-release' "$PROJECT_ROOT/skills/vibe-modes/archive.md"
  [ "$status" -eq 0 ]
}

@test "archive.md contains version bump logic" {
  run grep 'bump-version' "$PROJECT_ROOT/skills/vibe-modes/archive.md"
  [ "$status" -eq 0 ]
}

@test "archive.md contains changelog finalization" {
  run grep '\[Unreleased\]' "$PROJECT_ROOT/skills/vibe-modes/archive.md"
  [ "$status" -eq 0 ]
}

@test "archive.md release commit format" {
  run grep 'chore: release v' "$PROJECT_ROOT/skills/vibe-modes/archive.md"
  [ "$status" -eq 0 ]
}

@test "archive.md push gated by auto_push" {
  run grep 'auto_push' "$PROJECT_ROOT/skills/vibe-modes/archive.md"
  [ "$status" -eq 0 ]
}
