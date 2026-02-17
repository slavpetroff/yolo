#!/usr/bin/env bash
set -u

# qa-gate-post-task.sh -- Post-task QA gate: runs test-summary.sh after each task batch.
# Produces structured JSON result. Fail-open: missing infrastructure = warn, not block.
# Usage: qa-gate-post-task.sh --phase-dir <path> [--plan ID] [--task ID] [--timeout N] [--scope] [--files f1,f2]
# Exit: 0 on pass/warn, 1 on fail.

# --- jq dependency check ---
if ! command -v jq &>/dev/null; then
  echo '{"error":"jq is required but not installed. Install: brew install jq (macOS) / apt install jq (Linux)"}' >&2
  exit 1
fi

# --- Resolve paths ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TESTS_DIR="${TESTS_DIR:-$SCRIPT_DIR/../tests}"

# --- Constants ---
DEFAULT_TIMEOUT=30

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
PLAN_ID=""
TASK_ID=""
SCOPE_MODE=false
FILES_LIST=""
TIMEOUT="$DEFAULT_TIMEOUT"

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

# Validate required args
if [ -z "$PHASE_DIR" ]; then
  echo '{"error":"--phase-dir is required"}' >&2
  exit 1
fi

# --- Config toggle check (04-10 integration) ---
QA_CONFIG_SCRIPT=$(command -v resolve-qa-config.sh 2>/dev/null) || QA_CONFIG_SCRIPT="$SCRIPT_DIR/resolve-qa-config.sh"
if [ -x "$QA_CONFIG_SCRIPT" ]; then
  QA_CONFIG_JSON=$("$QA_CONFIG_SCRIPT" 2>/dev/null) || QA_CONFIG_JSON="{}"
  # Note: jq '//' treats false as falsy, so 'false // true' = true. Use explicit null check.
  POST_TASK_ENABLED=$(echo "$QA_CONFIG_JSON" | jq -r 'if .post_task == null then true else .post_task end' 2>/dev/null) || POST_TASK_ENABLED="true"
  if [ "$POST_TASK_ENABLED" = "false" ]; then
    RESULT_JSON=$(jq -n \
      --arg gate "skipped" \
      --arg level "post-task" \
      --arg r "SKIPPED" \
      --arg plan "$PLAN_ID" \
      --arg task "$TASK_ID" \
      --arg dt "$(date +%Y-%m-%d)" \
      '{gate:$gate,level:$level,r:$r,plan:$plan,task:$task,tst:{ps:0,fl:0},dur:0,dt:$dt}')
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
    # Fallback to config/defaults.json
    DEFAULTS_PATH="$SCRIPT_DIR/../config/defaults.json"
    if [ -f "$DEFAULTS_PATH" ]; then
      TEAM_MODE=$(jq -r '.team_mode // "task"' "$DEFAULTS_PATH" 2>/dev/null) || TEAM_MODE="task"
    else
      TEAM_MODE="task"
    fi
  fi
fi

# --- Helper: output JSON result ---
output_result() {
  local gate="$1" r="$2" pass_count="$3" fail_count="$4" duration="${5:-0}"
  RESULT_JSON=$(jq -n \
    --arg gate "$gate" \
    --arg level "post-task" \
    --arg r "$r" \
    --arg plan "$PLAN_ID" \
    --arg task "$TASK_ID" \
    --argjson ps "$pass_count" \
    --argjson fl "$fail_count" \
    --argjson dur "$duration" \
    --arg dt "$(date +%Y-%m-%d)" \
    --arg tm "$TEAM_MODE" \
    '{gate:$gate,level:$level,r:$r,plan:$plan,task:$task,tst:{ps:$ps,fl:$fl},dur:$dur,dt:$dt,tm:$tm}')
  echo "$RESULT_JSON"

  # --- Result persistence via flock ---
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
      return 0
    fi

    delay=$((BASE_DELAY_MS * (1 << i)))
    sleep_ms "$delay"
  done

  # Failed to acquire lock -- non-fatal, just warn on stderr
  echo "WARN: Could not acquire lock for results file after $MAX_RETRIES retries" >&2
  return 0
}

# --- Resolve test-summary.sh path ---
# PATH-based resolution only. Callers must ensure scripts/ is in PATH for production use.
# Test mocking works by prepending MOCK_DIR to PATH.
TEST_SUMMARY_PATH=$(command -v test-summary.sh 2>/dev/null) || TEST_SUMMARY_PATH=""

