#!/usr/bin/env bats
# validate-send-message.bats — Unit tests for scripts/validate-send-message.sh
# PostToolUse hook: enforces cross-department communication rules.
# Exit codes: 0 = allow, 2 = block

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/validate-send-message.sh"

  # Create planning dir and active-agent file
  mkdir -p "$TEST_WORKDIR/.yolo-planning"
}

# Helper: run validate-send-message with sender and recipient
run_validate() {
  local sender="$1" recipient="$2"
  echo "$sender" > "$TEST_WORKDIR/.yolo-planning/.active-agent"
  run bash -c "jq -n --arg tool 'SendMessage' --arg rec '$recipient' '{tool_name:\$tool,tool_input:{recipient:\$rec}}' | bash '$SUT'"
}

# --- Same department communication ---

@test "backend dev to backend lead: allowed" {
  run_validate "yolo-dev" "yolo-lead"
  assert_success
}

@test "backend lead to backend dev: allowed" {
  run_validate "yolo-lead" "yolo-dev"
  assert_success
}

@test "backend architect to backend qa: allowed" {
  run_validate "yolo-architect" "yolo-qa"
  assert_success
}

@test "frontend dev to frontend lead: allowed" {
  run_validate "yolo-fe-dev" "yolo-fe-lead"
  assert_success
}

@test "frontend lead to frontend dev: allowed" {
  run_validate "yolo-fe-lead" "yolo-fe-dev"
  assert_success
}

@test "uiux dev to uiux lead: allowed" {
  run_validate "yolo-ux-dev" "yolo-ux-lead"
  assert_success
}

@test "uiux lead to uiux dev: allowed" {
  run_validate "yolo-ux-lead" "yolo-ux-dev"
  assert_success
}

# --- Escalation: any agent to Owner ---

@test "backend dev to owner: allowed (escalation)" {
  run_validate "yolo-dev" "yolo-owner"
  assert_success
}

@test "backend lead to owner: allowed (escalation)" {
  run_validate "yolo-lead" "yolo-owner"
  assert_success
}

@test "frontend lead to owner: allowed (escalation)" {
  run_validate "yolo-fe-lead" "yolo-owner"
  assert_success
}

@test "uiux lead to owner: allowed (escalation)" {
  run_validate "yolo-ux-lead" "yolo-owner"
  assert_success
}

@test "frontend dev to owner: allowed (escalation)" {
  run_validate "yolo-fe-dev" "yolo-owner"
  assert_success
}

# --- Delegation: Owner to any Lead ---

@test "owner to backend lead: allowed (delegation)" {
  run_validate "yolo-owner" "yolo-lead"
  assert_success
}

@test "owner to frontend lead: allowed (delegation)" {
  run_validate "yolo-owner" "yolo-fe-lead"
  assert_success
}

@test "owner to uiux lead: allowed (delegation)" {
  run_validate "yolo-owner" "yolo-ux-lead"
  assert_success
}

@test "owner to backend dev: allowed" {
  run_validate "yolo-owner" "yolo-dev"
  assert_success
}

@test "owner to frontend dev: allowed" {
  run_validate "yolo-owner" "yolo-fe-dev"
  assert_success
}

# --- Shared agents can talk to anyone ---

@test "scout to backend lead: allowed (shared agent)" {
  run_validate "yolo-scout" "yolo-lead"
  assert_success
}

@test "scout to frontend lead: allowed (shared agent)" {
  run_validate "yolo-scout" "yolo-fe-lead"
  assert_success
}

@test "debugger to uiux dev: allowed (shared agent)" {
  run_validate "yolo-debugger" "yolo-ux-dev"
  assert_success
}

@test "security to owner: allowed (shared agent)" {
  run_validate "yolo-security" "yolo-owner"
  assert_success
}

@test "critic to backend dev: allowed (shared agent)" {
  run_validate "yolo-critic" "yolo-dev"
  assert_success
}

# --- Anyone can talk to shared agents ---

@test "backend dev to scout: allowed" {
  run_validate "yolo-dev" "yolo-scout"
  assert_success
}

@test "frontend dev to debugger: allowed" {
  run_validate "yolo-fe-dev" "yolo-debugger"
  assert_success
}

@test "uiux lead to security: allowed" {
  run_validate "yolo-ux-lead" "yolo-security"
  assert_success
}

@test "backend lead to critic: allowed" {
  run_validate "yolo-lead" "yolo-critic"
  assert_success
}

# --- Cross-department violations: BLOCKED ---

@test "backend dev to frontend lead: BLOCKED" {
  run_validate "yolo-dev" "yolo-fe-lead"
  assert_failure
  [ "$status" -eq 2 ]
  assert_output --partial "BLOCKED"
  assert_output --partial "cannot send message to"
}

@test "backend dev to frontend dev: BLOCKED" {
  run_validate "yolo-dev" "yolo-fe-dev"
  assert_failure
  [ "$status" -eq 2 ]
  assert_output --partial "BLOCKED"
}

@test "frontend dev to backend lead: BLOCKED" {
  run_validate "yolo-fe-dev" "yolo-lead"
  assert_failure
  [ "$status" -eq 2 ]
  assert_output --partial "BLOCKED"
}

