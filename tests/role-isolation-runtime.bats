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
files_modified:
  - src/allowed.js
tasks:
  - id: 1-1-T1
    title: Test task
    files: [src/allowed.js]
---
PLAN
}

create_contract() {
  cat > "$TEST_TEMP_DIR/.yolo-planning/.contracts/01-01.json" << 'CONTRACT'
{"phase_id":"phase-1","plan_id":"01-01","phase":1,"plan":1,"objective":"Test","task_ids":["1-1-T1"],"task_count":1,"allowed_paths":["src/allowed.js"],"forbidden_paths":[],"depends_on":[],"must_haves":["Works"],"verification_checks":[],"max_token_budget":50000,"timeout_seconds":300,"contract_hash":"abc123"}
CONTRACT
}

# --- Role isolation: Rust source verification ---

@test "validate_contract.rs has allowed_paths enforcement" {
  grep -q 'allowed_paths' "$RUST_SRC/hooks/validate_contract.rs"
}

@test "validate_contract.rs has forbidden_paths enforcement" {
  grep -q 'forbidden_paths' "$RUST_SRC/hooks/validate_contract.rs"
}

@test "validate_contract.rs uses exit code 2 for hard violations" {
  grep -q 'exit_code.*2\|code.*=.*2' "$RUST_SRC/hooks/validate_contract.rs"
}

@test "validate_contract.rs has v2_hard_contracts check" {
  grep -q 'v2_hard_contracts\|hard_contracts' "$RUST_SRC/hooks/validate_contract.rs"
}

@test "pre-tool-use hook exits 0 for non-Write tools" {
  cd "$TEST_TEMP_DIR"
  INPUT='{"tool_name":"Read","tool_input":{"file_path":"src/anything.js"}}'
  run bash -c "echo '$INPUT' | \"$YOLO_BIN\" hook pre-tool-use"
  [ "$status" -eq 0 ]
}

@test "pre-tool-use hook handles Write tool without crash" {
  cd "$TEST_TEMP_DIR"
  create_plan_with_files
  INPUT='{"tool_name":"Write","tool_input":{"file_path":"src/allowed.js","content":"ok"}}'
  run bash -c "echo '$INPUT' | \"$YOLO_BIN\" hook pre-tool-use"
  [ "$status" -eq 0 ]
}
