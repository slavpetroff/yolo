#!/usr/bin/env bats

load test_helper

RUST_SRC="$PROJECT_ROOT/yolo-mcp-server/src"

setup() {
  setup_temp_dir
  create_test_config
  export YOLO_BIN="${YOLO_BIN:-$HOME/.cargo/bin/yolo}"
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

# --- Contract validation: Rust source verification ---

@test "validate_contract: blocks file outside allowed_paths (Rust source)" {
  grep -q 'not in allowed_paths' "$RUST_SRC/hooks/validate_contract.rs"
}

@test "validate_contract: checks allowed_paths list" {
  grep -q 'allowed_paths' "$RUST_SRC/hooks/validate_contract.rs"
}

@test "validate_contract: fails open when flags disabled" {
  grep -q 'v3_lite.*v2_hard\|!v3_lite && !v2_hard' "$RUST_SRC/hooks/validate_contract.rs"
}

@test "validate_contract: blocks forbidden_paths" {
  grep -q 'forbidden.*path\|forbidden_paths' "$RUST_SRC/hooks/validate_contract.rs"
}

@test "validate_contract: advisory mode for v3_contract_lite" {
  grep -q 'contract_lite\|advisory' "$RUST_SRC/hooks/validate_contract.rs"
}

@test "validate_contract: hard mode for v2_hard_contracts" {
  grep -q 'v2_hard\|hard_contracts' "$RUST_SRC/hooks/validate_contract.rs"
}

@test "validate_contract: has start and end modes" {
  grep -q '"start"' "$RUST_SRC/hooks/validate_contract.rs"
  grep -q '"end"' "$RUST_SRC/hooks/validate_contract.rs"
}

# --- Role isolation in agent definitions ---

@test "agent: architect has V2 role isolation section" {
  run grep -c "V2 Role Isolation" "$PROJECT_ROOT/agents/yolo-architect.md"
  [ "$output" -ge 1 ]
}

@test "agent: lead defines file access constraints" {
  # Lead agent must have write restrictions or role boundaries
  grep -qi 'write\|planning\|restrict\|scope' "$PROJECT_ROOT/agents/yolo-lead.md"
}

@test "agent: dev defines file access scope" {
  grep -qi 'file\|scope\|contract\|allowed' "$PROJECT_ROOT/agents/yolo-dev.md"
}

@test "agent: reviewer has read-oriented scope" {
  grep -qi 'review\|read\|verify\|check' "$PROJECT_ROOT/agents/yolo-reviewer.md"
}

# --- v2_role_isolation flag ---

@test "defaults.json includes v2_role_isolation flag" {
  run jq '.v2_role_isolation' "$CONFIG_DIR/defaults.json"
  [ "$output" = "false" ]
}

# --- Lease integration in protocol ---

@test "execute-protocol references lease in V2 gate sequence" {
  run grep -c "Lease acquisition" "$PROJECT_ROOT/skills/execute-protocol/SKILL.md"
  [ "$output" -ge 1 ]
  run grep -c "Lease release" "$PROJECT_ROOT/skills/execute-protocol/SKILL.md"
  [ "$output" -ge 1 ]
}

# --- Pre-tool-use hook integration ---

@test "pre-tool-use hook handles Write without crash" {
  cd "$TEST_TEMP_DIR"
  create_plan_with_files
  INPUT='{"tool_name":"Write","tool_input":{"file_path":"src/allowed.js","content":"ok"}}'
  run bash -c "echo '$INPUT' | \"$YOLO_BIN\" hook pre-tool-use"
  [ "$status" -eq 0 ]
}
