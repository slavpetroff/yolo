#!/usr/bin/env bash
set -u

# qa-gate.sh — Consolidated QA gate dispatcher.
#
# Modes:
#   (no --tier)         Notification hook: structural checks (exit 0=allow, exit 2=block)
#   --tier task         Post-task gate: test-summary.sh after each task (exit 0=pass/warn, 1=fail)
#   --tier plan         Post-plan gate: summary + full test suite + must_haves (exit 0=pass/warn, 1=fail)
#   --tier phase        Post-phase gate: validate-gates + all plans + full tests (exit 0=pass/warn, 1=fail)
#
# Common flags (--tier modes only):
#   --phase-dir <path>  Required. Phase directory path.
#   --plan <ID>         Plan ID (required for task/plan tiers).
#   --task <ID>         Task ID (task tier only).
#   --timeout <N>       Timeout in seconds.
#   --scope             Scoped test execution (task tier only).
#   --files <f1,f2>     Explicit file list for scoped tests (task tier only).

# --- Source shared library if available ---
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_LIB_PATH="$_SCRIPT_DIR/../lib/yolo-common.sh"
if [ -f "$_LIB_PATH" ]; then
  # shellcheck source=../lib/yolo-common.sh
  source "$_LIB_PATH"
fi

# --- jq dependency check (for --tier modes) ---
_require_jq() {
  if ! command -v jq &>/dev/null; then
    echo '{"error":"jq is required but not installed. Install: brew install jq (macOS) / apt install jq (Linux)"}' >&2
    exit 1
  fi
}

# --- Shared: timeout wrapper ---
_run_with_timeout() {
  if declare -f run_with_timeout &>/dev/null; then
    run_with_timeout "$@"
    return $?
  fi
  # Inline fallback if lib not loaded
  local secs="$1"; shift
  if command -v timeout &>/dev/null; then
    timeout "$secs" "$@"
    return $?
  elif command -v gtimeout &>/dev/null; then
    gtimeout "$secs" "$@"
    return $?
  else
    "$@" &
    local cmd_pid=$!
    local elapsed=0
    while kill -0 "$cmd_pid" 2>/dev/null; do
      if [ "$elapsed" -ge "$secs" ]; then
        pkill -P "$cmd_pid" 2>/dev/null || true
        kill "$cmd_pid" 2>/dev/null || true
        wait "$cmd_pid" 2>/dev/null || true
        return 124
      fi
      sleep 1
      elapsed=$((elapsed + 1))
    done
    wait "$cmd_pid" 2>/dev/null
    return $?
  fi
}

# --- Shared: lock helpers ---
_has_flock() {
  command -v flock &>/dev/null
}

_acquire_lock_flock() {
  exec 200>"$_LOCK_FILE" && flock -n 200
  return $?
}

_acquire_lock_mkdir() {
  mkdir "${_LOCK_FILE}.d" 2>/dev/null
  return $?
}

_release_lock_mkdir() {
  rmdir "${_LOCK_FILE}.d" 2>/dev/null || true
}

_sleep_ms() {
  local ms="$1"
  if command -v awk &>/dev/null; then
    sleep "$(awk "BEGIN {printf \"%.3f\", $ms/1000}")"
  elif command -v bc &>/dev/null; then
    sleep "$(echo "scale=3; $ms/1000" | bc)"
  elif command -v python3 &>/dev/null; then
    sleep "$(python3 -c "print(f'{$ms/1000:.3f}')")"
  else
    sleep $(( (ms + 999) / 1000 ))
  fi
}

# --- Shared: persist result to .qa-gate-results.jsonl ---
_persist_result() {
  local result_json="$1" phase_dir="$2"
  _LOCK_FILE="$phase_dir/.qa-gate-results.lock"
  local results_file="$phase_dir/.qa-gate-results.jsonl"
  local max_retries=5
  local base_delay_ms=200

  local use_flock=false
  if _has_flock; then
    use_flock=true
  fi

  for i in $(seq 0 $((max_retries - 1))); do
    local lock_acquired=false
    if [ "$use_flock" = true ]; then
      if _acquire_lock_flock; then
        lock_acquired=true
      fi
    else
      if _acquire_lock_mkdir; then
        lock_acquired=true
      fi
    fi

    if [ "$lock_acquired" = true ]; then
      echo "$result_json" | jq -c '.' >> "$results_file"
      if [ "$use_flock" = false ]; then
        _release_lock_mkdir
      fi
      return 0
    fi

    local delay=$((base_delay_ms * (1 << i)))
    _sleep_ms "$delay"
  done

  echo "WARN: Could not acquire lock for results file after $max_retries retries" >&2
  return 0
}

