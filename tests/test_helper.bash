#!/bin/bash
# Shared test helper for YOLO bats tests

# Project root (relative to tests/ dir)
export PROJECT_ROOT="${BATS_TEST_DIRNAME}/.."
export SCRIPTS_DIR="${PROJECT_ROOT}/scripts"
export CONFIG_DIR="${PROJECT_ROOT}/config"

# Create temp directory for test isolation
setup_temp_dir() {
  export TEST_TEMP_DIR=$(mktemp -d)
  mkdir -p "$TEST_TEMP_DIR/.yolo-planning"
}

# Clean up temp directory
teardown_temp_dir() {
  [ -n "${TEST_TEMP_DIR:-}" ] && rm -rf "$TEST_TEMP_DIR"
}

# Create minimal config.json for tests
create_test_config() {
  local dir="${1:-.yolo-planning}"
  cat > "$TEST_TEMP_DIR/$dir/config.json" <<'CONF'
{
  "effort": "balanced",
  "autonomy": "standard",
  "auto_commit": true,
  "planning_tracking": "manual",
  "auto_push": "never",
  "verification_tier": "standard",
  "skill_suggestions": true,
  "auto_install_skills": false,
  "discovery_questions": true,
  "visual_format": "unicode",
  "max_tasks_per_plan": 5,
  "prefer_teams": "always",
  "branch_per_milestone": false,
  "plain_summary": true,
  "qa_skip_agents": ["docs"],
  "active_profile": "default",
  "custom_profiles": {},
  "model_profile": "quality",
  "model_overrides": {},
  "agent_max_turns": {
    "scout": 15,
    "qa": 25,
    "architect": 30,
    "debugger": 80,
    "lead": 50,
    "dev": 75
  },
  "context_compiler": true,
  "v3_delta_context": false,
  "v3_context_cache": false,
  "v3_plan_research_persist": false,
  "v3_metrics": false,
  "v3_contract_lite": false,
  "v3_lock_lite": false,
  "v3_validation_gates": false,
  "v3_smart_routing": false,
  "v3_event_log": false,
  "v3_schema_validation": false,
  "v3_snapshot_resume": false,
  "v3_lease_locks": false,
  "v3_event_recovery": false,
  "v3_monorepo_routing": false,
  "v3_rolling_summary": false,
  "v2_hard_contracts": false,
  "v2_hard_gates": false,
  "v2_typed_protocol": false,
  "v2_role_isolation": false,
  "v2_two_phase_completion": false,
  "v2_token_budgets": false
}
CONF
}

# Seed an agent_token_usage event into run-metrics.jsonl
# Usage: seed_agent_token_event <role> <phase> <input> <output> <cache_read> <cache_write>
seed_agent_token_event() {
  local role="$1" phase="$2" input="$3" output="$4" cache_read="$5" cache_write="$6"
  local metrics_dir="$TEST_TEMP_DIR/.yolo-planning/.metrics"
  mkdir -p "$metrics_dir"
  printf '{"ts":"2026-02-20T10:00:00Z","event":"agent_token_usage","phase":%s,"data":{"role":"%s","input_tokens":"%s","output_tokens":"%s","cache_read_tokens":"%s","cache_write_tokens":"%s"}}\n' \
    "$phase" "$role" "$input" "$output" "$cache_read" "$cache_write" \
    >> "$metrics_dir/run-metrics.jsonl"
}

# Seed a task_completed_confirmed event into event-log.jsonl
# Usage: seed_task_completed <phase> <task_id>
seed_task_completed() {
  local phase="$1" task_id="$2"
  local events_dir="$TEST_TEMP_DIR/.yolo-planning/.events"
  mkdir -p "$events_dir"
  printf '{"ts":"2026-02-20T10:00:00Z","event_id":"evt-%s","event":"task_completed_confirmed","phase":%s,"data":{"task":"%s"}}\n' \
    "$task_id" "$phase" "$task_id" \
    >> "$events_dir/event-log.jsonl"
}
