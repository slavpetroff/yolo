#!/usr/bin/env bats

# Tests for discovered issues surfacing across commands and agents
# Issue #98: Pre-existing test failures silently dropped by /yolo:fix, /yolo:debug, /yolo:qa

load test_helper

# =============================================================================
# Dev agent: DEVN-05 Pre-existing deviation code
# =============================================================================

@test "dev agent has DEVN-05 Pre-existing deviation code" {
  grep -q 'DEVN-05' "$PROJECT_ROOT/agents/yolo-dev.md"
}

@test "dev agent DEVN-05 action is note and do not fix" {
  grep 'DEVN-05' "$PROJECT_ROOT/agents/yolo-dev.md" | grep -qi 'do not fix'
}

@test "dev agent DEVN-05 never escalates" {
  grep 'DEVN-05' "$PROJECT_ROOT/agents/yolo-dev.md" | grep -qi 'Never'
}

@test "dev agent deviation table has all 5 DEVN codes" {
  for code in DEVN-01 DEVN-02 DEVN-03 DEVN-04 DEVN-05; do
    grep -q "$code" "$PROJECT_ROOT/agents/yolo-dev.md" || { echo "Missing $code"; return 1; }
  done
}

@test "dev agent deviation table includes DEVN-04 Architectural" {
  grep -q 'DEVN-04.*Architectural' "$PROJECT_ROOT/agents/yolo-dev.md"
}

# =============================================================================
# Fix command: discovered issues output
# =============================================================================

@test "fix command prompt instructs Dev to report pre-existing failures" {
  grep -q 'Pre-existing Issues' "$PROJECT_ROOT/commands/fix.md"
}

@test "fix command prompt mentions pre-existing failures in spawn block" {
  # The spawn prompt template must tell Dev about pre-existing reporting
  sed -n '/^3\./,/^4\./p' "$PROJECT_ROOT/commands/fix.md" | grep -q 'pre-existing'
}

@test "fix command has discovered issues output section" {
  grep -q 'Discovered Issues' "$PROJECT_ROOT/commands/fix.md"
}

@test "fix command discovered issues uses warning bullet format" {
  grep -q '⚠' "$PROJECT_ROOT/commands/fix.md"
}

@test "fix command discovered issues suggests /yolo:todo" {
  grep -q '/yolo:todo' "$PROJECT_ROOT/commands/fix.md"
}

@test "fix command discovered issues is display-only" {
  grep -q 'display-only' "$PROJECT_ROOT/commands/fix.md"
}

# =============================================================================
# Debug command: discovered issues output
# =============================================================================

@test "debug command Path B prompt instructs reporting pre-existing failures" {
  # Path B spawn prompt must mention pre-existing
  sed -n '/Path B/,/^[0-9]\./p' "$PROJECT_ROOT/commands/debug.md" | grep -q 'Pre-existing Issues'
}

@test "debug command Path A prompt instructs reporting pre-existing failures" {
  # Path A task creation must mention pre-existing
  sed -n '/Path A/,/Path B/p' "$PROJECT_ROOT/commands/debug.md" | grep -q 'Pre-existing Issues'
}

@test "debug command has discovered issues output section" {
  grep -q 'Discovered Issues' "$PROJECT_ROOT/commands/debug.md"
}

@test "debug command discovered issues uses warning bullet format" {
  grep -q '⚠' "$PROJECT_ROOT/commands/debug.md"
}

@test "debug command discovered issues suggests /yolo:todo" {
  grep -q '/yolo:todo' "$PROJECT_ROOT/commands/debug.md"
}

@test "debug command discovered issues is display-only" {
  grep -q 'display-only' "$PROJECT_ROOT/commands/debug.md"
}

@test "debug command Path A has de-duplication instruction" {
  sed -n '/Path A/,/Path B/p' "$PROJECT_ROOT/commands/debug.md" | grep -qi 'de-duplicate'
}

@test "debug command Path A dedup key includes file" {
  sed -n '/Path A/,/Path B/p' "$PROJECT_ROOT/commands/debug.md" | grep -qi 'test name and file'
}

# =============================================================================
# Debugger agent: pre-existing failure handling
# =============================================================================

@test "debugger agent has pre-existing issues section" {
  grep -q 'Pre-existing Issues' "$PROJECT_ROOT/agents/yolo-debugger.md"
}

