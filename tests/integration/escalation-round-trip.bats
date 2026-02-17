#!/usr/bin/env bats
# escalation-round-trip.bats -- Integration test: full escalation round-trip
# Verifies all Phase 5 artifacts exist and are correctly wired

setup() {
  load '../test_helper/common'
}

@test "escalation_resolution schema exists in handoff-schemas.md" {
  run grep -q 'escalation_resolution' "$PROJECT_ROOT/references/handoff-schemas.md"
  assert_success
}

@test "escalation_resolution schema has required fields" {
  local file="$PROJECT_ROOT/references/handoff-schemas.md"
  run grep -A 30 'escalation_resolution' "$file"
  assert_success
  assert_output --partial 'original_escalation'
  assert_output --partial 'decision'
  assert_output --partial 'rationale'
  assert_output --partial 'action_items'
  assert_output --partial 'resolved_by'
}

@test "escalation_timeout_warning schema exists in handoff-schemas.md" {
  run grep -q 'escalation_timeout_warning' "$PROJECT_ROOT/references/handoff-schemas.md"
  assert_success
}

@test "execute-protocol.md has Escalation Handling section" {
  run grep -q 'Escalation Handling' "$PROJECT_ROOT/references/execute-protocol.md"
  assert_success
}

@test "go.md has Escalation from Agents section" {
  run grep -q 'Escalation from Agents' "$PROJECT_ROOT/commands/go.md"
  assert_success
}

@test "yolo-lead.md has Escalation Receipt and Routing section" {
  run grep -q 'Escalation Receipt' "$AGENTS_DIR/yolo-lead.md"
  assert_success
}

@test "yolo-senior.md has Resolution Routing section" {
  run grep -q 'Resolution Routing' "$AGENTS_DIR/yolo-senior.md"
  assert_success
}

@test "yolo-dev.md has Escalation Resolution section" {
  run grep -q 'Escalation Resolution' "$AGENTS_DIR/yolo-dev.md"
  assert_success
}

@test "yolo-owner.md has Resolution Routing section" {
  run grep -q 'Resolution Routing' "$AGENTS_DIR/yolo-owner.md"
  assert_success
}

@test "company-hierarchy.md has Escalation Round-Trip section" {
  run grep -q 'Escalation Round-Trip' "$PROJECT_ROOT/references/company-hierarchy.md"
  assert_success
}

@test "defaults.json has escalation.timeout_seconds" {
  run jq -e '.escalation.timeout_seconds' "$PROJECT_ROOT/config/defaults.json"
  assert_success
  run jq -r '.escalation.timeout_seconds' "$PROJECT_ROOT/config/defaults.json"
  [ "$output" = "300" ]
}

@test "check-escalation-timeout.sh exists and is executable" {
  [ -x "$PROJECT_ROOT/scripts/check-escalation-timeout.sh" ]
}

@test "escalation_resolution schema has direction note" {
  run grep -A 30 'escalation_resolution' "$PROJECT_ROOT/references/handoff-schemas.md"
  assert_success
  run grep -i 'downward' "$PROJECT_ROOT/references/handoff-schemas.md"
  assert_success
}

@test "execute-protocol.md Step 7 references escalations array" {
  run grep -q 'escalations' "$PROJECT_ROOT/references/execute-protocol.md"
  assert_success
}
