#!/usr/bin/env bash
set -u

# qa-gate-post-phase.sh -- Post-phase QA gate: full system verification.
# Runs validate-gates.sh for all workflow steps, checks all plans complete,
# runs full test suite. Produces structured JSON result.
# Fail-open: missing infrastructure = warn, not block.
# Usage: qa-gate-post-phase.sh --phase-dir <path> [--timeout N]
# Exit: 0 on pass/warn, 1 on fail.

# --- jq dependency check ---
if ! command -v jq &>/dev/null; then
  echo '{"error":"jq is required but not installed. Install: brew install jq (macOS) / apt install jq (Linux)"}' >&2
  exit 1
fi

# --- Resolve paths ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Constants ---
DEFAULT_TIMEOUT=300

# --- Timeout wrapper (handles missing timeout command on macOS) ---
run_with_timeout() {
  local secs="$1"; shift
  if command -v timeout &>/dev/null; then
    timeout "$secs" "$@"
    return $?
  elif command -v gtimeout &>/dev/null; then
    gtimeout "$secs" "$@"
    return $?
  else
    # Bash-based timeout fallback using background process
    "$@" &
    local cmd_pid=$!
    local elapsed=0
    while kill -0 "$cmd_pid" 2>/dev/null; do
      if [ "$elapsed" -ge "$secs" ]; then
        # Kill children first to prevent orphans holding stdout open
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

# --- Lock helpers (copied from git-commit-serialized.sh) ---

has_flock() {
  command -v flock &>/dev/null
}

acquire_lock_flock() {
  exec 200>"$LOCK_FILE" && flock -n 200
  return $?
}

acquire_lock_mkdir() {
  mkdir "${LOCK_FILE}.d" 2>/dev/null
  return $?
}

release_lock_mkdir() {
  rmdir "${LOCK_FILE}.d" 2>/dev/null || true
}

sleep_ms() {
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

# --- Arg parsing ---
PHASE_DIR=""
TIMEOUT="$DEFAULT_TIMEOUT"

while [ $# -gt 0 ]; do
  case "$1" in
    --phase-dir) PHASE_DIR="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    *) echo "Unknown flag: $1" >&2; shift ;;
  esac
done

# Validate required args
if [ -z "$PHASE_DIR" ]; then
  echo '{"error":"--phase-dir is required"}' >&2
  exit 1
fi

# --- Config toggle check (04-10 integration) ---
QA_CONFIG_SCRIPT=$(command -v resolve-qa-config.sh 2>/dev/null) || QA_CONFIG_SCRIPT="$SCRIPT_DIR/resolve-qa-config.sh"
if [ -x "$QA_CONFIG_SCRIPT" ]; then
  _cfg_path="$(dirname "$(dirname "$PHASE_DIR")")/config.json"
  _def_path="$SCRIPT_DIR/../config/defaults.json"
  QA_CONFIG_JSON=$("$QA_CONFIG_SCRIPT" "$_cfg_path" "$_def_path" 2>/dev/null) || QA_CONFIG_JSON="{}"
  # Note: jq '//' treats false as falsy, so 'false // true' = true. Use explicit null check.
  POST_PHASE_ENABLED=$(echo "$QA_CONFIG_JSON" | jq -r 'if .post_phase == null then true else .post_phase end' 2>/dev/null) || POST_PHASE_ENABLED="true"
  if [ "$POST_PHASE_ENABLED" = "false" ]; then
    RESULT_JSON=$(jq -n \
      --arg gate "skipped" \
      --arg gl "post-phase" \
      --arg r "SKIPPED" \
      --arg dt "$(date +%Y-%m-%d)" \
      '{gate:$gate,gl:$gl,r:$r,steps:{ps:0,fl:0},tst:{ps:0,fl:0},plans:{complete:0,total:0},dur:0,dt:$dt}')
    echo "$RESULT_JSON"
    exit 0
  fi
  # Check for config-provided timeout
  CONFIG_TIMEOUT=$(echo "$QA_CONFIG_JSON" | jq -r '.timeout_seconds // empty' 2>/dev/null) || true
  if [ -n "${CONFIG_TIMEOUT:-}" ]; then
    TIMEOUT="$CONFIG_TIMEOUT"
  fi
fi

# --- Team mode detection ---
TEAM_MODE="${YOLO_TEAM_MODE:-}"
if [ -z "$TEAM_MODE" ]; then
  CONFIG_PATH="$(dirname "$(dirname "$PHASE_DIR")")/config.json"
  if [ -f "$CONFIG_PATH" ]; then
    TEAM_MODE=$(jq -r '.team_mode // "task"' "$CONFIG_PATH" 2>/dev/null) || TEAM_MODE="task"
  else
    DEFAULTS_PATH="$SCRIPT_DIR/../config/defaults.json"
    if [ -f "$DEFAULTS_PATH" ]; then
      TEAM_MODE=$(jq -r '.team_mode // "task"' "$DEFAULTS_PATH" 2>/dev/null) || TEAM_MODE="task"
    else
      TEAM_MODE="task"
    fi
  fi
fi

# --- Tracking ---
FAILURES=()
START_TIME=$(date +%s)

# --- (3) Plan completeness check ---
PLAN_FILES=$(ls "$PHASE_DIR"/*.plan.jsonl 2>/dev/null) || PLAN_FILES=""
TOTAL_PLANS=0
COMPLETE_PLANS=0

if [ -n "$PLAN_FILES" ]; then
  while IFS= read -r plan_file; do
    [ -z "$plan_file" ] && continue
    TOTAL_PLANS=$((TOTAL_PLANS + 1))

    # Extract plan_id from filename (e.g., 04-07.plan.jsonl -> 04-07)
    _plan_id=$(basename "$plan_file" .plan.jsonl)

    # Check summary exists with s:complete
    SUMMARY_FILE="$PHASE_DIR/${_plan_id}.summary.jsonl"
    if [ -f "$SUMMARY_FILE" ]; then
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

# --- (4) Gate validation via validate-gates.sh ---
VALIDATE_GATES_PATH=$(command -v validate-gates.sh 2>/dev/null) || VALIDATE_GATES_PATH=""
STEPS_PASSED=0
STEPS_FAILED=0

# 11-step workflow (research step may not be recognized by validate-gates.sh yet)
STEPS=(critique research architecture planning design_review test_authoring implementation code_review qa security signoff)

if [ -n "$VALIDATE_GATES_PATH" ] && [ -x "$VALIDATE_GATES_PATH" ]; then
  for step in "${STEPS[@]}"; do
    step_exit=0
    result=$(bash "$VALIDATE_GATES_PATH" --step "$step" --phase-dir "$PHASE_DIR" 2>/dev/null) || step_exit=$?
    # Use exit code as primary signal: 0=pass, 1=fail
    # Try to parse JSON gate field as secondary signal, fall back to exit code
    gate_status=""
    if [ -n "$result" ]; then
      gate_status=$(echo "$result" | jq -r '.gate // ""' 2>/dev/null) || gate_status=""
    fi
    if [ "$gate_status" = "pass" ] || { [ -z "$gate_status" ] && [ "$step_exit" -eq 0 ]; }; then
      STEPS_PASSED=$((STEPS_PASSED + 1))
    elif [ "$step_exit" -ne 0 ] || [ "$gate_status" = "fail" ]; then
      STEPS_FAILED=$((STEPS_FAILED + 1))
      FAILURES+=("gate validation failed for step: $step")
    fi
    # Unknown/unrecognized step output with exit 0 -- skip gracefully
  done
fi

# --- (5) Test execution (full suite) ---
TEST_SUMMARY_PATH=$(command -v test-summary.sh 2>/dev/null) || TEST_SUMMARY_PATH=""
PASS_COUNT=0
FAIL_COUNT=0

if ! command -v bats >/dev/null 2>&1; then
  # Fail-open on missing bats
  PASS_COUNT=0
  FAIL_COUNT=0
elif [ -z "$TEST_SUMMARY_PATH" ] || ! [ -x "$TEST_SUMMARY_PATH" ]; then
  # Fail-open on missing test-summary.sh
  PASS_COUNT=0
  FAIL_COUNT=0
else
  _tmpout=$(mktemp)
  run_with_timeout "$TIMEOUT" bash "$TEST_SUMMARY_PATH" > "$_tmpout" 2>&1
  TEST_EXIT=$?
  TEST_OUTPUT=$(cat "$_tmpout")
  rm -f "$_tmpout"

  if [ "$TEST_EXIT" -eq 124 ]; then
    # Timeout -- warn, fail-open
    PASS_COUNT=0
    FAIL_COUNT=0
  elif echo "$TEST_OUTPUT" | grep -q '^PASS'; then
    PASS_COUNT=$(echo "$TEST_OUTPUT" | grep '^PASS' | sed 's/PASS (\([0-9]*\) tests)/\1/' | head -1) || PASS_COUNT=0
    FAIL_COUNT=0
  elif echo "$TEST_OUTPUT" | grep -q '^FAIL'; then
    FAIL_COUNT=$(echo "$TEST_OUTPUT" | grep '^FAIL' | sed 's/FAIL (\([0-9]*\)\/\([0-9]*\) failed).*/\1/' | head -1) || FAIL_COUNT=0
    TOTAL=$(echo "$TEST_OUTPUT" | grep '^FAIL' | sed 's/FAIL (\([0-9]*\)\/\([0-9]*\) failed).*/\2/' | head -1) || TOTAL=0
    PASS_COUNT=$((TOTAL - FAIL_COUNT))
    FAILURES+=("test suite failed: $FAIL_COUNT failures")
  fi
fi

# --- (6) Result computation ---
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Extract phase number from directory name
PHASE_NUM=$(basename "$PHASE_DIR" | cut -d- -f1)

if [ ${#FAILURES[@]} -eq 0 ]; then
  GATE="pass"
  RESULT="PASS"
else
  GATE="fail"
  RESULT="FAIL"
fi

# --- (7) JSON output ---
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

# --- (8) Result persistence via flock ---
LOCK_FILE="$PHASE_DIR/.qa-gate-results.lock"
RESULTS_FILE="$PHASE_DIR/.qa-gate-results.jsonl"
MAX_RETRIES=5
BASE_DELAY_MS=200

USE_FLOCK=false
if has_flock; then
  USE_FLOCK=true
fi

for i in $(seq 0 $((MAX_RETRIES - 1))); do
  lock_acquired=false
  if [ "$USE_FLOCK" = true ]; then
    if acquire_lock_flock; then
      lock_acquired=true
    fi
  else
    if acquire_lock_mkdir; then
      lock_acquired=true
    fi
  fi

  if [ "$lock_acquired" = true ]; then
    echo "$RESULT_JSON" | jq -c '.' >> "$RESULTS_FILE"
    if [ "$USE_FLOCK" = false ]; then
      release_lock_mkdir
    fi
    break
  fi

  delay=$((BASE_DELAY_MS * (1 << i)))
  sleep_ms "$delay"
done

# --- (9) Exit ---
if [ "$GATE" = "fail" ]; then
  exit 1
else
  exit 0
fi
