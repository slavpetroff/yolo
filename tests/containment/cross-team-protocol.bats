#!/usr/bin/env bats
# cross-team-protocol.bats — Verify cross-team handoff rules and protocol enforcement
# Tests: handoff schemas, communication boundaries, workflow order

setup() {
  load '../test_helper/common'
}

# --- Handoff schema documentation ---

@test "handoff-schemas.md has design_handoff schema" {
  run grep "design_handoff" "$PROJECT_ROOT/references/handoff-schemas.md"
  assert_success
}

@test "handoff-schemas.md has api_contract schema" {
  run grep "api_contract" "$PROJECT_ROOT/references/handoff-schemas.md"
  assert_success
}

@test "handoff-schemas.md has department_result schema" {
  run grep "department_result" "$PROJECT_ROOT/references/handoff-schemas.md"
  assert_success
}

@test "handoff-schemas.md has owner_signoff schema" {
  run grep "owner_signoff" "$PROJECT_ROOT/references/handoff-schemas.md"
  assert_success
}

# --- Cross-team protocol content ---

@test "cross-team-protocol.md has execution order" {
  run grep "Execution Order" "$PROJECT_ROOT/references/cross-team-protocol.md"
  assert_success
}

@test "cross-team-protocol.md has communication rules" {
  run grep "Communication Rules" "$PROJECT_ROOT/references/cross-team-protocol.md"
  assert_success
}

@test "cross-team-protocol.md has handoff gates" {
  run grep -i "handoff.*gate" "$PROJECT_ROOT/references/cross-team-protocol.md"
  assert_success
}

# --- UX runs first, then FE + BE parallel ---

@test "cross-team-protocol.md documents UX runs first" {
  run grep "UI/UX.*FIRST" "$PROJECT_ROOT/references/cross-team-protocol.md"
  assert_success
}

@test "cross-team-protocol.md documents FE and BE parallel" {
  run grep -i "parallel" "$PROJECT_ROOT/references/cross-team-protocol.md"
  assert_success
}

# --- Backend NEVER communicates with UI/UX directly ---

@test "cross-team-protocol.md enforces Backend-UX isolation" {
  run grep "Backend.*UI/UX.*isolation" "$PROJECT_ROOT/references/cross-team-protocol.md"
  assert_success
}

# --- Multi-department protocol ---

@test "multi-dept-protocol.md has department dispatch" {
  run grep -i "department.*dispatch" "$PROJECT_ROOT/references/multi-dept-protocol.md"
  assert_success
}

@test "multi-dept-protocol.md has integration QA" {
  run grep -i "integration.*QA" "$PROJECT_ROOT/references/multi-dept-protocol.md"
  assert_success
}

@test "multi-dept-protocol.md has owner sign-off" {
  run grep -i "owner.*sign.off" "$PROJECT_ROOT/references/multi-dept-protocol.md"
  assert_success
}

# --- Artifact format schemas ---

@test "artifact-formats.md has design token schema" {
  run grep "design.token" "$PROJECT_ROOT/references/artifact-formats.md"
  assert_success
}

@test "artifact-formats.md has component spec schema" {
  run grep "component.spec" "$PROJECT_ROOT/references/artifact-formats.md"
  assert_success
}

@test "artifact-formats.md has api contract schema" {
  run grep "api.contract" "$PROJECT_ROOT/references/artifact-formats.md"
  assert_success
}

# --- Agent cross-department awareness ---

@test "FE lead agent references design-handoff" {
  run grep "design.handoff" "$AGENTS_DIR/yolo-fe-lead.md"
  assert_success
}

@test "FE lead agent references api-contracts" {
  run grep "api.contract" "$AGENTS_DIR/yolo-fe-lead.md"
  assert_success
}

@test "UX lead agent references design-handoff" {
  run grep "design.handoff" "$AGENTS_DIR/yolo-ux-lead.md"
  assert_success
}

@test "UX dev agent produces design-tokens" {
  run grep "design-tokens" "$AGENTS_DIR/yolo-ux-dev.md"
  assert_success
}

@test "owner agent references department results" {
  run grep -i "department.*result" "$AGENTS_DIR/yolo-owner.md"
  assert_success
}
