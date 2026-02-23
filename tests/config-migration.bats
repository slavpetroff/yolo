#!/usr/bin/env bats
# Migrated: migrate-config.sh -> yolo migrate-config
# CWD-sensitive: no (takes config_path as argument)

load test_helper

setup() {
  setup_temp_dir
}

teardown() {
  teardown_temp_dir
}

# Helper: Run the migration via CLI
run_migration() {
  "$YOLO_BIN" migrate-config "$TEST_TEMP_DIR/.yolo-planning/config.json" "$CONFIG_DIR/defaults.json"
}

@test "migration handles empty config" {
  cat > "$TEST_TEMP_DIR/.yolo-planning/config.json" <<'EOF'
{
  "effort": "balanced",
  "autonomy": "standard"
}
EOF

  run_migration

  # Verify all 23 flags were added
  run jq '[
    has("context_compiler"), has("v3_delta_context"), has("v3_context_cache"),
    has("v3_plan_research_persist"), has("v3_metrics"), has("v3_contract_lite"),
    has("v3_lock_lite"), has("v3_validation_gates"), has("v3_smart_routing"),
    has("v3_event_log"), has("v3_schema_validation"), has("v3_snapshot_resume"),
    has("v3_lease_locks"), has("v3_event_recovery"), has("v3_monorepo_routing"),
    has("v2_hard_contracts"), has("v2_hard_gates"), has("v2_typed_protocol"),
    has("v2_role_isolation"), has("v2_two_phase_completion"), has("v2_token_budgets"),
    has("model_overrides"), has("prefer_teams")
  ] | map(select(.)) | length' "$TEST_TEMP_DIR/.yolo-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "23" ]

  # Verify context_compiler defaults to true
  run jq -r '.context_compiler' "$TEST_TEMP_DIR/.yolo-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  # Verify v3 flags default to false
  run jq -r '.v3_delta_context' "$TEST_TEMP_DIR/.yolo-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "migration handles partial config" {
  cat > "$TEST_TEMP_DIR/.yolo-planning/config.json" <<'EOF'
{
  "effort": "balanced",
  "context_compiler": false,
  "v3_delta_context": true,
  "v2_hard_contracts": true
}
EOF

  run_migration

  # Verify all 23 flags exist
  run jq '[
    has("context_compiler"), has("v3_delta_context"), has("v3_context_cache"),
    has("v3_plan_research_persist"), has("v3_metrics"), has("v3_contract_lite"),
    has("v3_lock_lite"), has("v3_validation_gates"), has("v3_smart_routing"),
    has("v3_event_log"), has("v3_schema_validation"), has("v3_snapshot_resume"),
    has("v3_lease_locks"), has("v3_event_recovery"), has("v3_monorepo_routing"),
    has("v2_hard_contracts"), has("v2_hard_gates"), has("v2_typed_protocol"),
    has("v2_role_isolation"), has("v2_two_phase_completion"), has("v2_token_budgets"),
    has("model_overrides"), has("prefer_teams")
  ] | map(select(.)) | length' "$TEST_TEMP_DIR/.yolo-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "23" ]

  # Verify existing values were preserved
  run jq -r '.context_compiler' "$TEST_TEMP_DIR/.yolo-planning/config.json"
  [ "$output" = "false" ]

  run jq -r '.v3_delta_context' "$TEST_TEMP_DIR/.yolo-planning/config.json"
  [ "$output" = "true" ]

  run jq -r '.v2_hard_contracts' "$TEST_TEMP_DIR/.yolo-planning/config.json"
  [ "$output" = "true" ]
}

@test "migration handles full config" {
  create_test_config
  BEFORE=$(jq -S . "$TEST_TEMP_DIR/.yolo-planning/config.json")

  run_migration

  AFTER=$(jq -S . "$TEST_TEMP_DIR/.yolo-planning/config.json")
  [ "$BEFORE" = "$AFTER" ]
}

