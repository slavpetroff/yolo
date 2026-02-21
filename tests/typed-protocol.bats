#!/usr/bin/env bats

# Tests for typed protocol message schemas.
# Validates message-schemas.json structure, role permissions,
# envelope requirements, and payload field definitions.
# The Rust binary embeds validation logic in hook handlers;
# these tests verify the schema definitions are correct.

load test_helper

SCHEMAS="$CONFIG_DIR/schemas/message-schemas.json"

setup() {
  [ -f "$SCHEMAS" ] || skip "message-schemas.json not found"
}

# =============================================================================
# Envelope field validation
# =============================================================================

@test "schema defines all required envelope fields" {
  for field in id type phase task author_role timestamp schema_version payload confidence; do
    jq -e --arg f "$field" '.envelope_fields | index($f) != null' "$SCHEMAS" || {
      echo "Missing envelope field: $field"
      return 1
    }
  done
}

# =============================================================================
# execution_update schema
# =============================================================================

@test "execution_update: allowed_roles includes dev" {
  jq -e '.schemas.execution_update.allowed_roles | index("dev") != null' "$SCHEMAS"
}

@test "execution_update: payload requires plan_id, task_id, status, commit" {
  for field in plan_id task_id status commit; do
    jq -e --arg f "$field" '.schemas.execution_update.payload_required | index($f) != null' "$SCHEMAS" || {
      echo "Missing required payload field: $field"
      return 1
    }
  done
}

@test "execution_update: qa not in allowed_roles" {
  run jq -e '.schemas.execution_update.allowed_roles | index("qa") != null' "$SCHEMAS"
  [ "$status" -ne 0 ]
}

# =============================================================================
# scout_findings schema
# =============================================================================

@test "scout_findings: allowed_roles includes scout" {
  jq -e '.schemas.scout_findings.allowed_roles | index("scout") != null' "$SCHEMAS"
}

@test "scout_findings: payload requires domain and documents" {
  jq -e '.schemas.scout_findings.payload_required | (index("domain") != null and index("documents") != null)' "$SCHEMAS"
}

# =============================================================================
# plan_contract schema
# =============================================================================

@test "plan_contract: allowed_roles includes lead and architect" {
  jq -e '.schemas.plan_contract.allowed_roles | (index("lead") != null and index("architect") != null)' "$SCHEMAS"
}

@test "plan_contract: payload requires plan_id, phase_id, objective, tasks, allowed_paths, must_haves" {
  for field in plan_id phase_id objective tasks allowed_paths must_haves; do
    jq -e --arg f "$field" '.schemas.plan_contract.payload_required | index($f) != null' "$SCHEMAS" || {
      echo "Missing required payload field: $field"
      return 1
    }
  done
}

# =============================================================================
# qa_verdict schema
# =============================================================================

@test "qa_verdict: allowed_roles includes qa" {
  jq -e '.schemas.qa_verdict.allowed_roles | index("qa") != null' "$SCHEMAS"
}

@test "qa_verdict: payload requires tier, result, checks" {
  jq -e '.schemas.qa_verdict.payload_required | (index("tier") != null and index("result") != null and index("checks") != null)' "$SCHEMAS"
}

# =============================================================================
# blocker_report schema
# =============================================================================

@test "blocker_report: allowed_roles includes dev" {
  jq -e '.schemas.blocker_report.allowed_roles | index("dev") != null' "$SCHEMAS"
}

@test "blocker_report: payload requires plan_id, task_id, blocker, needs" {
  for field in plan_id task_id blocker needs; do
    jq -e --arg f "$field" '.schemas.blocker_report.payload_required | index($f) != null' "$SCHEMAS" || {
      echo "Missing required payload field: $field"
      return 1
    }
  done
}

# =============================================================================
# approval_request / approval_response schemas
# =============================================================================

@test "approval_request: allowed_roles includes dev and lead" {
  jq -e '.schemas.approval_request.allowed_roles | (index("dev") != null and index("lead") != null)' "$SCHEMAS"
}

@test "approval_request: payload requires subject, request_type, evidence" {
  jq -e '.schemas.approval_request.payload_required | (index("subject") != null and index("request_type") != null and index("evidence") != null)' "$SCHEMAS"
}

@test "approval_response: allowed_roles includes lead and architect" {
  jq -e '.schemas.approval_response.allowed_roles | (index("lead") != null and index("architect") != null)' "$SCHEMAS"
}

@test "approval_response: payload requires request_id, approved, reason" {
  jq -e '.schemas.approval_response.payload_required | (index("request_id") != null and index("approved") != null and index("reason") != null)' "$SCHEMAS"
}

# =============================================================================
# Role hierarchy: can_send / can_receive
# =============================================================================

@test "role hierarchy: dev can_send execution_update" {
  jq -e '.role_hierarchy.dev.can_send | index("execution_update") != null' "$SCHEMAS"
}

@test "role hierarchy: dev can_receive plan_contract" {
  jq -e '.role_hierarchy.dev.can_receive | index("plan_contract") != null' "$SCHEMAS"
}

@test "role hierarchy: lead can_send plan_contract" {
  jq -e '.role_hierarchy.lead.can_send | index("plan_contract") != null' "$SCHEMAS"
}

@test "role hierarchy: lead can_receive execution_update" {
  jq -e '.role_hierarchy.lead.can_receive | index("execution_update") != null' "$SCHEMAS"
}

@test "role hierarchy: scout can_send scout_findings" {
  jq -e '.role_hierarchy.scout.can_send | index("scout_findings") != null' "$SCHEMAS"
}

@test "role hierarchy: qa can_send qa_verdict" {
  jq -e '.role_hierarchy.qa.can_send | index("qa_verdict") != null' "$SCHEMAS"
}

@test "role hierarchy: architect can_send plan_contract and approval_response" {
  jq -e '.role_hierarchy.architect.can_send | (index("plan_contract") != null and index("approval_response") != null)' "$SCHEMAS"
}

@test "role hierarchy: dev cannot receive scout_findings" {
  run jq -e '.role_hierarchy.dev.can_receive | index("scout_findings") != null' "$SCHEMAS"
  [ "$status" -ne 0 ]
}

# =============================================================================
# Schema completeness: all message types have required fields
# =============================================================================

@test "all schemas have allowed_roles and payload_required" {
  local types
  types=$(jq -r '.schemas | keys[]' "$SCHEMAS")
  for t in $types; do
    jq -e --arg t "$t" '.schemas[$t] | has("allowed_roles") and has("payload_required")' "$SCHEMAS" || {
      echo "Schema $t missing allowed_roles or payload_required"
      return 1
    }
  done
}

@test "schema version is 2.0" {
  jq -e '.schema_version == "2.0"' "$SCHEMAS"
}
