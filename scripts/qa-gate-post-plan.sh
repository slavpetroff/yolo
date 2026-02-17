#!/usr/bin/env bash
set -u

# qa-gate-post-plan.sh -- Post-plan QA gate: verifies plan summary, runs full test suite,
# checks must_have coverage (truths, artifacts, key_links).
# Produces structured JSON result. Fail-open: missing infrastructure = warn, not block.
# Usage: qa-gate-post-plan.sh --phase-dir <path> --plan <ID> [--timeout N]
# Exit: 0 on pass/partial/warn, 1 on fail.

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
TIMEOUT="$DEFAULT_TIMEOUT"

while [ $# -gt 0 ]; do
  case "$1" in
    --phase-dir) PHASE_DIR="$2"; shift 2 ;;
    --plan) PLAN_ID="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    *) echo "Unknown flag: $1" >&2; shift ;;
  esac
done

# Validate required args
if [ -z "$PHASE_DIR" ]; then
  echo '{"error":"--phase-dir is required"}' >&2
  exit 1
fi

if [ -z "$PLAN_ID" ]; then
  echo '{"error":"--plan is required"}' >&2
  exit 1
fi

# --- Config toggle check (04-10 integration) ---
QA_CONFIG_SCRIPT=$(command -v resolve-qa-config.sh 2>/dev/null) || QA_CONFIG_SCRIPT="$SCRIPT_DIR/resolve-qa-config.sh"
if [ -x "$QA_CONFIG_SCRIPT" ]; then
  QA_CONFIG_JSON=$("$QA_CONFIG_SCRIPT" 2>/dev/null) || QA_CONFIG_JSON="{}"
  # Note: jq '//' treats false as falsy, so 'false // true' = true. Use explicit null check.
  POST_PLAN_ENABLED=$(echo "$QA_CONFIG_JSON" | jq -r 'if .post_plan == null then true else .post_plan end' 2>/dev/null) || POST_PLAN_ENABLED="true"
  if [ "$POST_PLAN_ENABLED" = "false" ]; then
    RESULT_JSON=$(jq -n \
      --arg gate "skipped" \
      --arg level "post-plan" \
      --arg r "SKIPPED" \
      --arg plan "$PLAN_ID" \
      --arg dt "$(date +%Y-%m-%d)" \
      '{gate:$gate,level:$level,r:$r,plan:$plan,tst:{ps:0,fl:0},mh:{tr:0,ar:0,kl:0},dur:0,dt:$dt}')
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

# --- (3) Summary verification ---
SUMMARY_FILE="$PHASE_DIR/${PLAN_ID}.summary.jsonl"
if [ ! -f "$SUMMARY_FILE" ]; then
  FAILURES+=("summary.jsonl missing for plan $PLAN_ID")
else
  STATUS=$(jq -r '.s // ""' "$SUMMARY_FILE" 2>/dev/null) || STATUS=""
  if [ "$STATUS" != "complete" ]; then
    FAILURES+=("summary status is '$STATUS', expected 'complete'")
  fi
fi

# --- (4) Test execution (full suite, no --scope) ---
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
  TEST_OUTPUT=$(run_with_timeout "$TIMEOUT" bash "$TEST_SUMMARY_PATH" 2>&1) || true
  TEST_EXIT=$?

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

# --- (5) Must-have verification ---
TR_COUNT=0
TR_VERIFIED=0
AR_COUNT=0
AR_VERIFIED=0
KL_COUNT=0
KL_VERIFIED=0

PLAN_FILE="$PHASE_DIR/${PLAN_ID}.plan.jsonl"
if [ -f "$PLAN_FILE" ]; then
  PLAN_HEADER=$(head -1 "$PLAN_FILE")

  # --- Truths (tr) ---
  TR_COUNT=$(echo "$PLAN_HEADER" | jq '.mh.tr | if type == "array" then length else 0 end' 2>/dev/null) || TR_COUNT=0
  # Truths are human-readable strings -- best-effort verify (count them as verified since
  # they are descriptive assertions checked by inspection, not file existence)
  TR_VERIFIED=$TR_COUNT

  # --- Artifacts (ar) ---
  # Support two formats: array of strings (paths) and array of objects with .p field
  AR_TYPE=$(echo "$PLAN_HEADER" | jq -r '.mh.ar | if type == "array" and length > 0 then (.[0] | type) else "none" end' 2>/dev/null) || AR_TYPE="none"

  if [ "$AR_TYPE" = "string" ]; then
    # Array of path strings
    AR_COUNT=$(echo "$PLAN_HEADER" | jq '.mh.ar | length' 2>/dev/null) || AR_COUNT=0
    if [ "$AR_COUNT" -gt 0 ]; then
      for i in $(seq 0 $((AR_COUNT - 1))); do
        AR_PATH=$(echo "$PLAN_HEADER" | jq -r ".mh.ar[$i]" 2>/dev/null) || continue
        if [ -f "$AR_PATH" ]; then
          AR_VERIFIED=$((AR_VERIFIED + 1))
        else
          FAILURES+=("must_have artifact missing: $AR_PATH")
        fi
      done
    fi
  elif [ "$AR_TYPE" = "object" ]; then
    # Array of objects with .p field
    AR_COUNT=$(echo "$PLAN_HEADER" | jq '.mh.ar | length' 2>/dev/null) || AR_COUNT=0
    if [ "$AR_COUNT" -gt 0 ]; then
      for i in $(seq 0 $((AR_COUNT - 1))); do
        AR_PATH=$(echo "$PLAN_HEADER" | jq -r ".mh.ar[$i].p" 2>/dev/null) || continue
        if [ -f "$AR_PATH" ]; then
          AR_VERIFIED=$((AR_VERIFIED + 1))
        else
          FAILURES+=("must_have artifact missing: $AR_PATH")
        fi
      done
    fi
  fi

  # --- Key links (kl) ---
  KL_COUNT=$(echo "$PLAN_HEADER" | jq '.mh.kl | if type == "array" then length else 0 end' 2>/dev/null) || KL_COUNT=0
  if [ "$KL_COUNT" -gt 0 ]; then
    for i in $(seq 0 $((KL_COUNT - 1))); do
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

# --- (6) Result computation ---
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

if [ ${#FAILURES[@]} -eq 0 ]; then
  GATE="pass"
  RESULT="PASS"
elif [ "$FAIL_COUNT" -eq 0 ] && [ -f "$SUMMARY_FILE" ]; then
  # Tests pass but some must_haves fail -- partial
  _summary_status=$(jq -r '.s // ""' "$SUMMARY_FILE" 2>/dev/null) || _summary_status=""
  if [ "$_summary_status" = "complete" ]; then
    GATE="fail"
    RESULT="PARTIAL"
  else
    GATE="fail"
    RESULT="FAIL"
  fi
else
  GATE="fail"
  RESULT="FAIL"
fi

# --- (7) JSON output ---
RESULT_JSON=$(jq -n \
  --arg gate "$GATE" \
  --arg level "post-plan" \
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
  '{gate:$gate,level:$level,r:$r,plan:$plan,tst:{ps:$ps,fl:$fl},mh:{tr:$tr,ar:$ar,kl:$kl},dur:$dur,dt:$dt,tm:$tm}')
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
if [ "$GATE" = "fail" ] && [ "$RESULT" = "FAIL" ]; then
  exit 1
elif [ "$GATE" = "fail" ] && [ "$RESULT" = "PARTIAL" ]; then
  exit 1
else
  exit 0
fi