@test "migration is idempotent" {
  cat > "$TEST_TEMP_DIR/.yolo-planning/config.json" <<'EOF'
{
  "effort": "balanced"
}
EOF

  run_migration
  AFTER_FIRST=$(cat "$TEST_TEMP_DIR/.yolo-planning/config.json")

  run_migration
  AFTER_SECOND=$(cat "$TEST_TEMP_DIR/.yolo-planning/config.json")

  [ "$AFTER_FIRST" = "$AFTER_SECOND" ]
}

@test "migration detects malformed JSON" {
  cat > "$TEST_TEMP_DIR/.yolo-planning/config.json" <<'EOF'
{
  "effort": "balanced",
  invalid json here
}
EOF

  run "$YOLO_BIN" migrate-config "$TEST_TEMP_DIR/.yolo-planning/config.json" "$CONFIG_DIR/defaults.json"
  [ "$status" -ne 0 ]
}

@test "defaults.json has expected number of feature flags" {
  # Count v3_*, v2_*, context_compiler, model_overrides, prefer_teams
  DEFAULTS_COUNT=$(jq '[keys[] | select(startswith("v3_") or startswith("v2_") or . == "context_compiler" or . == "model_overrides" or . == "prefer_teams")] | length' "$CONFIG_DIR/defaults.json")
  [ "$DEFAULTS_COUNT" = "23" ]
}

@test "migration adds missing prefer_teams with default value" {
  cat > "$TEST_TEMP_DIR/.yolo-planning/config.json" <<'EOF'
{
  "effort": "balanced",
  "autonomy": "standard"
}
EOF

  run_migration

  run jq -r '.prefer_teams' "$TEST_TEMP_DIR/.yolo-planning/config.json"
  [ "$output" = "always" ]
}

@test "migration adds planning_tracking and auto_push defaults" {
  cat > "$TEST_TEMP_DIR/.yolo-planning/config.json" <<'EOF'
{
  "effort": "balanced"
}
EOF

  run_migration

  run jq -r '.planning_tracking' "$TEST_TEMP_DIR/.yolo-planning/config.json"
  [ "$output" = "manual" ]

  run jq -r '.auto_push' "$TEST_TEMP_DIR/.yolo-planning/config.json"
  [ "$output" = "never" ]
}

@test "migration preserves existing planning_tracking and auto_push values" {
  cat > "$TEST_TEMP_DIR/.yolo-planning/config.json" <<'EOF'
{
  "effort": "balanced",
  "planning_tracking": "commit",
  "auto_push": "after_phase"
}
EOF

  run_migration

  run jq -r '.planning_tracking' "$TEST_TEMP_DIR/.yolo-planning/config.json"
  [ "$output" = "commit" ]

  run jq -r '.auto_push' "$TEST_TEMP_DIR/.yolo-planning/config.json"
  [ "$output" = "after_phase" ]
}

@test "migration preserves existing prefer_teams value" {
  cat > "$TEST_TEMP_DIR/.yolo-planning/config.json" <<'EOF'
{
  "effort": "balanced",
  "prefer_teams": "never"
}
EOF

  run_migration

  run jq -r '.prefer_teams' "$TEST_TEMP_DIR/.yolo-planning/config.json"
  [ "$output" = "never" ]
}

@test "migration adds missing agent_max_turns defaults" {
  cat > "$TEST_TEMP_DIR/.yolo-planning/config.json" <<'EOF'
{
  "effort": "balanced"
}
EOF

  run_migration

  run jq -r '.agent_max_turns.scout' "$TEST_TEMP_DIR/.yolo-planning/config.json"
  [ "$output" = "15" ]

  run jq -r '.agent_max_turns.debugger' "$TEST_TEMP_DIR/.yolo-planning/config.json"
  [ "$output" = "80" ]
}

@test "migration preserves existing agent_max_turns values" {
  cat > "$TEST_TEMP_DIR/.yolo-planning/config.json" <<'EOF'
{
  "effort": "balanced",
  "agent_max_turns": {
    "debugger": 120,
    "dev": 90
  }
}
EOF

  run_migration

  run jq -r '.agent_max_turns.debugger' "$TEST_TEMP_DIR/.yolo-planning/config.json"
  [ "$output" = "120" ]

  run jq -r '.agent_max_turns.dev' "$TEST_TEMP_DIR/.yolo-planning/config.json"
  [ "$output" = "90" ]
}

