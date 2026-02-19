#!/usr/bin/env bash
set -u

# qa-gate.sh — Consolidated QA gate dispatcher.
#
# Modes:
#   (no --tier)         Notification hook: structural checks (exit 0=allow, exit 2=block)
#   --tier task         Post-task gate: test-summary.sh after each task (exit 0=pass/warn, 1=fail)
#   --tier plan         Post-plan gate: summary + full test suite + must_haves (exit 0=pass/warn, 1=fail)
#   --tier phase        Post-phase gate: validate.sh --type gates + all plans + full tests (exit 0=pass/warn, 1=fail)
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
  local PHASE_DIR="" PLAN_ID="" TASK_ID="" SCOPE_MODE=false FILES_LIST="" TIMEOUT=30
  local TESTS_DIR="${TESTS_DIR:-$_SCRIPT_DIR/../tests}"

  while [ $# -gt 0 ]; do
    case "$1" in
      --phase-dir) PHASE_DIR="$2"; shift 2 ;;
      --plan) PLAN_ID="$2"; shift 2 ;;
      --task) TASK_ID="$2"; shift 2 ;;
      --scope) SCOPE_MODE=true; shift ;;
      --files) FILES_LIST="$2"; shift 2 ;;
      --timeout) TIMEOUT="$2"; shift 2 ;;
      *) echo "Unknown flag: $1" >&2; shift ;;
    esac
  done

  if [ -z "$PHASE_DIR" ]; then
    echo '{"error":"--phase-dir is required"}' >&2
    exit 1
  fi

  # Config toggle check
  local enabled
  enabled=$(_load_qa_config "$PHASE_DIR" "post_task")
  if [ "$enabled" = "false" ]; then
    local RESULT_JSON
    RESULT_JSON=$(jq -n \
      --arg gate "skipped" \
      --arg gl "post-task" \
      --arg r "SKIPPED" \
      --arg plan "$PLAN_ID" \
      --arg task "$TASK_ID" \
      --arg dt "$(date +%Y-%m-%d)" \
      '{gate:$gate,gl:$gl,r:$r,plan:$plan,task:$task,tst:{ps:0,fl:0},dur:0,dt:$dt}')
    echo "$RESULT_JSON"
    exit 0
  fi

  TIMEOUT=$(_config_timeout "$TIMEOUT")

  # Team mode detection
  local TEAM_MODE
  TEAM_MODE=$(_detect_team_mode "$PHASE_DIR")

  # Helper: output JSON result and persist
  _task_output_result() {
    local gate="$1" r="$2" pass_count="$3" fail_count="$4" duration="${5:-0}"
    local RESULT_JSON
    RESULT_JSON=$(jq -n \
      --arg gate "$gate" \
      --arg gl "post-task" \
      --arg r "$r" \
      --arg plan "$PLAN_ID" \
      --arg task "$TASK_ID" \
      --argjson ps "$pass_count" \
      --argjson fl "$fail_count" \
      --argjson dur "$duration" \
      --arg dt "$(date +%Y-%m-%d)" \
      --arg tm "$TEAM_MODE" \
      '{gate:$gate,gl:$gl,r:$r,plan:$plan,task:$task,tst:{ps:$ps,fl:$fl},dur:$dur,dt:$dt,tm:$tm}')
    echo "$RESULT_JSON"
    _persist_result "$RESULT_JSON" "$PHASE_DIR"
  }

  # Resolve test-summary.sh path (PATH-based)
  local TEST_SUMMARY_PATH
  TEST_SUMMARY_PATH=$(command -v test-summary.sh 2>/dev/null) || TEST_SUMMARY_PATH=""

  # Fail-open checks
  if ! command -v bats >/dev/null 2>&1; then
    _task_output_result "warn" "WARN" 0 0 0
    exit 0
  fi

  if [ -z "$TEST_SUMMARY_PATH" ] || ! [ -x "$TEST_SUMMARY_PATH" ]; then
    _task_output_result "warn" "WARN" 0 0 0
    exit 0
  fi

  # Scoped test execution (--scope flag)
  if [ "$SCOPE_MODE" = true ]; then
    local FILES_ARRAY=()
    if [ -n "$FILES_LIST" ]; then
      IFS=',' read -ra FILES_ARRAY <<< "$FILES_LIST"
    elif [ -n "$PLAN_ID" ] && [ -n "$TASK_ID" ]; then
      local PLAN_FILE="$PHASE_DIR/${PLAN_ID}.plan.jsonl"
      if [ -f "$PLAN_FILE" ]; then
        while IFS= read -r line; do
          [ -z "$line" ] && continue
          local task_id
          task_id=$(echo "$line" | jq -r '.id // empty' 2>/dev/null) || continue
          if [ "$task_id" = "$TASK_ID" ]; then
            while IFS= read -r f; do
              [ -n "$f" ] && FILES_ARRAY+=("$f")
            done < <(echo "$line" | jq -r '.f[]' 2>/dev/null)
            break
          fi
        done < <(tail -n +2 "$PLAN_FILE")
      fi
    fi

    # Map source files to test files
    local SCOPED_TESTS=()
    for src_file in "${FILES_ARRAY[@]}"; do
      local base_name test_file
      base_name=$(basename "$src_file" .sh)
      test_file=$(find "$TESTS_DIR" -name "${base_name}.bats" 2>/dev/null | head -1) || true
      if [ -n "$test_file" ]; then
        SCOPED_TESTS+=("$test_file")
      fi
    done

    if [ ${#SCOPED_TESTS[@]} -eq 0 ]; then
      _task_output_result "pass" "PASS" 0 0 0
      exit 0
    fi

    local START_TIME END_TIME DURATION TAP_EXIT TAP_OUTPUT
    START_TIME=$(date +%s)
    local _tmpout
    _tmpout=$(mktemp)
    _run_with_timeout "$TIMEOUT" bats --tap "${SCOPED_TESTS[@]}" > "$_tmpout" 2>&1
    TAP_EXIT=$?
    TAP_OUTPUT=$(cat "$_tmpout")
    rm -f "$_tmpout"
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))

    if [ "$TAP_EXIT" -eq 124 ]; then
      _task_output_result "warn" "WARN" 0 0 "$DURATION"
      exit 0
    fi

    local PASS_COUNT FAIL_COUNT
    PASS_COUNT=$(echo "$TAP_OUTPUT" | grep -c '^ok [0-9]' || true)
    FAIL_COUNT=$(echo "$TAP_OUTPUT" | grep -c '^not ok ' || true)

    if [ "$FAIL_COUNT" -gt 0 ]; then
      _task_output_result "fail" "FAIL" "$PASS_COUNT" "$FAIL_COUNT" "$DURATION"
      exit 1
    else
      _task_output_result "pass" "PASS" "$PASS_COUNT" "$FAIL_COUNT" "$DURATION"
      exit 0
    fi
  fi

  # Full test execution (no --scope)
  local START_TIME END_TIME DURATION
  START_TIME=$(date +%s)
  local _tmpout
  _tmpout=$(mktemp)
  _run_with_timeout "$TIMEOUT" bash "$TEST_SUMMARY_PATH" > "$_tmpout" 2>&1
  local TEST_EXIT=$?
  local TEST_OUTPUT
  TEST_OUTPUT=$(cat "$_tmpout")
  rm -f "$_tmpout"
  END_TIME=$(date +%s)
  DURATION=$((END_TIME - START_TIME))

  if [ "$TEST_EXIT" -eq 124 ]; then
    _task_output_result "warn" "WARN" 0 0 "$DURATION"
    exit 0
  fi

  local PASS_COUNT=0 FAIL_COUNT=0

  if echo "$TEST_OUTPUT" | grep -q '^PASS'; then
    PASS_COUNT=$(echo "$TEST_OUTPUT" | grep '^PASS' | sed 's/PASS (\([0-9]*\) tests)/\1/' | head -1) || PASS_COUNT=0
    _task_output_result "pass" "PASS" "$PASS_COUNT" 0 "$DURATION"
    exit 0
  elif echo "$TEST_OUTPUT" | grep -q '^FAIL'; then
    FAIL_COUNT=$(echo "$TEST_OUTPUT" | grep '^FAIL' | sed 's/FAIL (\([0-9]*\)\/\([0-9]*\) failed).*/\1/' | head -1) || FAIL_COUNT=0
    local TOTAL
    TOTAL=$(echo "$TEST_OUTPUT" | grep '^FAIL' | sed 's/FAIL (\([0-9]*\)\/\([0-9]*\) failed).*/\2/' | head -1) || TOTAL=0
    PASS_COUNT=$((TOTAL - FAIL_COUNT))
    _task_output_result "fail" "FAIL" "$PASS_COUNT" "$FAIL_COUNT" "$DURATION"
    exit 1
  else
    _task_output_result "warn" "WARN" 0 0 "$DURATION"
    exit 0
  fi
}

