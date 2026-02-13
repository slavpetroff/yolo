#!/usr/bin/env bats
# department-guard.bats — Unit tests for scripts/department-guard.sh
# Tests department boundary enforcement for Write/Edit operations.

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/department-guard.sh"
}

# Helper: run department-guard with agent and file path
run_guard() {
  local agent="$1" file_path="$2"
  YOLO_AGENT="$agent" run bash -c "echo '{\"file_path\":\"$file_path\"}' | bash '$SUT'"
}

# --- Backend agent boundary tests ---

@test "backend agent can write to scripts/" {
  run_guard "yolo-dev" "scripts/foo.sh"
  assert_success
}

@test "backend agent can write to .yolo-planning/" {
  run_guard "yolo-dev" ".yolo-planning/phases/01/plan.jsonl"
  assert_success
}

@test "backend agent blocked from frontend/" {
  run_guard "yolo-dev" "frontend/App.tsx"
  assert_failure
  assert_output --partial "BLOCKED"
}

@test "backend agent blocked from design/" {
  run_guard "yolo-dev" "design/tokens.json"
  assert_failure
  assert_output --partial "BLOCKED"
}

# --- Frontend agent boundary tests ---

@test "frontend agent can write to src/components/" {
  run_guard "yolo-fe-dev" "src/components/Button.tsx"
  assert_success
}

@test "frontend agent can write to .yolo-planning/" {
  run_guard "yolo-fe-dev" ".yolo-planning/phases/01/plan.jsonl"
  assert_success
}

@test "frontend agent blocked from scripts/" {
  run_guard "yolo-fe-dev" "scripts/foo.sh"
  assert_failure
  assert_output --partial "BLOCKED"
}

@test "frontend agent blocked from agents/" {
  run_guard "yolo-fe-dev" "agents/yolo-dev.md"
  assert_failure
  assert_output --partial "BLOCKED"
}

@test "frontend agent blocked from design/" {
  run_guard "yolo-fe-dev" "design/tokens.json"
  assert_failure
  assert_output --partial "BLOCKED"
}

# --- UI/UX agent boundary tests ---

@test "uiux agent can write to design/" {
  run_guard "yolo-ux-dev" "design/tokens.json"
  assert_success
}

@test "uiux agent can write to .yolo-planning/" {
  run_guard "yolo-ux-dev" ".yolo-planning/phases/01/plan.jsonl"
  assert_success
}

@test "uiux agent blocked from src/" {
  run_guard "yolo-ux-dev" "src/components/Button.tsx"
  assert_failure
  assert_output --partial "BLOCKED"
}

@test "uiux agent blocked from scripts/" {
  run_guard "yolo-ux-dev" "scripts/foo.sh"
  assert_failure
  assert_output --partial "BLOCKED"
}

# --- Shared/Owner agents ---

@test "owner agent is allowed (read-only enforced by agent def)" {
  run_guard "yolo-owner" "any/file.txt"
  assert_success
}

@test "security agent is allowed (shared)" {
  run_guard "yolo-security" "any/file.txt"
  assert_success
}

# --- Graceful degradation ---

@test "no YOLO_AGENT env var allows all writes" {
  unset YOLO_AGENT
  run bash -c "echo '{\"file_path\":\"frontend/App.tsx\"}' | bash '$SUT'"
  assert_success
}

@test "empty stdin allows all writes" {
  YOLO_AGENT="yolo-dev" run bash -c "echo '' | bash '$SUT'"
  assert_success
}

@test "unknown agent allows all writes" {
  run_guard "unknown-agent" "frontend/App.tsx"
  assert_success
}
