#!/usr/bin/env bats

# Tests for shutdown_request/shutdown_response protocol
# Covers: agent handler presence, handoff-schemas consistency,
#         message-schemas.json machine-readable definitions, and
#         schema-level validation of shutdown messages.

load test_helper

SCHEMAS="$CONFIG_DIR/schemas/message-schemas.json"

# =============================================================================
# Agent definitions: agents with Shutdown Handling section
# After agent consolidation: qa/scout removed (merged into reviewer).
# dev and reviewer have no Shutdown Handling. lead, debugger, docs, architect do.
# =============================================================================

@test "yolo-lead has Shutdown Handling section" {
  grep -q '^## Shutdown Handling$' "$PROJECT_ROOT/agents/yolo-lead.md"
}

@test "yolo-debugger has Shutdown Handling section" {
  grep -q '^## Shutdown Handling$' "$PROJECT_ROOT/agents/yolo-debugger.md"
}

@test "yolo-docs has Shutdown Handling section" {
  grep -q '^## Shutdown Handling$' "$PROJECT_ROOT/agents/yolo-docs.md"
}

@test "yolo-architect has Shutdown Handling section" {
  grep -q '^## Shutdown Handling$' "$PROJECT_ROOT/agents/yolo-architect.md"
}

@test "all current agent files exist" {
  [ -f "$PROJECT_ROOT/agents/yolo-dev.md" ]
  [ -f "$PROJECT_ROOT/agents/yolo-reviewer.md" ]
  [ -f "$PROJECT_ROOT/agents/yolo-lead.md" ]
  [ -f "$PROJECT_ROOT/agents/yolo-debugger.md" ]
  [ -f "$PROJECT_ROOT/agents/yolo-docs.md" ]
  [ -f "$PROJECT_ROOT/agents/yolo-architect.md" ]
}

# =============================================================================
# Agent handlers reference both message types
# =============================================================================

@test "agents with Shutdown Handling reference shutdown_request" {
  for agent in lead debugger docs architect; do
    grep -q 'shutdown_request' "$PROJECT_ROOT/agents/yolo-${agent}.md" || {
      echo "yolo-${agent}.md missing shutdown_request reference"
      return 1
    }
  done
}

@test "agents with Shutdown Handling reference shutdown_response" {
  for agent in lead debugger docs architect; do
    grep -q 'shutdown_response' "$PROJECT_ROOT/agents/yolo-${agent}.md" || {
      echo "yolo-${agent}.md missing shutdown_response reference"
      return 1
    }
  done
}

# =============================================================================
# Agent handlers instruct STOP behavior
# =============================================================================

@test "execution agents with Shutdown Handling instruct to STOP" {
  for agent in lead debugger docs; do
    sed -n '/^## Shutdown Handling$/,/^## /p' "$PROJECT_ROOT/agents/yolo-${agent}.md" | grep -qi 'STOP' || {
      echo "yolo-${agent}.md Shutdown Handling section missing STOP instruction"
      return 1
    }
  done
}

@test "debugger handler includes finish instruction" {
  sed -n '/^## Shutdown Handling$/,/^## /p' "$PROJECT_ROOT/agents/yolo-debugger.md" | grep -qi 'finish'
}

@test "architect handler documents planning-only exemption" {
  sed -n '/^## Shutdown Handling$/,/^## /p' "$PROJECT_ROOT/agents/yolo-architect.md" | grep -qi 'planning-only'
}

# =============================================================================
# Shutdown Handling is positioned between Effort and Circuit Breaker
# =============================================================================

@test "shutdown handling before Circuit Breaker in all agents with both sections" {
  for agent in lead debugger docs architect; do
    local file="$PROJECT_ROOT/agents/yolo-${agent}.md"
    local shutdown_line breaker_line
    shutdown_line=$(grep -n '^## Shutdown Handling' "$file" | head -1 | cut -d: -f1)
    breaker_line=$(grep -n '^## Circuit Breaker' "$file" | head -1 | cut -d: -f1)
    [ -n "$shutdown_line" ] && [ -n "$breaker_line" ] || {
      echo "yolo-${agent}.md missing Shutdown or Circuit sections"
      return 1
    }
    [ "$shutdown_line" -lt "$breaker_line" ] || {
      echo "yolo-${agent}.md: Shutdown ($shutdown_line) not before Circuit Breaker ($breaker_line)"
      return 1
    }
  done
}