# ============================================================
# Tier: plan — gate_post_plan()
# ============================================================
gate_post_plan() {
  local PHASE_DIR="" PLAN_ID="" TIMEOUT=300

  while [ $# -gt 0 ]; do
    case "$1" in
      --phase-dir) PHASE_DIR="$2"; shift 2 ;;
      --plan) PLAN_ID="$2"; shift 2 ;;
      --timeout) TIMEOUT="$2"; shift 2 ;;
      *) echo "Unknown flag: $1" >&2; shift ;;
    esac
  done

  if [ -z "$PHASE_DIR" ]; then
    echo '{"error":"--phase-dir is required"}' >&2
    exit 1
  fi

  if [ -z "$PLAN_ID" ]; then
    echo '{"error":"--plan is required"}' >&2
    exit 1
  fi

  # Config toggle check
  local enabled
  enabled=$(_load_qa_config "$PHASE_DIR" "post_plan")
  if [ "$enabled" = "false" ]; then
    local RESULT_JSON
    RESULT_JSON=$(jq -n \
      --arg gate "skipped" \
      --arg gl "post-plan" \
      --arg r "SKIPPED" \
      --arg plan "$PLAN_ID" \
      --arg dt "$(date +%Y-%m-%d)" \
      '{gate:$gate,gl:$gl,r:$r,plan:$plan,tst:{ps:0,fl:0},mh:{tr:0,ar:0,kl:0},dur:0,dt:$dt}')
    echo "$RESULT_JSON"
    exit 0
  fi

  TIMEOUT=$(_config_timeout "$TIMEOUT")

  # Team mode detection
  local TEAM_MODE
  TEAM_MODE=$(_detect_team_mode "$PHASE_DIR")

  # Tracking
  local FAILURES=()
  local START_TIME
  START_TIME=$(date +%s)

  # Summary verification
  local SUMMARY_FILE="$PHASE_DIR/${PLAN_ID}.summary.jsonl"
  if [ ! -f "$SUMMARY_FILE" ]; then
    FAILURES+=("summary.jsonl missing for plan $PLAN_ID")
  else
    local STATUS
    STATUS=$(jq -r '.s // ""' "$SUMMARY_FILE" 2>/dev/null) || STATUS=""
    if [ "$STATUS" != "complete" ]; then
      FAILURES+=("summary status is '$STATUS', expected 'complete'")
    fi
  fi

  # Test execution (full suite, no --scope)
  local TEST_SUMMARY_PATH PASS_COUNT=0 FAIL_COUNT=0
  TEST_SUMMARY_PATH=$(command -v test-summary.sh 2>/dev/null) || TEST_SUMMARY_PATH=""

  if ! command -v bats >/dev/null 2>&1; then
    PASS_COUNT=0; FAIL_COUNT=0
  elif [ -z "$TEST_SUMMARY_PATH" ] || ! [ -x "$TEST_SUMMARY_PATH" ]; then
    PASS_COUNT=0; FAIL_COUNT=0
  else
    local _tmpout TEST_EXIT TEST_OUTPUT
    _tmpout=$(mktemp)
    _run_with_timeout "$TIMEOUT" bash "$TEST_SUMMARY_PATH" > "$_tmpout" 2>&1
    TEST_EXIT=$?
    TEST_OUTPUT=$(cat "$_tmpout")
    rm -f "$_tmpout"

    if [ "$TEST_EXIT" -eq 124 ]; then
      PASS_COUNT=0; FAIL_COUNT=0
    elif echo "$TEST_OUTPUT" | grep -q '^PASS'; then
      PASS_COUNT=$(echo "$TEST_OUTPUT" | grep '^PASS' | sed 's/PASS (\([0-9]*\) tests)/\1/' | head -1) || PASS_COUNT=0
      FAIL_COUNT=0
    elif echo "$TEST_OUTPUT" | grep -q '^FAIL'; then
      FAIL_COUNT=$(echo "$TEST_OUTPUT" | grep '^FAIL' | sed 's/FAIL (\([0-9]*\)\/\([0-9]*\) failed).*/\1/' | head -1) || FAIL_COUNT=0
      local TOTAL
      TOTAL=$(echo "$TEST_OUTPUT" | grep '^FAIL' | sed 's/FAIL (\([0-9]*\)\/\([0-9]*\) failed).*/\2/' | head -1) || TOTAL=0
      PASS_COUNT=$((TOTAL - FAIL_COUNT))
      FAILURES+=("test suite failed: $FAIL_COUNT failures")
    fi
  fi

  # Must-have verification
  local TR_COUNT=0 TR_VERIFIED=0 AR_COUNT=0 AR_VERIFIED=0 KL_COUNT=0 KL_VERIFIED=0
  local PLAN_FILE="$PHASE_DIR/${PLAN_ID}.plan.jsonl"

  if [ -f "$PLAN_FILE" ]; then
    local PLAN_HEADER
    PLAN_HEADER=$(head -1 "$PLAN_FILE")

    # Truths (tr)
    TR_COUNT=$(echo "$PLAN_HEADER" | jq '.mh.tr | if type == "array" then length else 0 end' 2>/dev/null) || TR_COUNT=0
    TR_VERIFIED=$TR_COUNT

    # Artifacts (ar) — support strings and objects with .p field
    local AR_TYPE
    AR_TYPE=$(echo "$PLAN_HEADER" | jq -r '.mh.ar | if type == "array" and length > 0 then (.[0] | type) else "none" end' 2>/dev/null) || AR_TYPE="none"

    if [ "$AR_TYPE" = "string" ]; then
      AR_COUNT=$(echo "$PLAN_HEADER" | jq '.mh.ar | length' 2>/dev/null) || AR_COUNT=0
      if [ "$AR_COUNT" -gt 0 ]; then
        for i in $(seq 0 $((AR_COUNT - 1))); do
          local AR_PATH
          AR_PATH=$(echo "$PLAN_HEADER" | jq -r ".mh.ar[$i]" 2>/dev/null) || continue
          if [ -f "$AR_PATH" ]; then
            AR_VERIFIED=$((AR_VERIFIED + 1))
          else
            FAILURES+=("must_have artifact missing: $AR_PATH")
          fi
        done
      fi
    elif [ "$AR_TYPE" = "object" ]; then
      AR_COUNT=$(echo "$PLAN_HEADER" | jq '.mh.ar | length' 2>/dev/null) || AR_COUNT=0
      if [ "$AR_COUNT" -gt 0 ]; then
        for i in $(seq 0 $((AR_COUNT - 1))); do
          local AR_PATH
          AR_PATH=$(echo "$PLAN_HEADER" | jq -r ".mh.ar[$i].p" 2>/dev/null) || continue
          if [ -f "$AR_PATH" ]; then
            AR_VERIFIED=$((AR_VERIFIED + 1))
          else
            FAILURES+=("must_have artifact missing: $AR_PATH")
          fi
        done
      fi
    fi

    # Key links (kl)
    KL_COUNT=$(echo "$PLAN_HEADER" | jq '.mh.kl | if type == "array" then length else 0 end' 2>/dev/null) || KL_COUNT=0
    if [ "$KL_COUNT" -gt 0 ]; then
      for i in $(seq 0 $((KL_COUNT - 1))); do
        local KL_FROM KL_TO
        KL_FROM=$(echo "$PLAN_HEADER" | jq -r ".mh.kl[$i].fr" 2>/dev/null) || continue
        KL_TO=$(echo "$PLAN_HEADER" | jq -r ".mh.kl[$i].to" 2>/dev/null) || continue
        if [ -f "$KL_FROM" ] && [ -f "$KL_TO" ]; then
          KL_VERIFIED=$((KL_VERIFIED + 1))
        else
          FAILURES+=("must_have key_link unresolved: $KL_FROM -> $KL_TO")
        fi
      done
    fi
  fi

  # Result computation
  local END_TIME DURATION GATE RESULT
  END_TIME=$(date +%s)
  DURATION=$((END_TIME - START_TIME))

  if [ ${#FAILURES[@]} -eq 0 ]; then
    GATE="pass"; RESULT="PASS"
  elif [ "$FAIL_COUNT" -eq 0 ] && [ -f "$SUMMARY_FILE" ]; then
    local _summary_status
    _summary_status=$(jq -r '.s // ""' "$SUMMARY_FILE" 2>/dev/null) || _summary_status=""
    if [ "$_summary_status" = "complete" ]; then
      GATE="fail"; RESULT="PARTIAL"
    else
      GATE="fail"; RESULT="FAIL"
    fi
  else
    GATE="fail"; RESULT="FAIL"
  fi

  # JSON output
  local RESULT_JSON
  RESULT_JSON=$(jq -n \
    --arg gate "$GATE" \
    --arg gl "post-plan" \
    --arg r "$RESULT" \
    --arg plan "$PLAN_ID" \
    --argjson ps "$PASS_COUNT" \
    --argjson fl "$FAIL_COUNT" \
    --argjson tr "$TR_VERIFIED" \
    --argjson ar "$AR_VERIFIED" \
    --argjson kl "$KL_VERIFIED" \
    --argjson dur "$DURATION" \
    --arg dt "$(date +%Y-%m-%d)" \
    --arg tm "$TEAM_MODE" \
    '{gate:$gate,gl:$gl,r:$r,plan:$plan,tst:{ps:$ps,fl:$fl},mh:{tr:$tr,ar:$ar,kl:$kl},dur:$dur,dt:$dt,tm:$tm}')
  echo "$RESULT_JSON"

  # Persist result
  _persist_result "$RESULT_JSON" "$PHASE_DIR"

  # Exit
  if [ "$GATE" = "fail" ] && [ "$RESULT" = "FAIL" ]; then
    exit 1
  elif [ "$GATE" = "fail" ] && [ "$RESULT" = "PARTIAL" ]; then
    exit 1
  else
    exit 0
  fi
}

# ============================================================
# Tier: phase — gate_post_phase()
# ============================================================
gate_post_phase() {
  local PHASE_DIR="" TIMEOUT=300

  while [ $# -gt 0 ]; do
    case "$1" in
      --phase-dir) PHASE_DIR="$2"; shift 2 ;;
      --timeout) TIMEOUT="$2"; shift 2 ;;
      *) echo "Unknown flag: $1" >&2; shift ;;
    esac
  done

  if [ -z "$PHASE_DIR" ]; then
    echo '{"error":"--phase-dir is required"}' >&2
    exit 1
  fi

  # Config toggle check
  local enabled
  enabled=$(_load_qa_config "$PHASE_DIR" "post_phase")
  if [ "$enabled" = "false" ]; then
    local RESULT_JSON
    RESULT_JSON=$(jq -n \
      --arg gate "skipped" \
      --arg gl "post-phase" \
      --arg r "SKIPPED" \
      --arg dt "$(date +%Y-%m-%d)" \
      '{gate:$gate,gl:$gl,r:$r,steps:{ps:0,fl:0},tst:{ps:0,fl:0},plans:{complete:0,total:0},dur:0,dt:$dt}')
    echo "$RESULT_JSON"
    exit 0
  fi

  TIMEOUT=$(_config_timeout "$TIMEOUT")

  # Team mode detection
  local TEAM_MODE
  TEAM_MODE=$(_detect_team_mode "$PHASE_DIR")

  # Tracking
  local FAILURES=()
  local START_TIME
  START_TIME=$(date +%s)

  # Plan completeness check
  local PLAN_FILES TOTAL_PLANS=0 COMPLETE_PLANS=0
  PLAN_FILES=$(ls "$PHASE_DIR"/*.plan.jsonl 2>/dev/null) || PLAN_FILES=""

  if [ -n "$PLAN_FILES" ]; then
    while IFS= read -r plan_file; do
      [ -z "$plan_file" ] && continue
      TOTAL_PLANS=$((TOTAL_PLANS + 1))

      local _plan_id
      _plan_id=$(basename "$plan_file" .plan.jsonl)

      local SUMMARY_FILE="$PHASE_DIR/${_plan_id}.summary.jsonl"
      if [ -f "$SUMMARY_FILE" ]; then
        local _status
        _status=$(jq -r '.s // ""' "$SUMMARY_FILE" 2>/dev/null) || _status=""
        if [ "$_status" = "complete" ]; then
          COMPLETE_PLANS=$((COMPLETE_PLANS + 1))
        else
          FAILURES+=("plan $_plan_id summary status is '$_status', expected 'complete'")
        fi
      else
        FAILURES+=("plan $_plan_id missing summary.jsonl")
      fi
    done <<< "$PLAN_FILES"
  fi

  if [ "$TOTAL_PLANS" -eq 0 ]; then
    FAILURES+=("no plan files found in phase directory")
  fi

  if [ "$COMPLETE_PLANS" -lt "$TOTAL_PLANS" ]; then
    FAILURES+=("incomplete plans: $COMPLETE_PLANS/$TOTAL_PLANS complete")
  fi

  # Gate validation: check PATH for validate-gates.sh first (supports test mocking),
  # fall back to validate.sh --type gates in scripts dir
  local _VALIDATE_CMD="" _VALIDATE_USE_TYPE=false
  _VALIDATE_CMD=$(command -v validate-gates.sh 2>/dev/null) || _VALIDATE_CMD=""
  if [ -z "$_VALIDATE_CMD" ] || ! [ -x "$_VALIDATE_CMD" ]; then
    local _validate_sh_path
    _validate_sh_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/validate.sh"
    if [ -x "$_validate_sh_path" ]; then
      _VALIDATE_CMD="$_validate_sh_path"
      _VALIDATE_USE_TYPE=true
    fi
  fi

  local STEPS_PASSED=0 STEPS_FAILED=0
  local STEPS=(critique research architecture planning design_review test_authoring implementation code_review qa security signoff)

  if [ -n "$_VALIDATE_CMD" ] && [ -x "$_VALIDATE_CMD" ]; then
    for step in "${STEPS[@]}"; do
      local step_exit=0 result gate_status=""
      if [ "$_VALIDATE_USE_TYPE" = true ]; then
        result=$(bash "$_VALIDATE_CMD" --type gates --step "$step" --phase-dir "$PHASE_DIR" 2>/dev/null) || step_exit=$?
      else
        result=$(bash "$_VALIDATE_CMD" --step "$step" --phase-dir "$PHASE_DIR" 2>/dev/null) || step_exit=$?
      fi
      if [ -n "$result" ]; then
        gate_status=$(echo "$result" | jq -r '.gate // ""' 2>/dev/null) || gate_status=""
      fi
      if [ "$gate_status" = "pass" ] || { [ -z "$gate_status" ] && [ "$step_exit" -eq 0 ]; }; then
        STEPS_PASSED=$((STEPS_PASSED + 1))
      elif [ "$step_exit" -ne 0 ] || [ "$gate_status" = "fail" ]; then
        STEPS_FAILED=$((STEPS_FAILED + 1))
        FAILURES+=("gate validation failed for step: $step")
      fi
    done
  fi

  # Test execution (full suite)
  local TEST_SUMMARY_PATH PASS_COUNT=0 FAIL_COUNT=0
  TEST_SUMMARY_PATH=$(command -v test-summary.sh 2>/dev/null) || TEST_SUMMARY_PATH=""

  if ! command -v bats >/dev/null 2>&1; then
    PASS_COUNT=0; FAIL_COUNT=0
  elif [ -z "$TEST_SUMMARY_PATH" ] || ! [ -x "$TEST_SUMMARY_PATH" ]; then
    PASS_COUNT=0; FAIL_COUNT=0
  else
    local _tmpout TEST_EXIT TEST_OUTPUT
    _tmpout=$(mktemp)
    _run_with_timeout "$TIMEOUT" bash "$TEST_SUMMARY_PATH" > "$_tmpout" 2>&1
    TEST_EXIT=$?
    TEST_OUTPUT=$(cat "$_tmpout")
    rm -f "$_tmpout"

    if [ "$TEST_EXIT" -eq 124 ]; then
      PASS_COUNT=0; FAIL_COUNT=0
    elif echo "$TEST_OUTPUT" | grep -q '^PASS'; then
      PASS_COUNT=$(echo "$TEST_OUTPUT" | grep '^PASS' | sed 's/PASS (\([0-9]*\) tests)/\1/' | head -1) || PASS_COUNT=0
      FAIL_COUNT=0
    elif echo "$TEST_OUTPUT" | grep -q '^FAIL'; then
      FAIL_COUNT=$(echo "$TEST_OUTPUT" | grep '^FAIL' | sed 's/FAIL (\([0-9]*\)\/\([0-9]*\) failed).*/\1/' | head -1) || FAIL_COUNT=0
      local TOTAL
      TOTAL=$(echo "$TEST_OUTPUT" | grep '^FAIL' | sed 's/FAIL (\([0-9]*\)\/\([0-9]*\) failed).*/\2/' | head -1) || TOTAL=0
      PASS_COUNT=$((TOTAL - FAIL_COUNT))
      FAILURES+=("test suite failed: $FAIL_COUNT failures")
    fi
  fi

  # Result computation
  local END_TIME DURATION GATE RESULT PHASE_NUM
  END_TIME=$(date +%s)
  DURATION=$((END_TIME - START_TIME))
  PHASE_NUM=$(basename "$PHASE_DIR" | cut -d- -f1)

  if [ ${#FAILURES[@]} -eq 0 ]; then
    GATE="pass"; RESULT="PASS"
  else
    GATE="fail"; RESULT="FAIL"
  fi

  # JSON output
  local RESULT_JSON
  RESULT_JSON=$(jq -n \
    --arg gate "$GATE" \
    --arg gl "post-phase" \
    --arg r "$RESULT" \
    --arg ph "$PHASE_NUM" \
    --argjson sps "$STEPS_PASSED" \
    --argjson sfl "$STEPS_FAILED" \
    --argjson ps "$PASS_COUNT" \
    --argjson fl "$FAIL_COUNT" \
    --argjson complete "$COMPLETE_PLANS" \
    --argjson total "$TOTAL_PLANS" \
    --argjson dur "$DURATION" \
    --arg dt "$(date +%Y-%m-%d)" \
    --arg tm "$TEAM_MODE" \
    '{gate:$gate,gl:$gl,r:$r,ph:$ph,steps:{ps:$sps,fl:$sfl},tst:{ps:$ps,fl:$fl},plans:{complete:$complete,total:$total},dur:$dur,dt:$dt,tm:$tm}')
  echo "$RESULT_JSON"

  # Persist result
  _persist_result "$RESULT_JSON" "$PHASE_DIR"

  # Exit
  if [ "$GATE" = "fail" ]; then
    exit 1
  else
    exit 0
  fi
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
