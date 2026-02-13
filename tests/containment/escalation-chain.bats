#!/usr/bin/env bats
# escalation-chain.bats — Verify strict escalation chain enforcement across all 11 agents
# Rule: Each agent escalates ONLY to their direct report-to. No level skipping.
# Chain: Dev → Senior → Lead → Architect → User

setup() {
  load '../test_helper/common'
}

# Helper: check agent has escalation table with expected target
# Uses the "NEVER" constraint line which names the forbidden targets
assert_escalation_target() {
  local agent_file="$AGENTS_DIR/$1"
  local target="$2"
  # Check the escalation table section exists and mentions the target
  run grep -A 20 "## Escalation Table" "$agent_file"
  assert_success
  assert_output --partial "$target"
}

# --- Dev escalates to Senior ONLY ---

@test "yolo-dev.md escalates to Senior" {
  assert_escalation_target "yolo-dev.md" "Senior"
}

@test "yolo-dev.md NEVER escalates to Lead directly" {
  run grep "NEVER.*Lead" "$AGENTS_DIR/yolo-dev.md"
  assert_success
}

@test "yolo-dev.md NEVER escalates to Architect directly" {
  run grep "NEVER.*Architect" "$AGENTS_DIR/yolo-dev.md"
  assert_success
}

# --- Senior escalates to Lead ONLY ---

@test "yolo-senior.md has escalation table" {
  run grep -c "Escalation Table" "$AGENTS_DIR/yolo-senior.md"
  assert_success
  [ "$output" -ge 1 ]
}

@test "yolo-senior.md escalates to Lead" {
  assert_escalation_target "yolo-senior.md" "Lead"
}

@test "yolo-senior.md NEVER escalates to Architect directly" {
  run grep "NEVER.*Architect" "$AGENTS_DIR/yolo-senior.md"
  assert_success
}

# --- Lead escalates to Architect ONLY ---

@test "yolo-lead.md has escalation table" {
  run grep -c "Escalation Table" "$AGENTS_DIR/yolo-lead.md"
  assert_success
  [ "$output" -ge 1 ]
}

@test "yolo-lead.md escalates to Architect" {
  assert_escalation_target "yolo-lead.md" "Architect"
}

@test "yolo-lead.md NEVER escalates to User directly" {
  run grep "NEVER.*User" "$AGENTS_DIR/yolo-lead.md"
  assert_success
}

# --- Architect escalates to User ---

@test "yolo-architect.md has escalation table" {
  run grep -c "Escalation Table" "$AGENTS_DIR/yolo-architect.md"
  assert_success
  [ "$output" -ge 1 ]
}

@test "yolo-architect.md escalates to User" {
  assert_escalation_target "yolo-architect.md" "User"
}

# --- Tester escalates to Senior (NOT Lead) ---

@test "yolo-tester.md has escalation table" {
  run grep -c "Escalation Table" "$AGENTS_DIR/yolo-tester.md"
  assert_success
  [ "$output" -ge 1 ]
}

@test "yolo-tester.md escalates to Senior" {
  assert_escalation_target "yolo-tester.md" "Senior"
}

@test "yolo-tester.md NEVER escalates to Lead directly" {
  run grep "NEVER.*Lead" "$AGENTS_DIR/yolo-tester.md"
  assert_success
}

# --- QA Lead escalates to Lead ---

@test "yolo-qa.md has escalation table" {
  run grep -c "Escalation Table" "$AGENTS_DIR/yolo-qa.md"
  assert_success
  [ "$output" -ge 1 ]
}

@test "yolo-qa.md escalates to Lead" {
  assert_escalation_target "yolo-qa.md" "Lead"
}

@test "yolo-qa.md NEVER escalates to Architect directly" {
  run grep "NEVER.*Architect" "$AGENTS_DIR/yolo-qa.md"
  assert_success
}

# --- QA Code escalates to Lead ---

@test "yolo-qa-code.md has escalation table" {
  run grep -c "Escalation Table" "$AGENTS_DIR/yolo-qa-code.md"
  assert_success
  [ "$output" -ge 1 ]
}

@test "yolo-qa-code.md escalates to Lead" {
  assert_escalation_target "yolo-qa-code.md" "Lead"
}

# --- Security escalates to Lead ---

@test "yolo-security.md has escalation table" {
  run grep -c "Escalation Table" "$AGENTS_DIR/yolo-security.md"
  assert_success
  [ "$output" -ge 1 ]
}

@test "yolo-security.md escalates to Lead" {
  assert_escalation_target "yolo-security.md" "Lead"
}

# --- Scout escalates to Lead ---

@test "yolo-scout.md has escalation table" {
  run grep -c "Escalation Table" "$AGENTS_DIR/yolo-scout.md"
  assert_success
  [ "$output" -ge 1 ]
}

@test "yolo-scout.md escalates to Lead" {
  assert_escalation_target "yolo-scout.md" "Lead"
}

# --- Debugger escalates to Lead ---

@test "yolo-debugger.md has escalation table" {
  run grep -c "Escalation Table" "$AGENTS_DIR/yolo-debugger.md"
  assert_success
  [ "$output" -ge 1 ]
}

@test "yolo-debugger.md escalates to Lead" {
  assert_escalation_target "yolo-debugger.md" "Lead"
}

# --- Critic escalates to Lead ---

@test "yolo-critic.md has escalation table" {
  run grep -c "Escalation Table" "$AGENTS_DIR/yolo-critic.md"
  assert_success
  [ "$output" -ge 1 ]
}

@test "yolo-critic.md escalates to Lead" {
  assert_escalation_target "yolo-critic.md" "Lead"
}

# --- company-hierarchy.md has strict escalation section ---

@test "company-hierarchy.md has strict escalation chain" {
  local hierarchy="$PROJECT_ROOT/references/company-hierarchy.md"
  run grep "STRICT" "$hierarchy"
  assert_success
  assert_output --partial "NO LEVEL SKIPPING"
}

@test "company-hierarchy.md documents Dev → Senior chain" {
  local hierarchy="$PROJECT_ROOT/references/company-hierarchy.md"
  run grep "Dev.*Senior" "$hierarchy"
  assert_success
}

@test "company-hierarchy.md documents primary chain" {
  local hierarchy="$PROJECT_ROOT/references/company-hierarchy.md"
  run grep "Dev → Senior → Lead → Architect → User" "$hierarchy"
  assert_success
}