@test "docs: Effort before Shutdown Handling before Circuit Breaker" {
  local file="$PROJECT_ROOT/agents/yolo-docs.md"
  local effort_line shutdown_line breaker_line
  effort_line=$(grep -n '^## Effort' "$file" | head -1 | cut -d: -f1)
  shutdown_line=$(grep -n '^## Shutdown Handling' "$file" | head -1 | cut -d: -f1)
  breaker_line=$(grep -n '^## Circuit Breaker' "$file" | head -1 | cut -d: -f1)
  [ -n "$effort_line" ] && [ -n "$shutdown_line" ] && [ -n "$breaker_line" ]
  [ "$effort_line" -lt "$shutdown_line" ]
  [ "$shutdown_line" -lt "$breaker_line" ]
}

# =============================================================================
# Handoff schemas: prose documentation consistency
# =============================================================================

@test "handoff-schemas.md envelope type list includes shutdown_request" {
  grep -q 'shutdown_request' "$PROJECT_ROOT/references/handoff-schemas.md"
}

@test "handoff-schemas.md envelope type list includes shutdown_response" {
  grep -q 'shutdown_response' "$PROJECT_ROOT/references/handoff-schemas.md"
}

@test "handoff-schemas.md has shutdown_request section" {
  grep -q '## `shutdown_request`' "$PROJECT_ROOT/references/handoff-schemas.md"
}

@test "handoff-schemas.md has shutdown_response section" {
  grep -q '## `shutdown_response`' "$PROJECT_ROOT/references/handoff-schemas.md"
}

@test "handoff-schemas.md role matrix lists shutdown_request sender as lead" {
  grep 'shutdown_request' "$PROJECT_ROOT/references/handoff-schemas.md" | grep -q 'lead'
}

@test "handoff-schemas.md role matrix lists current roles as shutdown_request receivers" {
  local row
  row=$(grep 'shutdown_request.*|.*|' "$PROJECT_ROOT/references/handoff-schemas.md" | head -1)
  for role in dev lead debugger docs; do
    echo "$row" | grep -q "$role" || {
      echo "shutdown_request receiver row missing $role"
      return 1
    }
  done
}

@test "handoff-schemas.md shutdown_request payload has reason field" {
  # The JSON example should contain "reason"
  sed -n '/## `shutdown_request`/,/## `/p' "$PROJECT_ROOT/references/handoff-schemas.md" | grep -q '"reason"'
}

@test "handoff-schemas.md shutdown_response payload has request_id and approved fields" {
  local section
  section=$(sed -n '/## `shutdown_response`/,/## /p' "$PROJECT_ROOT/references/handoff-schemas.md")
  echo "$section" | grep -q '"request_id"'
  echo "$section" | grep -q '"approved"'
}

@test "handoff-schemas.md shutdown_response payload has final_status field" {
  sed -n '/## `shutdown_response`/,/## /p' "$PROJECT_ROOT/references/handoff-schemas.md" | grep -q '"final_status"'
}

# =============================================================================
# Machine-readable schema: message-schemas.json includes shutdown types
# =============================================================================

@test "message-schemas.json has shutdown_request schema" {
  jq -e '.schemas.shutdown_request' "$SCHEMAS"
}

@test "message-schemas.json has shutdown_response schema" {
  jq -e '.schemas.shutdown_response' "$SCHEMAS"
}

@test "message-schemas.json shutdown_request allowed_roles includes lead" {
  jq -e '.schemas.shutdown_request.allowed_roles | index("lead") != null' "$SCHEMAS"
}

@test "message-schemas.json shutdown_response allowed_roles includes all 6 teammate roles" {
  for role in dev qa scout lead debugger docs; do
    jq -e --arg r "$role" '.schemas.shutdown_response.allowed_roles | index($r) != null' \
      "$SCHEMAS" || {
      echo "shutdown_response missing allowed role: $role"
      return 1
    }
  done
}

@test "message-schemas.json shutdown_request payload requires reason and team_name" {
  jq -e '.schemas.shutdown_request.payload_required | (index("reason") != null and index("team_name") != null)' \
    "$SCHEMAS"
}

@test "message-schemas.json shutdown_response payload requires request_id, approved, final_status" {
  jq -e '.schemas.shutdown_response.payload_required | (index("request_id") != null and index("approved") != null and index("final_status") != null)' \
    "$SCHEMAS"
}

# =============================================================================
# Role hierarchy: shutdown messages in can_send / can_receive
# =============================================================================

@test "message-schemas.json lead can_send includes shutdown_request" {
  jq -e '.role_hierarchy.lead.can_send | index("shutdown_request") != null' \
    "$SCHEMAS"
}

@test "message-schemas.json all teammate roles can_receive shutdown_request" {
  for role in dev qa scout debugger docs; do
    jq -e --arg r "$role" '.role_hierarchy[$r].can_receive | index("shutdown_request") != null' \
      "$SCHEMAS" || {
      echo "$role missing shutdown_request in can_receive"
      return 1
    }
  done
}