@test "migration renames agent_teams to prefer_teams and removes stale key" {
  cat > "$TEST_TEMP_DIR/.yolo-planning/config.json" <<'EOF'
{
  "effort": "balanced",
  "agent_teams": true
}
EOF

  run_migration

  run jq -r '.prefer_teams' "$TEST_TEMP_DIR/.yolo-planning/config.json"
  [ "$output" = "always" ]

  run jq -r 'has("agent_teams")' "$TEST_TEMP_DIR/.yolo-planning/config.json"
  [ "$output" = "false" ]
}

@test "migration removes stale agent_teams when prefer_teams already exists" {
  cat > "$TEST_TEMP_DIR/.yolo-planning/config.json" <<'EOF'
{
  "effort": "balanced",
  "prefer_teams": "auto",
  "agent_teams": false
}
EOF

  run_migration

  run jq -r '.prefer_teams' "$TEST_TEMP_DIR/.yolo-planning/config.json"
  [ "$output" = "auto" ]

  run jq -r 'has("agent_teams")' "$TEST_TEMP_DIR/.yolo-planning/config.json"
  [ "$output" = "false" ]
}

@test "migration maps agent_teams false to prefer_teams auto" {
  cat > "$TEST_TEMP_DIR/.yolo-planning/config.json" <<'EOF'
{
  "effort": "balanced",
  "agent_teams": false
}
EOF

  run_migration

  run jq -r '.prefer_teams' "$TEST_TEMP_DIR/.yolo-planning/config.json"
  [ "$output" = "auto" ]
}

@test "migration backfills all missing defaults keys" {
  cat > "$TEST_TEMP_DIR/.yolo-planning/config.json" <<'EOF'
{
  "effort": "balanced"
}
EOF

  run jq -s '.[0] as $d | .[1] as $c | [$d | keys[] | select($c[.] == null)] | length' "$CONFIG_DIR/defaults.json" "$TEST_TEMP_DIR/.yolo-planning/config.json"
  [ "$status" -eq 0 ]
  BEFORE_MISSING="$output"
  [ "$BEFORE_MISSING" -gt 0 ]

  run_migration

  run jq -s '.[0] as $d | .[1] as $c | [$d | keys[] | select($c[.] == null)] | length' "$CONFIG_DIR/defaults.json" "$TEST_TEMP_DIR/.yolo-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "new config gets v2_token_budgets=true from defaults" {
  cat > "$TEST_TEMP_DIR/.yolo-planning/config.json" <<'EOF'
{
  "effort": "balanced"
}
EOF

  run_migration

  run jq -r '.v2_token_budgets' "$TEST_TEMP_DIR/.yolo-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "existing config with v2_token_budgets=false keeps false after migration" {
  cat > "$TEST_TEMP_DIR/.yolo-planning/config.json" <<'EOF'
{
  "effort": "balanced",
  "v2_token_budgets": false
}
EOF

  run_migration

  run jq -r '.v2_token_budgets' "$TEST_TEMP_DIR/.yolo-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "migration --print-added returns number of inserted defaults" {
  cat > "$TEST_TEMP_DIR/.yolo-planning/config.json" <<'EOF'
{
  "effort": "balanced"
}
EOF

  run jq -s '.[0] as $d | .[1] as $c | [$d | keys[] | select($c[.] == null)] | length' "$CONFIG_DIR/defaults.json" "$TEST_TEMP_DIR/.yolo-planning/config.json"
  [ "$status" -eq 0 ]
  EXPECTED_ADDED="$output"

  run "$YOLO_BIN" migrate-config "$TEST_TEMP_DIR/.yolo-planning/config.json" "$CONFIG_DIR/defaults.json" --print-added
  [ "$status" -eq 0 ]
  # Extract last line (skip any WARNING lines on stderr captured by run)
  local actual
  actual=$(echo "$output" | tail -1)
  [ "$actual" = "$EXPECTED_ADDED" ]
}
