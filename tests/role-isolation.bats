#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning/phases/01-test"
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning/.contracts"
}

teardown() {
  teardown_temp_dir
}

create_plan_with_files() {
  cat > "$TEST_TEMP_DIR/.yolo-planning/phases/01-test/01-01-PLAN.md" << 'PLAN'
---
phase: 1
plan: 1
title: Test Plan
wave: 1
depends_on: []
tasks:
  - id: 1-1-T1
    title: Test task
    files: [src/allowed.js, src/helper.js]
---
PLAN
}

create_contract() {
  cat > "$TEST_TEMP_DIR/.yolo-planning/.contracts/01-01.json" << 'CONTRACT'
{"phase_id":"phase-1","plan_id":"01-01","phase":1,"plan":1,"objective":"Test","task_ids":["1-1-T1"],"task_count":1,"allowed_paths":["src/allowed.js","src/helper.js"],"forbidden_paths":["secrets/","node_modules/"],"depends_on":[],"must_haves":["Works"],"verification_checks":[],"max_token_budget":50000,"timeout_seconds":300,"contract_hash":"abc123"}
CONTRACT
}

# --- allowed_paths enforcement ---

@test "file-guard: blocks file outside contract allowed_paths" {
  cd "$TEST_TEMP_DIR"
  jq '.v2_hard_contracts = true' ".yolo-planning/config.json" > ".yolo-planning/config.json.tmp" \
    && mv ".yolo-planning/config.json.tmp" ".yolo-planning/config.json"
  create_plan_with_files
  create_contract
  INPUT='{"tool_name":"Write","tool_input":{"file_path":"src/unauthorized.js","content":"bad"}}'
  run bash -c "echo '$INPUT' | bash '$SCRIPTS_DIR/file-guard.sh'"
  [ "$status" -eq 2 ]
  [[ "$output" == *"not in contract allowed_paths"* ]]
}

@test "file-guard: allows file inside contract allowed_paths" {
  cd "$TEST_TEMP_DIR"
  jq '.v2_hard_contracts = true' ".yolo-planning/config.json" > ".yolo-planning/config.json.tmp" \
    && mv ".yolo-planning/config.json.tmp" ".yolo-planning/config.json"
  create_plan_with_files
  create_contract
  INPUT='{"tool_name":"Write","tool_input":{"file_path":"src/allowed.js","content":"ok"}}'
  run bash -c "echo '$INPUT' | bash '$SCRIPTS_DIR/file-guard.sh'"
  [ "$status" -eq 0 ]
}

@test "file-guard: exempts planning artifacts from allowed_paths check" {
  cd "$TEST_TEMP_DIR"
  jq '.v2_hard_contracts = true' ".yolo-planning/config.json" > ".yolo-planning/config.json.tmp" \
    && mv ".yolo-planning/config.json.tmp" ".yolo-planning/config.json"
  create_plan_with_files
  create_contract
  INPUT='{"tool_name":"Write","tool_input":{"file_path":".yolo-planning/phases/01-test/01-01-SUMMARY.md","content":"ok"}}'
  run bash -c "echo '$INPUT' | bash '$SCRIPTS_DIR/file-guard.sh'"
  [ "$status" -eq 0 ]
}

@test "file-guard: blocks forbidden_paths even when in allowed_paths" {
  cd "$TEST_TEMP_DIR"
  jq '.v2_hard_contracts = true' ".yolo-planning/config.json" > ".yolo-planning/config.json.tmp" \
    && mv ".yolo-planning/config.json.tmp" ".yolo-planning/config.json"
  create_plan_with_files
  create_contract
  INPUT='{"tool_name":"Write","tool_input":{"file_path":"secrets/api-key.json","content":"bad"}}'
  run bash -c "echo '$INPUT' | bash '$SCRIPTS_DIR/file-guard.sh'"
  [ "$status" -eq 2 ]
  [[ "$output" == *"forbidden path"* ]]
}

@test "file-guard: skips allowed_paths check when v2_hard_contracts=false" {
  cd "$TEST_TEMP_DIR"
  create_plan_with_files
  create_contract
  # v2_hard_contracts defaults to false in test config
  INPUT='{"tool_name":"Write","tool_input":{"file_path":"src/unauthorized.js","content":"ok"}}'
  run bash -c "echo '$INPUT' | bash '$SCRIPTS_DIR/file-guard.sh'"
  # Should not block (falls through to files_modified check only)
  # files_modified not in plan frontmatter, so fail-open
  [ "$status" -eq 0 ]
}

@test "file-guard: no contract present fails open" {
  cd "$TEST_TEMP_DIR"
  jq '.v2_hard_contracts = true' ".yolo-planning/config.json" > ".yolo-planning/config.json.tmp" \
    && mv ".yolo-planning/config.json.tmp" ".yolo-planning/config.json"
  create_plan_with_files
  # No contract file created
  INPUT='{"tool_name":"Write","tool_input":{"file_path":"src/anything.js","content":"ok"}}'
  run bash -c "echo '$INPUT' | bash '$SCRIPTS_DIR/file-guard.sh'"
  # No contract = fail-open (falls through to files_modified check)
  [ "$status" -eq 0 ]
}

# --- Role isolation in agent YAML ---

@test "agent: lead has V2 role isolation section" {
  run grep -c "V2 Role Isolation" "$PROJECT_ROOT/agents/yolo-lead.md"
  [ "$output" -ge 1 ]
}

@test "agent: dev has V2 role isolation section" {
  run grep -c "V2 Role Isolation" "$PROJECT_ROOT/agents/yolo-dev.md"
  [ "$output" -ge 1 ]
}

@test "agent: architect has V2 role isolation section" {
  run grep -c "V2 Role Isolation" "$PROJECT_ROOT/agents/yolo-architect.md"
  [ "$output" -ge 1 ]
}

@test "agent: qa has V2 role isolation section" {
  run grep -c "V2 Role Isolation" "$PROJECT_ROOT/agents/yolo-qa.md"
  [ "$output" -ge 1 ]
}

@test "agent: scout has V2 role isolation section" {
  run grep -c "V2 Role Isolation" "$PROJECT_ROOT/agents/yolo-scout.md"
  [ "$output" -ge 1 ]
}

@test "agent: debugger has V2 role isolation section" {
  run grep -c "V2 Role Isolation" "$PROJECT_ROOT/agents/yolo-debugger.md"
  [ "$output" -ge 1 ]
}

# --- v2_role_isolation flag ---

@test "defaults.json includes v2_role_isolation flag" {
  run jq '.v2_role_isolation' "$CONFIG_DIR/defaults.json"
  [ "$output" = "false" ]
}

# --- Lease integration in protocol ---

@test "execute-protocol references lease in V2 gate sequence" {
  run grep -c "Lease acquisition" "$PROJECT_ROOT/references/execute-protocol.md"
  [ "$output" -ge 1 ]
  run grep -c "Lease release" "$PROJECT_ROOT/references/execute-protocol.md"
  [ "$output" -ge 1 ]
}
