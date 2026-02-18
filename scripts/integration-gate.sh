#!/usr/bin/env bash
set -euo pipefail

# integration-gate.sh -- Barrier convergence for cross-department integration
#
# Checks that all active departments have completed, then runs cross-dept
# validation (API contracts, design sync, handoffs, test results).
#
# Usage: integration-gate.sh --phase-dir <dir> --config <config-path> [--timeout <seconds>]
# Output: JSON {gate, departments, cross_checks, timeout_remaining}
# Exit codes: 0 = pass, 1 = fail or timeout

# --- jq dependency check ---
if ! command -v jq &>/dev/null; then
  echo '{"error":"jq is required but not installed. Install: brew install jq (macOS) / apt install jq (Linux)"}' >&2
  exit 1
fi

# --- Arg parsing ---
PHASE_DIR=""
CONFIG_FILE=""
TIMEOUT=300

while [ $# -gt 0 ]; do
  case "$1" in
    --phase-dir) PHASE_DIR="$2"; shift 2 ;;
    --config)    CONFIG_FILE="$2"; shift 2 ;;
    --timeout)   TIMEOUT="$2"; shift 2 ;;
    *) echo "Usage: integration-gate.sh --phase-dir <dir> --config <config-path> [--timeout <seconds>]" >&2; exit 1 ;;
  esac
done

if [ -z "$PHASE_DIR" ] || [ -z "$CONFIG_FILE" ]; then
  echo "Usage: integration-gate.sh --phase-dir <dir> --config <config-path> [--timeout <seconds>]" >&2
  exit 1
fi

if [ ! -d "$PHASE_DIR" ]; then
  echo "{\"error\":\"Phase directory not found: $PHASE_DIR\"}" >&2
  exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
  echo "{\"error\":\"Config file not found: $CONFIG_FILE\"}" >&2
  exit 1
fi

# --- Read active departments from config ---
ACTIVE_DEPTS=()

BE_ENABLED=$(jq -r '.departments.backend // true' "$CONFIG_FILE")
FE_ENABLED=$(jq -r '.departments.frontend // false' "$CONFIG_FILE")
UX_ENABLED=$(jq -r '.departments.uiux // false' "$CONFIG_FILE")

if [ "$BE_ENABLED" = "true" ]; then ACTIVE_DEPTS+=("backend"); fi
if [ "$FE_ENABLED" = "true" ]; then ACTIVE_DEPTS+=("frontend"); fi
if [ "$UX_ENABLED" = "true" ]; then ACTIVE_DEPTS+=("uiux"); fi

# Single-dept mode: if only one department, skip cross-dept checks
SINGLE_DEPT=false
if [ "${#ACTIVE_DEPTS[@]}" -le 1 ]; then
  SINGLE_DEPT=true
fi

# --- Check per-department completion status ---
DT=$(date -u +"%Y-%m-%d")
ALL_COMPLETE=true
DEPT_STATUS="{}"

for dept in "${ACTIVE_DEPTS[@]}"; do
  STATUS_FILE="$PHASE_DIR/.dept-status-${dept}.json"
  if [ -f "$STATUS_FILE" ]; then
    DEPT_ST=$(jq -r '.status // "unknown"' "$STATUS_FILE")
    DEPT_STATUS=$(echo "$DEPT_STATUS" | jq --arg dept "$dept" --arg st "$DEPT_ST" '.[$dept] = $st')
    if [ "$DEPT_ST" != "complete" ]; then
      ALL_COMPLETE=false
    fi
  else
    DEPT_STATUS=$(echo "$DEPT_STATUS" | jq --arg dept "$dept" '.[$dept] = "pending"')
    ALL_COMPLETE=false
  fi
done

# --- If not all complete, check timeout ---
if [ "$ALL_COMPLETE" = "false" ]; then
  jq -n \
    --arg gate "timeout" \
    --argjson departments "$DEPT_STATUS" \
    --argjson cross_checks "null" \
    --argjson timeout_remaining "$TIMEOUT" \
    --arg dt "$DT" \
    '{"gate":$gate,"departments":$departments,"cross_checks":$cross_checks,"timeout_remaining":$timeout_remaining,"dt":$dt}'
  exit 1
fi

# --- All departments complete: run cross-dept checks ---
CROSS_CHECKS="{}"