# --- Shared: config toggle check ---
_load_qa_config() {
  local phase_dir="$1" config_key="$2"
  local qa_config_script
  qa_config_script=$(command -v resolve-qa-config.sh 2>/dev/null) || qa_config_script="$_SCRIPT_DIR/resolve-qa-config.sh"
  if [ -x "$qa_config_script" ]; then
    local _cfg_path _def_path
    _cfg_path="$(dirname "$(dirname "$phase_dir")")/config.json"
    _def_path="$_SCRIPT_DIR/../config/defaults.json"
    _QA_CONFIG_JSON=$("$qa_config_script" "$_cfg_path" "$_def_path" 2>/dev/null) || _QA_CONFIG_JSON="{}"
    local enabled
    enabled=$(echo "$_QA_CONFIG_JSON" | jq -r "if .${config_key} == null then true else .${config_key} end" 2>/dev/null) || enabled="true"
    echo "$enabled"
  else
    _QA_CONFIG_JSON="{}"
    echo "true"
  fi
}

# --- Shared: team mode detection ---
_detect_team_mode() {
  local phase_dir="$1"
  local team_mode="${YOLO_TEAM_MODE:-}"
  if [ -z "$team_mode" ]; then
    local config_path
    config_path="$(dirname "$(dirname "$phase_dir")")/config.json"
    if [ -f "$config_path" ]; then
      team_mode=$(jq -r '.team_mode // "task"' "$config_path" 2>/dev/null) || team_mode="task"
    else
      local defaults_path="$_SCRIPT_DIR/../config/defaults.json"
      if [ -f "$defaults_path" ]; then
        team_mode=$(jq -r '.team_mode // "task"' "$defaults_path" 2>/dev/null) || team_mode="task"
      else
        team_mode="task"
      fi
    fi
  fi
  echo "$team_mode"
}

# --- Shared: config timeout override ---
_config_timeout() {
  local default="$1"
  local config_timeout
  config_timeout=$(echo "${_QA_CONFIG_JSON:-{}}" | jq -r '.timeout_seconds // empty' 2>/dev/null) || true
  if [ -n "${config_timeout:-}" ]; then
    echo "$config_timeout"
  else
    echo "$default"
  fi
}

# --- Shared: run test-summary.sh and parse output ---
_run_tests_full() {
  local timeout="$1"
  local test_summary_path pass_count=0 fail_count=0 duration=0 test_result="none"
  test_summary_path=$(command -v test-summary.sh 2>/dev/null) || test_summary_path=""

  if ! command -v bats >/dev/null 2>&1; then
    echo "0 0 0 warn"
    return 0
  fi

  if [ -z "$test_summary_path" ] || ! [ -x "$test_summary_path" ]; then
    echo "0 0 0 warn"
    return 0
  fi

  local start_time end_time
  start_time=$(date +%s)
  local _tmpout
  _tmpout=$(mktemp)
  _run_with_timeout "$timeout" bash "$test_summary_path" > "$_tmpout" 2>&1
  local test_exit=$?
  local test_output
  test_output=$(cat "$_tmpout")
  rm -f "$_tmpout"
  end_time=$(date +%s)
  duration=$((end_time - start_time))

  if [ "$test_exit" -eq 124 ]; then
    echo "0 0 $duration warn"
    return 0
  elif echo "$test_output" | grep -q '^PASS'; then
    pass_count=$(echo "$test_output" | grep '^PASS' | sed 's/PASS (\([0-9]*\) tests)/\1/' | head -1) || pass_count=0
    echo "$pass_count 0 $duration pass"
    return 0
  elif echo "$test_output" | grep -q '^FAIL'; then
    fail_count=$(echo "$test_output" | grep '^FAIL' | sed 's/FAIL (\([0-9]*\)\/\([0-9]*\) failed).*/\1/' | head -1) || fail_count=0
    local total
    total=$(echo "$test_output" | grep '^FAIL' | sed 's/FAIL (\([0-9]*\)\/\([0-9]*\) failed).*/\2/' | head -1) || total=0
    pass_count=$((total - fail_count))
    echo "$pass_count $fail_count $duration fail"
    return 0
  else
    echo "0 0 $duration warn"
    return 0
  fi
}

# ============================================================
# Tier: task — gate_post_task()
# ============================================================
gate_post_task() {
  # Placeholder — migrated in T2
  echo '{"error":"gate_post_task not yet implemented"}' >&2
  exit 1
}

# ============================================================
# Tier: plan — gate_post_plan()
# ============================================================
gate_post_plan() {
  # Placeholder — migrated in T3
  echo '{"error":"gate_post_plan not yet implemented"}' >&2
  exit 1
}

# ============================================================
# Tier: phase — gate_post_phase()
# ============================================================
gate_post_phase() {
  # Placeholder — migrated in T3
  echo '{"error":"gate_post_phase not yet implemented"}' >&2
  exit 1
}