@test "debugger agent classifies unrelated failures as pre-existing" {
  sed -n '/Pre-existing Issues/,/^##/p' "$PROJECT_ROOT/agents/yolo-debugger.md" | grep -qi 'unrelated.*failures\|failures.*unrelated'
}

@test "debugger agent does not fix pre-existing issues" {
  sed -n '/Pre-existing Issues/,/^##/p' "$PROJECT_ROOT/agents/yolo-debugger.md" | grep -qi 'do not fix'
}

@test "debugger agent mentions pre_existing_issues in debugger_report" {
  grep -q 'pre-existing issues' "$PROJECT_ROOT/agents/yolo-debugger.md"
}

@test "debugger agent references debugger_report schema" {
  grep -q 'debugger_report' "$PROJECT_ROOT/agents/yolo-debugger.md"
}

@test "debugger agent Step 7 output includes pre-existing issues" {
  # Stage 7: Document mentions pre-existing issues
  sed -n '/### Stage 7/,/^##/p' "$PROJECT_ROOT/agents/yolo-debugger.md" | grep -qi 'pre-existing'
}

# =============================================================================
# Handoff schema: debugger_report is a proper schema type
# =============================================================================

@test "handoff schema has dedicated debugger_report section" {
  grep -q '## `debugger_report`' "$PROJECT_ROOT/references/handoff-schemas.md"
}

@test "handoff schema debugger_report uses correct type in JSON" {
  sed -n '/## .debugger_report/,/^## /p' "$PROJECT_ROOT/references/handoff-schemas.md" | grep -q '"type": "debugger_report"'
}

@test "handoff schema blocker_report section does not mention debugger" {
  # Extract blocker_report section up to but not including the debugger_report heading
  local section
  section=$(sed -n '/## .blocker_report/,/^## .debugger_report/{ /^## .debugger_report/d; p; }' "$PROJECT_ROOT/references/handoff-schemas.md")
  run grep -qi 'debugger' <<< "$section"
  [ "$status" -ne 0 ]
}

# =============================================================================
# Debugger report schema: pre_existing_issues field
# =============================================================================

@test "handoff schema documents pre_existing_issues field" {
  grep -q 'pre_existing_issues' "$PROJECT_ROOT/references/handoff-schemas.md"
}

@test "handoff schema pre_existing_issues has test/file/error structure" {
  grep -A2 'pre_existing_issues' "$PROJECT_ROOT/references/handoff-schemas.md" | grep -q '"test"'
}

@test "json schema qa_verdict payload_optional includes pre_existing_issues" {
  jq -r '.schemas.qa_verdict.payload_optional[]' "$PROJECT_ROOT/config/schemas/message-schemas.json" | grep -q 'pre_existing_issues'
}

@test "json schema blocker_report payload_optional includes pre_existing_issues" {
  jq -r '.schemas.blocker_report.payload_optional[]' "$PROJECT_ROOT/config/schemas/message-schemas.json" | grep -q 'pre_existing_issues'
}

@test "json schema execution_update payload_optional includes pre_existing_issues" {
  jq -r '.schemas.execution_update.payload_optional[]' "$PROJECT_ROOT/config/schemas/message-schemas.json" | grep -q 'pre_existing_issues'
}

@test "handoff schema execution_update example includes pre_existing_issues" {
  sed -n '/execution_update/,/^##/p' "$PROJECT_ROOT/references/handoff-schemas.md" | grep -q 'pre_existing_issues'
}

# =============================================================================
# Dev agent: DEVN-05 is in deviation table with correct semantics
# =============================================================================

@test "dev agent DEVN-05 is classified as Pre-existing" {
  grep 'DEVN-05' "$PROJECT_ROOT/agents/yolo-dev.md" | grep -qi 'Pre-existing'
}

@test "dev agent deviation table has DEVN-01 Minor" {
  grep -q 'DEVN-01.*Minor' "$PROJECT_ROOT/agents/yolo-dev.md"
}

@test "dev agent deviation table has DEVN-02 Critical" {
  grep -q 'DEVN-02.*Critical' "$PROJECT_ROOT/agents/yolo-dev.md"
}