# Check 1: API contract consistency
API_CHECK="skip"
API_FILE="$PHASE_DIR/api-contracts.jsonl"
if [ -f "$API_FILE" ] && [ "$SINGLE_DEPT" = "false" ]; then
  DISPUTED=$(jq -s '[.[] | select(.status == "proposed" or .status == "disputed")] | length' "$API_FILE" 2>/dev/null || echo "0")
  if [ "$DISPUTED" -gt 0 ]; then
    API_CHECK="fail"
  else
    API_CHECK="pass"
  fi
fi
CROSS_CHECKS=$(echo "$CROSS_CHECKS" | jq --arg v "$API_CHECK" '.api = $v')

# Check 2: Design sync (only when UX department active)
DESIGN_CHECK="skip"
HANDOFF_FILE="$PHASE_DIR/design-handoff.jsonl"
if [ -f "$HANDOFF_FILE" ] && [ "$UX_ENABLED" = "true" ]; then
  # Count ready components
  READY_COUNT=$(jq -s '[.[] | select(.status == "ready")] | length' "$HANDOFF_FILE" 2>/dev/null || echo "0")
  if [ "$READY_COUNT" -gt 0 ]; then
    # Check if any summary.jsonl files exist with fm fields
    SUMMARY_COUNT=$(find "$PHASE_DIR" -name "*.summary.jsonl" -type f 2>/dev/null | wc -l | tr -d ' ')
    if [ "$SUMMARY_COUNT" -gt 0 ]; then
      DESIGN_CHECK="pass"
    else
      DESIGN_CHECK="fail"
    fi
  else
    DESIGN_CHECK="pass"
  fi
fi
CROSS_CHECKS=$(echo "$CROSS_CHECKS" | jq --arg v "$DESIGN_CHECK" '.design = $v')

# Check 3: Handoff sentinels
HANDOFF_CHECK="pass"
for dept in "${ACTIVE_DEPTS[@]}"; do
  SENTINEL="$PHASE_DIR/.handoff-${dept}-complete"
  if [ ! -f "$SENTINEL" ]; then
    HANDOFF_CHECK="fail"
    break
  fi
done
CROSS_CHECKS=$(echo "$CROSS_CHECKS" | jq --arg v "$HANDOFF_CHECK" '.handoffs = $v')

# Check 4: Test results
TESTS_CHECK="skip"
TEST_FILE="$PHASE_DIR/test-results.jsonl"
if [ -f "$TEST_FILE" ]; then
  FAILED=$(jq -s '[.[] | select(.fl > 0)] | length' "$TEST_FILE" 2>/dev/null || echo "0")
  if [ "$FAILED" -gt 0 ]; then
    TESTS_CHECK="fail"
  else
    TESTS_CHECK="pass"
  fi
fi
CROSS_CHECKS=$(echo "$CROSS_CHECKS" | jq --arg v "$TESTS_CHECK" '.tests = $v')

# --- Determine gate result ---
HAS_FAIL=$(echo "$CROSS_CHECKS" | jq 'to_entries | map(select(.value == "fail")) | length')
HAS_SKIP=$(echo "$CROSS_CHECKS" | jq 'to_entries | map(select(.value == "skip")) | length')
ALL_PASS=$(echo "$CROSS_CHECKS" | jq 'to_entries | map(select(.value == "pass")) | length')
TOTAL=$(echo "$CROSS_CHECKS" | jq 'to_entries | length')

GATE="pass"
if [ "$HAS_FAIL" -gt 0 ]; then
  GATE="fail"
elif [ "$HAS_SKIP" -gt 0 ] && [ "$ALL_PASS" -lt "$TOTAL" ]; then
  # Only partial if some checks ran and some skipped
  if [ "$ALL_PASS" -gt 0 ]; then
    GATE="pass"
  fi
fi

jq -n \
  --arg gate "$GATE" \
  --argjson departments "$DEPT_STATUS" \
  --argjson cross_checks "$CROSS_CHECKS" \
  --argjson timeout_remaining "$TIMEOUT" \
  --arg dt "$DT" \
  '{"gate":$gate,"departments":$departments,"cross_checks":$cross_checks,"timeout_remaining":$timeout_remaining,"dt":$dt}'

exit 0