# --- Fail-open checks ---
if ! command -v bats >/dev/null 2>&1; then
  output_result "warn" "WARN" 0 0 0
  exit 0
fi

if [ -z "$TEST_SUMMARY_PATH" ] || ! [ -x "$TEST_SUMMARY_PATH" ]; then
  output_result "warn" "WARN" 0 0 0
  exit 0
fi

# --- Scoped test execution (--scope flag) ---
if [ "$SCOPE_MODE" = true ]; then
  # Determine relevant files
  FILES_ARRAY=()
  if [ -n "$FILES_LIST" ]; then
    IFS=',' read -ra FILES_ARRAY <<< "$FILES_LIST"
  elif [ -n "$PLAN_ID" ] && [ -n "$TASK_ID" ]; then
    PLAN_FILE="$PHASE_DIR/${PLAN_ID}.plan.jsonl"
    if [ -f "$PLAN_FILE" ]; then
      while IFS= read -r line; do
        [ -z "$line" ] && continue
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
  SCOPED_TESTS=()
  for src_file in "${FILES_ARRAY[@]}"; do
    base_name=$(basename "$src_file" .sh)
    test_file=$(find "$TESTS_DIR" -name "${base_name}.bats" 2>/dev/null | head -1) || true
    if [ -n "$test_file" ]; then
      SCOPED_TESTS+=("$test_file")
    fi
  done

  # No matching tests found
  if [ ${#SCOPED_TESTS[@]} -eq 0 ]; then
    output_result "pass" "PASS" 0 0 0
    exit 0
  fi

  # Run bats directly on scoped test files
  START_TIME=$(date +%s)
  TAP_OUTPUT=$(run_with_timeout "$TIMEOUT" bats --tap "${SCOPED_TESTS[@]}" 2>&1) || true
  TAP_EXIT=$?
  END_TIME=$(date +%s)
  DURATION=$((END_TIME - START_TIME))

  if [ "$TAP_EXIT" -eq 124 ]; then
    output_result "warn" "WARN" 0 0 "$DURATION"
    exit 0
  fi

  PASS_COUNT=$(echo "$TAP_OUTPUT" | grep -c '^ok [0-9]' || true)
  FAIL_COUNT=$(echo "$TAP_OUTPUT" | grep -c '^not ok ' || true)

  if [ "$FAIL_COUNT" -gt 0 ]; then
    output_result "fail" "FAIL" "$PASS_COUNT" "$FAIL_COUNT" "$DURATION"
    exit 1
  else
    output_result "pass" "PASS" "$PASS_COUNT" "$FAIL_COUNT" "$DURATION"
    exit 0
  fi
fi

# --- Full test execution (no --scope) ---
START_TIME=$(date +%s)
TEST_OUTPUT=$(run_with_timeout "$TIMEOUT" bash "$TEST_SUMMARY_PATH" 2>&1) || true
TEST_EXIT=$?
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Handle timeout (exit 124)
if [ "$TEST_EXIT" -eq 124 ]; then
  output_result "warn" "WARN" 0 0 "$DURATION"
  exit 0
fi

# Parse test-summary.sh output
PASS_COUNT=0
FAIL_COUNT=0

if echo "$TEST_OUTPUT" | grep -q '^PASS'; then
  # "PASS (10 tests)" -> extract 10
  PASS_COUNT=$(echo "$TEST_OUTPUT" | grep '^PASS' | sed 's/PASS (\([0-9]*\) tests)/\1/' | head -1) || PASS_COUNT=0
  output_result "pass" "PASS" "$PASS_COUNT" 0 "$DURATION"
  exit 0
elif echo "$TEST_OUTPUT" | grep -q '^FAIL'; then
  # "FAIL (2/10 failed)" -> extract 2 and 10
  FAIL_COUNT=$(echo "$TEST_OUTPUT" | grep '^FAIL' | sed 's/FAIL (\([0-9]*\)\/\([0-9]*\) failed).*/\1/' | head -1) || FAIL_COUNT=0
  TOTAL=$(echo "$TEST_OUTPUT" | grep '^FAIL' | sed 's/FAIL (\([0-9]*\)\/\([0-9]*\) failed).*/\2/' | head -1) || TOTAL=0
  PASS_COUNT=$((TOTAL - FAIL_COUNT))
  output_result "fail" "FAIL" "$PASS_COUNT" "$FAIL_COUNT" "$DURATION"
  exit 1
else
  # Unexpected output -- warn, fail-open
  output_result "warn" "WARN" 0 0 "$DURATION"
  exit 0
fi