@test "dev agent deviation table has DEVN-03 Blocking" {
  grep -q 'DEVN-03.*Blocking' "$PROJECT_ROOT/agents/yolo-dev.md"
}

# =============================================================================
# Lead agent: planning and orchestration scope
# =============================================================================

@test "lead agent has deviation handling section" {
  grep -q 'Deviation Handling' "$PROJECT_ROOT/agents/yolo-lead.md"
}

@test "lead agent has planning protocol section" {
  grep -q 'Planning Protocol' "$PROJECT_ROOT/agents/yolo-lead.md"
}

@test "lead agent has wave optimization stage" {
  grep -q 'Wave Optimization' "$PROJECT_ROOT/agents/yolo-lead.md"
}

@test "lead agent has shutdown handling section" {
  grep -q 'Shutdown Handling' "$PROJECT_ROOT/agents/yolo-lead.md"
}

@test "lead agent has circuit breaker section" {
  grep -q 'Circuit Breaker' "$PROJECT_ROOT/agents/yolo-lead.md"
}

@test "debug command Path A dedup specifies merge strategy" {
  sed -n '/Path A/,/Path B/p' "$PROJECT_ROOT/commands/debug.md" | grep -qi 'first error message'
}

@test "execute-protocol discovered issues specifies merge strategy" {
  sed -n '/Discovered Issues/,/display-only/p' "$PROJECT_ROOT/skills/execute-protocol/SKILL.md" | grep -qi 'first.*error.*message'
}

@test "execute-protocol discovered issues caps list size" {
  sed -n '/Discovered Issues/,/display-only/p' "$PROJECT_ROOT/skills/execute-protocol/SKILL.md" | grep -qi 'cap.*20'
}

@test "execute-protocol discovered issues specifies bullet display format" {
  sed -n '/Discovered Issues/,/display-only/p' "$PROJECT_ROOT/skills/execute-protocol/SKILL.md" | grep -q 'testName.*path.*error'
}

# =============================================================================
# Debug command: schema naming consistency
# =============================================================================

@test "debug command Path A uses debugger_report schema" {
  sed -n '/Path A/,/Path B/p' "$PROJECT_ROOT/commands/debug.md" | grep -q 'debugger_report'
}

@test "debug command Path A does not reference blocker_report for debugger" {
  ! sed -n '/Path A/,/Path B/p' "$PROJECT_ROOT/commands/debug.md" | grep -q 'blocker_report'
}

@test "json schema has dedicated debugger_report type" {
  jq -e '.schemas.debugger_report' "$PROJECT_ROOT/config/schemas/message-schemas.json" > /dev/null
}

@test "json schema debugger_report requires hypothesis and evidence fields" {
  jq -r '.schemas.debugger_report.payload_required[]' "$PROJECT_ROOT/config/schemas/message-schemas.json" | grep -q 'hypothesis'
  jq -r '.schemas.debugger_report.payload_required[]' "$PROJECT_ROOT/config/schemas/message-schemas.json" | grep -q 'evidence_for'
}

@test "json schema debugger_report payload_optional includes pre_existing_issues" {
  jq -r '.schemas.debugger_report.payload_optional[]' "$PROJECT_ROOT/config/schemas/message-schemas.json" | grep -q 'pre_existing_issues'
}

@test "json schema blocker_report does not list debugger as allowed role" {
  ! jq -r '.schemas.blocker_report.allowed_roles[]' "$PROJECT_ROOT/config/schemas/message-schemas.json" | grep -q 'debugger'
}

@test "json schema debugger can send debugger_report" {
  jq -r '.role_hierarchy.debugger.can_send[]' "$PROJECT_ROOT/config/schemas/message-schemas.json" | grep -q 'debugger_report'
}

@test "json schema lead can receive debugger_report" {
  jq -r '.role_hierarchy.lead.can_receive[]' "$PROJECT_ROOT/config/schemas/message-schemas.json" | grep -q 'debugger_report'
}

# =============================================================================
# VERIFICATION.md format: pre-existing issues section
# =============================================================================

@test "verification template has Pre-existing Issues section" {
  grep -q 'Pre-existing Issues' "$PROJECT_ROOT/templates/VERIFICATION.md"
}

