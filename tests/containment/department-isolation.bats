#!/usr/bin/env bats
# department-isolation.bats — Verify department boundary enforcement
# Tests: escalation chains per department, NEVER constraints, cross-dept isolation

setup() {
  load '../test_helper/common'
}

# --- Frontend escalation chain: FE Dev → FE Senior → FE Lead → FE Architect ---

@test "vbw-fe-dev.md escalates to FE Senior" {
  run grep -A 20 "## Escalation Table" "$AGENTS_DIR/vbw-fe-dev.md"
  assert_success
  assert_output --partial "FE Senior"
}

@test "vbw-fe-dev.md NEVER escalates to FE Lead directly" {
  run grep "NEVER.*FE Lead" "$AGENTS_DIR/vbw-fe-dev.md"
  assert_success
}

@test "vbw-fe-senior.md escalates to FE Lead" {
  run grep -A 20 "## Escalation Table" "$AGENTS_DIR/vbw-fe-senior.md"
  assert_success
  assert_output --partial "FE Lead"
}

@test "vbw-fe-senior.md NEVER escalates to FE Architect directly" {
  run grep "NEVER.*FE Architect" "$AGENTS_DIR/vbw-fe-senior.md"
  assert_success
}

@test "vbw-fe-lead.md escalates to FE Architect" {
  run grep -A 20 "## Escalation Table" "$AGENTS_DIR/vbw-fe-lead.md"
  assert_success
  assert_output --partial "FE Architect"
}

@test "vbw-fe-lead.md NEVER escalates to User directly" {
  run grep "NEVER.*User" "$AGENTS_DIR/vbw-fe-lead.md"
  assert_success
}

@test "vbw-fe-tester.md NEVER escalates to FE Lead directly" {
  run grep "NEVER.*FE Lead" "$AGENTS_DIR/vbw-fe-tester.md"
  assert_success
}

# --- UI/UX escalation chain: UX Dev → UX Senior → UX Lead → UX Architect ---

@test "vbw-ux-dev.md escalates to UX Senior" {
  run grep -A 20 "## Escalation Table" "$AGENTS_DIR/vbw-ux-dev.md"
  assert_success
  assert_output --partial "UX Senior"
}

@test "vbw-ux-dev.md NEVER escalates to UX Lead directly" {
  run grep "NEVER.*UX Lead" "$AGENTS_DIR/vbw-ux-dev.md"
  assert_success
}

@test "vbw-ux-senior.md escalates to UX Lead" {
  run grep -A 20 "## Escalation Table" "$AGENTS_DIR/vbw-ux-senior.md"
  assert_success
  assert_output --partial "UX Lead"
}

@test "vbw-ux-lead.md escalates to UX Architect" {
  run grep -A 20 "## Escalation Table" "$AGENTS_DIR/vbw-ux-lead.md"
  assert_success
  assert_output --partial "UX Architect"
}

@test "vbw-ux-lead.md NEVER escalates to User directly" {
  run grep "NEVER.*User" "$AGENTS_DIR/vbw-ux-lead.md"
  assert_success
}

# --- Owner escalation ---

@test "vbw-owner.md escalates to User" {
  run grep -A 20 "## Escalation Table" "$AGENTS_DIR/vbw-owner.md"
  assert_success
  assert_output --partial "User"
}

@test "vbw-owner.md communicates only with Leads" {
  run grep "ONLY with department Leads" "$AGENTS_DIR/vbw-owner.md"
  assert_success
}

# --- Cross-department isolation ---

@test "UI/UX agents never reference backend directly" {
  for agent in ux-dev ux-tester ux-qa ux-qa-code; do
    # Should NOT have "Backend" in escalation table
    run grep -A 10 "## Escalation Table" "$AGENTS_DIR/vbw-${agent}.md"
    refute_output --partial "Backend Lead"
  done
}

@test "cross-team-protocol.md enforces Backend-UX isolation" {
  local protocol="$PROJECT_ROOT/references/cross-team-protocol.md"
  run grep "Backend.*UI/UX.*isolation" "$protocol"
  assert_success
}

@test "cross-team-protocol.md documents communication rules" {
  local protocol="$PROJECT_ROOT/references/cross-team-protocol.md"
  run grep "STRICT" "$protocol"
  assert_success
}

# --- Department protocol files exist ---

@test "backend department protocol exists" {
  [ -f "$PROJECT_ROOT/references/departments/backend.md" ]
}

@test "frontend department protocol exists" {
  [ -f "$PROJECT_ROOT/references/departments/frontend.md" ]
}

@test "uiux department protocol exists" {
  [ -f "$PROJECT_ROOT/references/departments/uiux.md" ]
}

@test "shared department protocol exists" {
  [ -f "$PROJECT_ROOT/references/departments/shared.md" ]
}

@test "cross-team-protocol.md exists" {
  [ -f "$PROJECT_ROOT/references/cross-team-protocol.md" ]
}

@test "multi-dept-protocol.md exists" {
  [ -f "$PROJECT_ROOT/references/multi-dept-protocol.md" ]
}
