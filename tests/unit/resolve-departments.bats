#!/usr/bin/env bats
# resolve-departments.bats — Unit tests for scripts/resolve-departments.sh
# Department routing resolution for YOLO multi-department mode.
# Usage: resolve-departments.sh [config_path]
# Outputs key-value pairs for routing decisions.

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/resolve-departments.sh"
}

# Helper: run resolve-departments with config path
run_resolve() {
  local config="${1:-$TEST_WORKDIR/.yolo-planning/config.json}"
  run bash "$SUT" "$config"
}

# Helper: create config with custom settings
mk_config() {
  local backend="${1:-true}"
  local frontend="${2:-false}"
  local uiux="${3:-false}"
  local workflow="${4:-backend_only}"
  mkdir -p "$TEST_WORKDIR/.yolo-planning"
  jq -n \
    --argjson be "$backend" \
    --argjson fe "$frontend" \
    --argjson ux "$uiux" \
    --arg wf "$workflow" \
    '{departments:{backend:$be,frontend:$fe,uiux:$ux},department_workflow:$wf}' \
    > "$TEST_WORKDIR/.yolo-planning/config.json"
}

# --- Default config (all enabled, parallel) ---

@test "no config file: defaults to backend_only" {
  # No config file = backend_only (matches jq fallback)
  run_resolve "$TEST_WORKDIR/nonexistent.json"
  assert_success
  assert_output --partial "multi_dept=false"
  assert_output --partial "workflow=backend_only"
  assert_output --partial "active_depts=backend"
  assert_output --partial "leads_to_spawn=lead"
  assert_output --partial "spawn_order=single"
  assert_output --partial "owner_active=false"
  assert_output --partial "fe_active=false"
  assert_output --partial "ux_active=false"
}

@test "no-config and empty-config produce identical output" {
  # No config file
  run_resolve "$TEST_WORKDIR/nonexistent.json"
  assert_success
  local no_config_output="$output"

  # Empty config file
  mkdir -p "$TEST_WORKDIR/.yolo-planning"
  echo '{}' > "$TEST_WORKDIR/.yolo-planning/config.json"
  run_resolve
  assert_success

  assert_equal "$no_config_output" "$output"
}

# --- Backend-only mode ---

@test "backend-only mode: single department" {
  mk_config true false false backend_only
  run_resolve
  assert_success
  assert_output --partial "multi_dept=false"
  assert_output --partial "workflow=backend_only"
  assert_output --partial "active_depts=backend"
  assert_output --partial "leads_to_spawn=lead"
  assert_output --partial "spawn_order=single"
  assert_output --partial "owner_active=false"
  assert_output --partial "fe_active=false"
  assert_output --partial "ux_active=false"
}

@test "backend-only mode: frontend enabled but workflow backend_only" {
  mk_config true true false backend_only
  run_resolve
  assert_success
  assert_output --partial "multi_dept=false"
  assert_output --partial "workflow=backend_only"
  assert_output --partial "active_depts=backend,frontend"
  assert_output --partial "owner_active=false"
}

# --- Parallel workflow ---

@test "parallel workflow: frontend only" {
  mk_config true true false parallel
  run_resolve
  assert_success
  assert_output --partial "multi_dept=true"
  assert_output --partial "workflow=parallel"
  assert_output --partial "active_depts=backend,frontend"
  assert_output --partial "leads_to_spawn=fe-lead,lead"
  assert_output --partial "spawn_order=wave"
  assert_output --partial "owner_active=true"
  assert_output --partial "fe_active=true"
  assert_output --partial "ux_active=false"
}

@test "parallel workflow: uiux only" {
  mk_config true false true parallel
  run_resolve
  assert_success
  assert_output --partial "multi_dept=true"
  assert_output --partial "workflow=parallel"
  assert_output --partial "active_depts=backend,uiux"
  assert_output --partial "leads_to_spawn=ux-lead|lead"
  assert_output --partial "spawn_order=wave"
  assert_output --partial "owner_active=true"
  assert_output --partial "fe_active=false"
  assert_output --partial "ux_active=true"
}

@test "parallel workflow: uiux + frontend" {
  mk_config true true true parallel
  run_resolve
  assert_success
  assert_output --partial "multi_dept=true"
  assert_output --partial "workflow=parallel"
  assert_output --partial "active_depts=backend,frontend,uiux"
  assert_output --partial "leads_to_spawn=ux-lead|fe-lead,lead"
  assert_output --partial "spawn_order=wave"
  assert_output --partial "owner_active=true"
  assert_output --partial "fe_active=true"
  assert_output --partial "ux_active=true"
}

# --- Sequential workflow ---

@test "sequential workflow: uiux + frontend" {
  mk_config true true true sequential
  run_resolve
  assert_success
  assert_output --partial "multi_dept=true"
  assert_output --partial "workflow=sequential"
  assert_output --partial "active_depts=backend,frontend,uiux"
  assert_output --partial "leads_to_spawn=ux-lead|fe-lead|lead"
  assert_output --partial "spawn_order=sequential"
  assert_output --partial "owner_active=true"
  assert_output --partial "fe_active=true"
  assert_output --partial "ux_active=true"
}

