#!/usr/bin/env bats
# teammate-mock.bats -- Integration tests validating cross-file pattern consistency
# Verifies that agent Teammate API sections, handoff-schemas.md, cross-team-protocol.md,
# and teammate-api-patterns.md are all mutually consistent.

setup() {
  load '../test_helper/common'
  # Uses $PROJECT_ROOT, $AGENTS_DIR from common.bash
  REFS_DIR="$PROJECT_ROOT/references"
  SCHEMAS="$REFS_DIR/handoff-schemas.md"
  CROSS_TEAM="$REFS_DIR/cross-team-protocol.md"
  PATTERNS="$REFS_DIR/teammate-api-patterns.md"
}

# --- Group 1: Schema references match handoff-schemas.md ---

@test "all SendMessage schema types referenced in agents exist in handoff-schemas.md" {
  # Known schema types used across agent Teammate API sections
  local TYPES=(
    dev_progress dev_blocker test_plan_result architecture_design
    senior_spec code_review_result code_review_changes
    qa_result qa_code_result security_audit escalation
  )

  for type in "${TYPES[@]}"; do
    run grep -c "$type" "$SCHEMAS"
    [[ $status -eq 0 ]] || fail "Schema type '$type' not found in handoff-schemas.md"
    [[ "$output" -ge 1 ]] || fail "Zero matches for schema type '$type' in handoff-schemas.md"
  done
}

@test "handoff-schemas.md test_plan_result header says Tester -> Senior (not Lead)" {
  run grep 'test_plan_result' "$SCHEMAS"
  assert_success
  assert_output --partial 'Tester -> Senior'
  # Negative: must NOT say Tester -> Lead
  run grep 'test_plan_result.*Tester -> Lead' "$SCHEMAS"
  assert_failure
}

# --- Group 2: Escalation targets match hierarchy ---

@test "tester agents SendMessage target is Senior (all 3 depts)" {
  for agent in yolo-tester.md yolo-fe-tester.md yolo-ux-tester.md; do
    run grep 'Reports to:' "$AGENTS_DIR/$agent"
    assert_success
    assert_output --partial 'Senior'
  done
}

@test "dev agents SendMessage target is Senior (all 3 depts)" {
  for agent in yolo-dev.md yolo-fe-dev.md yolo-ux-dev.md; do
    run grep 'Reports to:' "$AGENTS_DIR/$agent"
    assert_success
    assert_output --partial 'Senior'
  done
}

@test "qa and qa-code agents SendMessage target is Lead (all 3 depts)" {
  for agent in yolo-qa.md yolo-fe-qa.md yolo-ux-qa.md yolo-qa-code.md yolo-fe-qa-code.md yolo-ux-qa-code.md; do
    run grep 'Reports to:' "$AGENTS_DIR/$agent"
    assert_success
    assert_output --partial 'Lead'
  done
}

@test "security agent SendMessage target is Lead" {
  run grep 'Reports to:' "$AGENTS_DIR/yolo-security.md"
  assert_success
  assert_output --partial 'Lead'
}

# --- Group 3: Cross-team-protocol transport table consistency ---

@test "cross-team-protocol documents SendMessage for intra-department in teammate mode" {
  run grep 'SendMessage within team' "$CROSS_TEAM"
  assert_success
}

@test "cross-team-protocol documents file-based for cross-department in teammate mode" {
  run grep -c 'File-based.*UNCHANGED' "$CROSS_TEAM"
  assert_success
  # At least 2 entries: Lead->Lead and Lead->Owner
  [ "$output" -ge 2 ]
}

# --- Group 4: teammate-api-patterns.md completeness ---

@test "teammate-api-patterns.md documents Task-Only Agents section" {
  run grep 'Task-Only Agents' "$PATTERNS"
  assert_success
  # Verify all 3 excluded agents mentioned
  for agent_name in critic scout debugger; do
    run grep "$agent_name" "$PATTERNS"
    [[ $status -eq 0 ]] || fail "Missing '$agent_name' in Task-Only Agents section of teammate-api-patterns.md"
  done
}

@test "teammate-api-patterns.md documents on-demand registration with step numbers" {
  # Verify step-to-role mapping documented in the registration table
  # Table format uses | N | where N is the step number
  run grep '| 5 ' "$PATTERNS"
  assert_success
  run grep '| 8 ' "$PATTERNS"
  assert_success
  run grep '| 9 ' "$PATTERNS"
  assert_success
}