@test "frontend dev to backend dev: BLOCKED" {
  run_validate "yolo-fe-dev" "yolo-dev"
  assert_failure
  [ "$status" -eq 2 ]
  assert_output --partial "BLOCKED"
}

@test "frontend dev to uiux lead: BLOCKED" {
  run_validate "yolo-fe-dev" "yolo-ux-lead"
  assert_failure
  [ "$status" -eq 2 ]
  assert_output --partial "BLOCKED"
}

@test "frontend dev to uiux dev: BLOCKED" {
  run_validate "yolo-fe-dev" "yolo-ux-dev"
  assert_failure
  [ "$status" -eq 2 ]
  assert_output --partial "BLOCKED"
}

@test "uiux dev to backend lead: BLOCKED" {
  run_validate "yolo-ux-dev" "yolo-lead"
  assert_failure
  [ "$status" -eq 2 ]
  assert_output --partial "BLOCKED"
}

@test "uiux dev to frontend lead: BLOCKED" {
  run_validate "yolo-ux-dev" "yolo-fe-lead"
  assert_failure
  [ "$status" -eq 2 ]
  assert_output --partial "BLOCKED"
}

@test "backend lead to frontend lead: BLOCKED (leads must use owner)" {
  run_validate "yolo-lead" "yolo-fe-lead"
  assert_failure
  [ "$status" -eq 2 ]
  assert_output --partial "BLOCKED"
}

@test "frontend lead to uiux lead: BLOCKED (leads must use owner)" {
  run_validate "yolo-fe-lead" "yolo-ux-lead"
  assert_failure
  [ "$status" -eq 2 ]
  assert_output --partial "BLOCKED"
}

# --- No .active-agent file: fail-open ---

@test "no active-agent file: allow all messages" {
  rm -f "$TEST_WORKDIR/.yolo-planning/.active-agent"
  run bash -c "jq -n --arg tool 'SendMessage' --arg rec 'yolo-fe-lead' '{tool_name:\$tool,tool_input:{recipient:\$rec}}' | bash '$SUT'"
  assert_success
}

# --- Empty .active-agent file ---

@test "empty active-agent file: allow all messages" {
  touch "$TEST_WORKDIR/.yolo-planning/.active-agent"
  run bash -c "jq -n --arg tool 'SendMessage' --arg rec 'yolo-fe-lead' '{tool_name:\$tool,tool_input:{recipient:\$rec}}' | bash '$SUT'"
  assert_success
}

# --- Non-SendMessage tools ---

@test "non-SendMessage tool: always allowed" {
  echo "yolo-dev" > "$TEST_WORKDIR/.yolo-planning/.active-agent"
  run bash -c "jq -n '{tool_name:\"Task\",tool_input:{}}' | bash '$SUT'"
  assert_success
}

@test "Task tool: allowed regardless of agent" {
  echo "yolo-fe-dev" > "$TEST_WORKDIR/.yolo-planning/.active-agent"
  run bash -c "jq -n '{tool_name:\"Task\",tool_input:{recipient:\"yolo-lead\"}}' | bash '$SUT'"
  assert_success
}

# --- Empty stdin ---

@test "empty stdin: allow" {
  run bash -c "echo '' | bash '$SUT'"
  assert_success
}

# --- Missing recipient ---

@test "missing recipient field: allow" {
  echo "yolo-dev" > "$TEST_WORKDIR/.yolo-planning/.active-agent"
  run bash -c "jq -n '{tool_name:\"SendMessage\",tool_input:{}}' | bash '$SUT'"
  assert_success
}

# --- Malformed JSON ---

@test "malformed JSON input: allow (graceful degradation)" {
  echo "yolo-dev" > "$TEST_WORKDIR/.yolo-planning/.active-agent"
  run bash -c "echo '{invalid json' | bash '$SUT'"
  assert_success
}

# --- Unknown agent names ---

@test "unknown sender agent: cross-dept blocked (unknown dept)" {
  echo "unknown-agent" > "$TEST_WORKDIR/.yolo-planning/.active-agent"
  run bash -c "jq -n --arg tool 'SendMessage' --arg rec 'yolo-fe-lead' '{tool_name:\$tool,tool_input:{recipient:\$rec}}' | bash '$SUT'"
  # unknown-agent → unknown dept → frontend dept = blocked
  assert_failure
  [ "$status" -eq 2 ]
}

@test "unknown recipient agent: cross-dept blocked" {
  echo "yolo-dev" > "$TEST_WORKDIR/.yolo-planning/.active-agent"
  run bash -c "jq -n --arg tool 'SendMessage' --arg rec 'unknown-agent' '{tool_name:\$tool,tool_input:{recipient:\$rec}}' | bash '$SUT'"
  # yolo-dev (backend) → unknown-agent (unknown)
  # Backend != unknown = blocked
  assert_failure
  [ "$status" -eq 2 ]
}

# --- Broadcast messages (no recipient) ---

@test "broadcast type message: no recipient validation" {
  echo "yolo-dev" > "$TEST_WORKDIR/.yolo-planning/.active-agent"
  run bash -c "jq -n --arg tool 'SendMessage' '{tool_name:\$tool,tool_input:{type:\"broadcast\",content:\"test\"}}' | bash '$SUT'"
  assert_success
}