# ============================================================
# Default mode: notification hook (no --tier)
# Exit 2 = block, Exit 0 = allow
# Exit 0 on ANY error (fail-open: never block legitimate work)
# ============================================================
gate_notification_hook() {
  INPUT=$(cat 2>/dev/null) || exit 0

  PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$_SCRIPT_DIR/.." && pwd)}"
  CONFIG_PATH=".yolo-planning/config.json"
  DEFAULTS_PATH="$PLUGIN_ROOT/config/defaults.json"
  RESOLVE_SCRIPT="$_SCRIPT_DIR/resolve-qa-config.sh"

  local QA_CONFIG
  if [ -x "$RESOLVE_SCRIPT" ]; then
    QA_CONFIG=$(bash "$RESOLVE_SCRIPT" "$CONFIG_PATH" "$DEFAULTS_PATH" 2>/dev/null) || QA_CONFIG='{}'
  else
    QA_CONFIG='{}'
  fi

  local POST_TASK_ENABLED
  POST_TASK_ENABLED=$(echo "$QA_CONFIG" | jq -r 'if .post_task == null then true else .post_task end' 2>/dev/null) || POST_TASK_ENABLED='true'

  if [ "$POST_TASK_ENABLED" = "false" ]; then
    exit 0
  fi

  # Structural Check 1: SUMMARY.md completeness
  local SUMMARY_OK=false
  local PLANS_TOTAL=0
  local SUMMARIES_TOTAL=0

  for phase_dir in .yolo-planning/phases/*/; do
    [ -d "$phase_dir" ] || continue
    local PLANS SUMMARIES
    PLANS=$(command ls -1 "$phase_dir"*.plan.jsonl "$phase_dir"*-PLAN.md 2>/dev/null | wc -l | tr -d ' ')
    SUMMARIES=$(command ls -1 "$phase_dir"*.summary.jsonl "$phase_dir"*-SUMMARY.md 2>/dev/null | wc -l | tr -d ' ')
    PLANS_TOTAL=$(( PLANS_TOTAL + PLANS ))
    SUMMARIES_TOTAL=$(( SUMMARIES_TOTAL + SUMMARIES ))
  done

  if [ "$PLANS_TOTAL" -eq 0 ] || [ "$SUMMARIES_TOTAL" -ge "$PLANS_TOTAL" ]; then
    SUMMARY_OK=true
  fi

  local NOW TWO_HOURS
  NOW=$(date +%s 2>/dev/null) || exit 0
  TWO_HOURS=7200

  # Structural Check 2: Commit format
  local FORMAT_MATCH=false
  local RECENT_COMMITS
  RECENT_COMMITS=$(git log --oneline -10 --format="%ct %s" 2>/dev/null) || exit 0
  [ -z "$RECENT_COMMITS" ] && exit 0

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local COMMIT_TS COMMIT_MSG
    COMMIT_TS=$(echo "$line" | cut -d' ' -f1)
    COMMIT_MSG=$(echo "$line" | cut -d' ' -f2-)

    if [ -n "$COMMIT_TS" ] && [ "$COMMIT_TS" -gt 0 ] 2>/dev/null; then
      local AGE=$(( NOW - COMMIT_TS ))
      if [ "$AGE" -le "$TWO_HOURS" ]; then
        if echo "$COMMIT_MSG" | grep -qE '^(feat|fix|refactor|docs|test|chore)\([0-9]{2}-[0-9]{2}\):'; then
          FORMAT_MATCH=true
          break
        fi
      fi
    fi
  done <<< "$RECENT_COMMITS"

  # Decision logic
  if [ "$PLANS_TOTAL" -eq 0 ]; then
    exit 0
  fi

  if [ "$SUMMARY_OK" = true ]; then
    exit 0
  fi

  local SUMMARY_GAP=$(( PLANS_TOTAL - SUMMARIES_TOTAL ))
  if [ "$FORMAT_MATCH" = true ] && [ "$SUMMARY_GAP" -le 1 ]; then
    exit 0
  fi

  echo "QA gate: SUMMARY.md gap detected ($SUMMARIES_TOTAL summaries for $PLANS_TOTAL plans)" >&2
  exit 2
}

# ============================================================
# Main dispatcher
# ============================================================

# Check for --tier flag first (before consuming stdin)
TIER=""
_REMAINING_ARGS=()

for arg in "$@"; do
  if [ "$arg" = "--tier" ]; then
    _TIER_NEXT=true
    continue
  fi
  if [ "${_TIER_NEXT:-}" = "true" ]; then
    TIER="$arg"
    _TIER_NEXT=""
    continue
  fi
  _REMAINING_ARGS+=("$arg")
done

case "$TIER" in
  task)
    _require_jq
    gate_post_task "${_REMAINING_ARGS[@]}"
    ;;
  plan)
    _require_jq
    gate_post_plan "${_REMAINING_ARGS[@]}"
    ;;
  phase)
    _require_jq
    gate_post_phase "${_REMAINING_ARGS[@]}"
    ;;
  "")
    gate_notification_hook
    ;;
  *)
    echo "Error: unknown tier '$TIER'. Valid: task, plan, phase" >&2
    exit 1
    ;;
esac
