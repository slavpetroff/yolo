#!/usr/bin/env bash
set -euo pipefail

# pre-integration-check.sh — Lightweight pre-integration readiness check
#
# Dept Leads run this before the full Integration Gate to catch showstoppers
# early (CH-4). Checks:
# - All dept handoff sentinels exist (.handoff-{dept}-complete)
# - test-results.jsonl exists per active department
# - No open critical escalations in escalation.jsonl
#
# Usage: pre-integration-check.sh --phase-dir <path> [--config <path>]
# Output: JSON to stdout with ready/not-ready per department and blocking issues
# Exit codes: 0 = all ready, 1 = at least one department not ready

# --- jq dependency check ---
if ! command -v jq &>/dev/null; then
  echo '{"error":"jq is required but not installed"}' >&2
  exit 1
fi

# --- Arg parsing ---
PHASE_DIR=""
CONFIG_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase-dir)
      PHASE_DIR="$2"
      shift 2
      ;;
    --config)
      CONFIG_PATH="$2"
      shift 2
      ;;
    *)
      echo "Usage: pre-integration-check.sh --phase-dir <path> [--config <path>]" >&2
      exit 1
      ;;
  esac
done

if [ -z "$PHASE_DIR" ]; then
  echo "Error: --phase-dir is required" >&2
  exit 1
fi

if [ ! -d "$PHASE_DIR" ]; then
  echo "Error: phase directory does not exist: $PHASE_DIR" >&2
  exit 1
fi

# --- Detect active departments from config ---
ACTIVE_DEPTS=()
if [ -n "$CONFIG_PATH" ] && [ -f "$CONFIG_PATH" ]; then
  while IFS= read -r dept; do
    ACTIVE_DEPTS+=("$dept")
  done < <(jq -r '.departments // {} | to_entries[] | select(.value == true) | .key' "$CONFIG_PATH" 2>/dev/null)
fi

# Default to backend if no config
if [ ${#ACTIVE_DEPTS[@]} -eq 0 ]; then
  ACTIVE_DEPTS=("backend")
fi

# --- Check functions ---
DEPT_RESULTS="[]"
BLOCKING_ISSUES="[]"
ALL_READY=true

for dept in "${ACTIVE_DEPTS[@]}"; do
  DEPT_READY=true
  DEPT_ISSUES="[]"

  # Map department name to sentinel name
  local_sentinel_name="$dept"

  # Check 1: Handoff sentinel exists
  SENTINEL_FILE="$PHASE_DIR/.handoff-${local_sentinel_name}-complete"
  if [ ! -f "$SENTINEL_FILE" ]; then
    DEPT_READY=false
    DEPT_ISSUES=$(echo "$DEPT_ISSUES" | jq --arg d "$dept" \
      '. + ["missing handoff sentinel: .handoff-" + $d + "-complete"]')
  fi

  # Check 2: test-results.jsonl exists with entries for this dept
  RESULTS_FILE="$PHASE_DIR/test-results.jsonl"
  if [ -f "$RESULTS_FILE" ]; then
    DEPT_TESTS=$(jq -r --arg d "$dept" 'select(.dept == $d) | .plan' "$RESULTS_FILE" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$DEPT_TESTS" -eq 0 ]; then
      # No test results for this dept — warn but don't block for single-dept
      if [ ${#ACTIVE_DEPTS[@]} -gt 1 ]; then
        DEPT_READY=false
        DEPT_ISSUES=$(echo "$DEPT_ISSUES" | jq --arg d "$dept" \
          '. + ["no test results for department: " + $d]')
      fi
    fi
  else
    # No test-results.jsonl at all
    if [ ${#ACTIVE_DEPTS[@]} -gt 1 ]; then
      DEPT_READY=false
      DEPT_ISSUES=$(echo "$DEPT_ISSUES" | jq \
        '. + ["test-results.jsonl not found"]')
    fi
  fi

  # Check 3: No open critical escalations for this dept
  ESC_FILE="$PHASE_DIR/escalation.jsonl"
  if [ -f "$ESC_FILE" ]; then
    CRITICAL_OPEN=$(jq -r --arg d "$dept" \
      'select(.st == "open" and .sev == "critical" and (.dept == $d or .dept == null)) | .id' \
      "$ESC_FILE" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$CRITICAL_OPEN" -gt 0 ]; then
      DEPT_READY=false
      DEPT_ISSUES=$(echo "$DEPT_ISSUES" | jq --arg c "$CRITICAL_OPEN" --arg d "$dept" \
        '. + [$c + " open critical escalation(s) for " + $d]')
    fi
  fi

  # Build department result
  DEPT_STATUS="ready"
  if [ "$DEPT_READY" = false ]; then
    DEPT_STATUS="not_ready"
    ALL_READY=false
  fi

  DEPT_RESULTS=$(echo "$DEPT_RESULTS" | jq \
    --arg d "$dept" --arg s "$DEPT_STATUS" --argjson i "$DEPT_ISSUES" \
    '. + [{"department": $d, "status": $s, "issues": $i}]')

  # Aggregate blocking issues
  if [ "$DEPT_READY" = false ]; then
    BLOCKING_ISSUES=$(echo "$BLOCKING_ISSUES" | jq --arg d "$dept" --argjson i "$DEPT_ISSUES" \
      '. + ($i | map($d + ": " + .))')
  fi
done

# --- Overall status ---
if [ "$ALL_READY" = true ]; then
  OVERALL="ready"
else
  OVERALL="not_ready"
fi

# --- Output JSON ---
jq -n \
  --arg status "$OVERALL" \
  --argjson departments "$DEPT_RESULTS" \
  --argjson blocking_issues "$BLOCKING_ISSUES" \
  '{
    status: $status,
    departments: $departments,
    blocking_issues: $blocking_issues
  }'

# Exit with appropriate code
if [ "$OVERALL" = "not_ready" ]; then
  exit 1
fi