@test "verification template Pre-existing Issues has Test/File/Error columns" {
  sed -n '/Pre-existing Issues/,/^##/p' "$PROJECT_ROOT/templates/VERIFICATION.md" | grep -q 'Test.*File.*Error'
}

# =============================================================================
# Reviewer agent: scope and permissions
# =============================================================================

@test "reviewer agent has adversarial analysis scope" {
  grep -qi 'adversarial' "$PROJECT_ROOT/agents/yolo-reviewer.md"
}

@test "reviewer agent is read-only" {
  grep -q 'Review only' "$PROJECT_ROOT/agents/yolo-reviewer.md"
}

@test "reviewer agent reviews architecture" {
  grep -q 'architecture\|architectural' "$PROJECT_ROOT/agents/yolo-reviewer.md"
}

# =============================================================================
# Dev agent: Circuit Breaker schema naming
# =============================================================================

@test "dev agent Circuit Breaker section exists" {
  grep -q 'Circuit Breaker' "$PROJECT_ROOT/agents/yolo-dev.md"
}

@test "dev agent Circuit Breaker does not reference non-existent dev_blocker schema" {
  ! sed -n '/Circuit Breaker/,/$/p' "$PROJECT_ROOT/agents/yolo-dev.md" | grep -q 'dev_blocker'
}

@test "dev agent Circuit Breaker mentions blocker reporting" {
  # Circuit Breaker must instruct agent to report the blocker
  sed -n '/## Circuit Breaker/,/^## /p' "$PROJECT_ROOT/agents/yolo-dev.md" | grep -qi 'report.*blocker\|blocker.*report'
}

# =============================================================================
# Execute-protocol: de-duplication for Discovered Issues
# =============================================================================

@test "execute-protocol discovered issues has de-duplication instruction" {
  sed -n '/Discovered Issues/,/display-only/p' "$PROJECT_ROOT/skills/execute-protocol/SKILL.md" | grep -qi 'de-duplicate'
}

# =============================================================================
# Verify command: discovered issues scoped to user-reported
# =============================================================================

@test "verify command discovered issues scoped to user-reported issues" {
  grep -A2 'Discovered Issues' "$PROJECT_ROOT/commands/verify.md" | grep -qi 'user.*reported'
}

# =============================================================================
# Verify command: discovered issues output
# =============================================================================

@test "verify command has discovered issues output section" {
  grep -q 'Discovered Issues' "$PROJECT_ROOT/commands/verify.md"
}

@test "verify command discovered issues uses warning bullet format" {
  grep -q '⚠' "$PROJECT_ROOT/commands/verify.md"
}

@test "verify command discovered issues suggests /yolo:todo" {
  grep -q '/yolo:todo' "$PROJECT_ROOT/commands/verify.md"
}

@test "verify command discovered issues is display-only" {
  grep -q 'display-only' "$PROJECT_ROOT/commands/verify.md"
}

# =============================================================================
# Consistency: all discovered issues blocks use the same format
# =============================================================================

@test "execute-protocol still has discovered issues section" {
  grep -q 'Discovered Issues' "$PROJECT_ROOT/skills/execute-protocol/SKILL.md"
}

@test "all discovered issues sections use display-only constraint" {
  local failed=""
  for file in commands/fix.md commands/debug.md commands/verify.md skills/execute-protocol/SKILL.md; do
    if grep -q 'Discovered Issues' "$PROJECT_ROOT/$file"; then
      if ! grep -q 'display-only' "$PROJECT_ROOT/$file"; then
        failed="${failed} ${file}"
      fi
    fi
  done
  [ -z "$failed" ] || { echo "Missing display-only in:$failed"; return 1; }
}

@test "all discovered issues sections suggest /yolo:todo" {
  local failed=""
  for file in commands/fix.md commands/debug.md commands/verify.md skills/execute-protocol/SKILL.md; do
    if grep -q 'Discovered Issues' "$PROJECT_ROOT/$file"; then
      if ! grep -q '/yolo:todo' "$PROJECT_ROOT/$file"; then
        failed="${failed} ${file}"
      fi
    fi
  done
  [ -z "$failed" ] || { echo "Missing /yolo:todo in:$failed"; return 1; }
}

# =============================================================================
# Blocker report: pre_existing_issues documented in reference
# =============================================================================