@test "message-schemas.json all teammate roles can_send shutdown_response" {
  for role in dev qa scout debugger docs lead; do
    jq -e --arg r "$role" '.role_hierarchy[$r].can_send | index("shutdown_response") != null' \
      "$SCHEMAS" || {
      echo "$role missing shutdown_response in can_send"
      return 1
    }
  done
}

@test "message-schemas.json lead can_receive includes shutdown_response" {
  jq -e '.role_hierarchy.lead.can_receive | index("shutdown_response") != null' \
    "$SCHEMAS"
}

# =============================================================================
# Schema-level validation: shutdown_request role authorization
# =============================================================================

@test "shutdown_request: lead is authorized sender (in allowed_roles)" {
  jq -e '.schemas.shutdown_request.allowed_roles | index("lead") != null' "$SCHEMAS"
}

@test "shutdown_request: dev is NOT authorized sender" {
  run jq -e '.schemas.shutdown_request.allowed_roles | index("dev") != null' "$SCHEMAS"
  [ "$status" -ne 0 ]
}

@test "shutdown_request: architect is NOT authorized sender" {
  run jq -e '.schemas.shutdown_request.allowed_roles | index("architect") != null' "$SCHEMAS"
  [ "$status" -ne 0 ]
}

# =============================================================================
# Schema-level validation: shutdown_response role authorization
# =============================================================================

@test "shutdown_response: dev is authorized sender" {
  jq -e '.schemas.shutdown_response.allowed_roles | index("dev") != null' "$SCHEMAS"
}

@test "shutdown_response: qa is authorized sender" {
  jq -e '.schemas.shutdown_response.allowed_roles | index("qa") != null' "$SCHEMAS"
}

@test "shutdown_response: scout is authorized sender" {
  jq -e '.schemas.shutdown_response.allowed_roles | index("scout") != null' "$SCHEMAS"
}

@test "shutdown_response: debugger is authorized sender" {
  jq -e '.schemas.shutdown_response.allowed_roles | index("debugger") != null' "$SCHEMAS"
}

@test "shutdown_response: lead is authorized sender" {
  jq -e '.schemas.shutdown_response.allowed_roles | index("lead") != null' "$SCHEMAS"
}

@test "shutdown_response: docs is authorized sender" {
  jq -e '.schemas.shutdown_response.allowed_roles | index("docs") != null' "$SCHEMAS"
}

@test "shutdown_response: architect is NOT authorized sender" {
  run jq -e '.schemas.shutdown_response.allowed_roles | index("architect") != null' "$SCHEMAS"
  [ "$status" -ne 0 ]
}

# =============================================================================
# Schema-level: shutdown_request target routing via can_receive
# =============================================================================

@test "shutdown_request: dev can_receive includes shutdown_request" {
  jq -e '.role_hierarchy.dev.can_receive | index("shutdown_request") != null' "$SCHEMAS"
}

@test "shutdown_request: docs can_receive includes shutdown_request" {
  jq -e '.role_hierarchy.docs.can_receive | index("shutdown_request") != null' "$SCHEMAS"
}

@test "shutdown_request: lead can_receive includes shutdown_request" {
  jq -e '.role_hierarchy.lead.can_receive | index("shutdown_request") != null' "$SCHEMAS"
}

@test "shutdown_response: lead can_receive includes shutdown_response" {
  jq -e '.role_hierarchy.lead.can_receive | index("shutdown_response") != null' "$SCHEMAS"
}

# =============================================================================
# Architect exclusion: shutdown messages not available to planning-only role
# =============================================================================

@test "architect agent documents shutdown exemption" {
  grep -q '## Shutdown Handling' "$PROJECT_ROOT/agents/yolo-architect.md"
  sed -n '/^## Shutdown Handling$/,/^## /p' "$PROJECT_ROOT/agents/yolo-architect.md" | grep -qi 'planning-only'
}

@test "architect shutdown handling section order: after Effort, before Circuit Breaker" {
  local file="$PROJECT_ROOT/agents/yolo-architect.md"
  local effort_line shutdown_line breaker_line
  effort_line=$(grep -n '^## Effort' "$file" | head -1 | cut -d: -f1)
  shutdown_line=$(grep -n '^## Shutdown Handling' "$file" | head -1 | cut -d: -f1)
  breaker_line=$(grep -n '^## Circuit Breaker' "$file" | head -1 | cut -d: -f1)
  [ -n "$effort_line" ] && [ -n "$shutdown_line" ] && [ -n "$breaker_line" ]
  [ "$effort_line" -lt "$shutdown_line" ]
  [ "$shutdown_line" -lt "$breaker_line" ]
}

# =============================================================================
# Schema optional fields: shutdown_response supports pending_work
# =============================================================================

@test "shutdown_response: pending_work is in payload_optional" {
  jq -e '.schemas.shutdown_response.payload_optional | index("pending_work") != null' "$SCHEMAS"
}