@test "sequential workflow: frontend only" {
  mk_config true true false sequential
  run_resolve
  assert_success
  assert_output --partial "multi_dept=true"
  assert_output --partial "workflow=sequential"
  assert_output --partial "active_depts=backend,frontend"
  assert_output --partial "leads_to_spawn=fe-lead|lead"
  assert_output --partial "spawn_order=sequential"
  assert_output --partial "owner_active=true"
  assert_output --partial "fe_active=true"
  assert_output --partial "ux_active=false"
}

@test "sequential workflow: uiux only" {
  mk_config true false true sequential
  run_resolve
  assert_success
  assert_output --partial "multi_dept=true"
  assert_output --partial "workflow=sequential"
  assert_output --partial "active_depts=backend,uiux"
  assert_output --partial "leads_to_spawn=ux-lead|lead"
  assert_output --partial "spawn_order=sequential"
  assert_output --partial "owner_active=true"
  assert_output --partial "fe_active=false"
  assert_output --partial "ux_active=true"
}

# --- Missing keys / malformed config ---

@test "missing departments key: handles gracefully" {
  mkdir -p "$TEST_WORKDIR/.yolo-planning"
  echo '{"department_workflow":"parallel"}' > "$TEST_WORKDIR/.yolo-planning/config.json"
  run_resolve
  assert_success
  # Should use defaults: backend=true, frontend=false, uiux=false
  # Runtime warning corrects parallel→backend_only when no non-backend depts
  assert_output --partial "multi_dept=false"
  assert_output --partial "workflow=backend_only"
  assert_output --partial "active_depts=backend"
  assert_output --partial "fe_active=false"
  assert_output --partial "ux_active=false"
}

@test "missing department_workflow key: defaults to backend_only" {
  mkdir -p "$TEST_WORKDIR/.yolo-planning"
  echo '{"departments":{"backend":true,"frontend":true,"uiux":false}}' > "$TEST_WORKDIR/.yolo-planning/config.json"
  run_resolve
  assert_success
  assert_output --partial "workflow=backend_only"
  assert_output --partial "multi_dept=false"
}

@test "empty config file: uses defaults" {
  mkdir -p "$TEST_WORKDIR/.yolo-planning"
  echo '{}' > "$TEST_WORKDIR/.yolo-planning/config.json"
  run_resolve
  assert_success
  assert_output --partial "multi_dept=false"
  assert_output --partial "workflow=backend_only"
  assert_output --partial "active_depts=backend"
}

# --- Spawn order validation ---

@test "spawn order: single for backend-only" {
  mk_config true false false backend_only
  run_resolve
  assert_success
  assert_output --partial "spawn_order=single"
  assert_output --partial "leads_to_spawn=lead"
}

@test "spawn order: wave for parallel with multiple depts" {
  mk_config true true false parallel
  run_resolve
  assert_success
  assert_output --partial "spawn_order=wave"
  # FE+BE in parallel (no UX wave)
  assert_output --partial "leads_to_spawn=fe-lead,lead"
}

@test "spawn order: sequential outputs pipe-separated" {
  mk_config true true true sequential
  run_resolve
  assert_success
  assert_output --partial "spawn_order=sequential"
  # UX | FE | BE
  assert_output --partial "leads_to_spawn=ux-lead|fe-lead|lead"
}

# --- Edge cases ---

@test "backend disabled: should still output backend in active_depts" {
  # Backend is always active (hardcoded in script)
  mk_config false true true parallel
  run_resolve
  assert_success
  assert_output --partial "active_depts=backend,frontend,uiux"
}

@test "parallel workflow with all depts spawns ux first, then fe+be" {
  mk_config true true true parallel
  run_resolve
  assert_success
  # Wave 1: ux-lead
  # Wave 2: fe-lead,lead (parallel)
  assert_output --partial "leads_to_spawn=ux-lead|fe-lead,lead"
}

# --- Defaults.json consistency ---

@test "defaults.json produces backend_only" {
  mkdir -p "$TEST_WORKDIR/.yolo-planning"
  cp "$CONFIG_DIR/defaults.json" "$TEST_WORKDIR/.yolo-planning/config.json"
  run_resolve
  assert_success
  assert_output --partial "multi_dept=false"
  assert_output --partial "workflow=backend_only"
  assert_output --partial "active_depts=backend"
  assert_output --partial "leads_to_spawn=lead"
  assert_output --partial "spawn_order=single"
  assert_output --partial "owner_active=false"
  assert_output --partial "fe_active=false"
  assert_output --partial "ux_active=false"
}

@test "defaults.json output matches no-config output exactly" {
  run_resolve "$TEST_WORKDIR/nonexistent.json"
  assert_success
  local no_config_output="$output"

  mkdir -p "$TEST_WORKDIR/.yolo-planning"
  cp "$CONFIG_DIR/defaults.json" "$TEST_WORKDIR/.yolo-planning/config.json"
  run_resolve
  assert_success

  assert_equal "$no_config_output" "$output"
}

@test "parallel with no non-backend depts emits warning and falls back" {
  mk_config true false false parallel
  run_resolve
  assert_success
  assert_output --partial "[warn]"
  assert_output --partial "workflow=backend_only"
  assert_output --partial "multi_dept=false"
}

@test "sequential with no non-backend depts emits warning and falls back" {
  mk_config true false false sequential
  run_resolve
  assert_success
  assert_output --partial "[warn]"
  assert_output --partial "workflow=backend_only"
  assert_output --partial "multi_dept=false"
}