@test "handoff schema blocker_report example includes pre_existing_issues" {
  sed -n '/## .blocker_report/,/^## .debugger_report/p' "$PROJECT_ROOT/references/handoff-schemas.md" | grep -q 'pre_existing_issues'
}

# =============================================================================
# Bullet format consistency across entry points
# =============================================================================

@test "all discovered issues sections specify testName format" {
  local failed=""
  for file in commands/fix.md commands/debug.md commands/verify.md skills/execute-protocol/SKILL.md; do
    if grep -q 'Discovered Issues' "$PROJECT_ROOT/$file"; then
      if ! grep -q 'testName.*path/to/file.*error' "$PROJECT_ROOT/$file"; then
        failed="${failed} ${file}"
      fi
    fi
  done
  [ -z "$failed" ] || { echo "Missing testName format in:$failed"; return 1; }
}

# =============================================================================
# Display-only STOP constraint
# =============================================================================

@test "all discovered issues sections include STOP after display" {
  local failed=""
  for file in commands/fix.md commands/debug.md commands/verify.md; do
    if grep -q 'Discovered Issues' "$PROJECT_ROOT/$file"; then
      if ! grep -qi 'STOP.*Do not take further action' "$PROJECT_ROOT/$file"; then
        failed="${failed} ${file}"
      fi
    fi
  done
  [ -z "$failed" ] || { echo "Missing STOP constraint in:$failed"; return 1; }
}

# =============================================================================
# Debugger standalone: structured pre-existing format
# =============================================================================

@test "debugger agent Step 7 specifies structured pre-existing format" {
  # Step 7 "Document" mentions pre-existing issues in the debugger report
  sed -n '/### Stage 7/,/^##/p' "$PROJECT_ROOT/agents/yolo-debugger.md" | grep -qi 'pre-existing'
}

# =============================================================================
# QA round 2: consistency fixes
# =============================================================================

@test "execute-protocol discovered issues includes STOP after display" {
  sed -n '/Discovered Issues/,/suggest-next/p' "$PROJECT_ROOT/skills/execute-protocol/SKILL.md" | grep -qi 'STOP.*Do not take further action'
}

@test "all discovered issues sections have de-duplication instruction" {
  local failed=""
  for file in commands/fix.md commands/debug.md commands/verify.md skills/execute-protocol/SKILL.md; do
    if grep -q 'Discovered Issues' "$PROJECT_ROOT/$file"; then
      if ! grep -qi 'de-duplicate\|De-duplicate' "$PROJECT_ROOT/$file"; then
        failed="${failed} ${file}"
      fi
    fi
  done
  [ -z "$failed" ] || { echo "Missing de-duplication in:$failed"; return 1; }
}

@test "all discovered issues sections have cap at 20" {
  local failed=""
  for file in commands/fix.md commands/debug.md commands/verify.md skills/execute-protocol/SKILL.md; do
    if grep -q 'Discovered Issues' "$PROJECT_ROOT/$file"; then
      if ! grep -qi 'cap.*20\|Cap.*20' "$PROJECT_ROOT/$file"; then
        failed="${failed} ${file}"
      fi
    fi
  done
  [ -z "$failed" ] || { echo "Missing cap at 20 in:$failed"; return 1; }
}

@test "verify command has best-effort extraction guidance" {
  grep -qi 'best-effort' "$PROJECT_ROOT/commands/verify.md"
}

@test "verify command handles unknown test name or file" {
  grep -qi 'unknown' "$PROJECT_ROOT/commands/verify.md"
}

@test "dev agent DEVN-05 Pre-existing escalation is Never" {
  # DEVN-05 row must specify Never for escalation
  grep 'DEVN-05' "$PROJECT_ROOT/agents/yolo-dev.md" | grep -q 'Never'
}

@test "dev agent has execution protocol with stages" {
  grep -q 'Stage 1.*Load Task' "$PROJECT_ROOT/agents/yolo-dev.md"
  grep -q 'Stage 2.*Acquire Locks' "$PROJECT_ROOT/agents/yolo-dev.md"
  grep -q 'Stage 3.*Execute' "$PROJECT_ROOT/agents/yolo-dev.md"
  grep -q 'Stage 4.*Atomic Commit' "$PROJECT_ROOT/agents/yolo-dev.md"
}
