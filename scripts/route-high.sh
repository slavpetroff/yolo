#!/usr/bin/env bash
set -euo pipefail

# route-high.sh — High complexity (full ceremony) routing path
#
# Pass-through that confirms the full 11-step workflow applies per
# execute-protocol.md. All steps active, none skipped (except per
# existing effort/config skip rules handled by execute-protocol).
#
# Usage: route-high.sh --phase-dir <path> --intent "text" --config <path> --analysis-json <path>
# Output: JSON to stdout with path, steps_skipped, steps_included, multi_dept, estimated_steps
# Exit codes: 0 = success, 1 = usage/runtime error

# --- jq dependency check ---
if ! command -v jq &>/dev/null; then
  echo '{"error":"jq is required but not installed"}' >&2
  exit 1
fi

# --- Arg parsing ---
PHASE_DIR=""
INTENT=""
CONFIG_PATH=""
ANALYSIS_JSON=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase-dir)
      PHASE_DIR="$2"
      shift 2
      ;;
    --intent)
      INTENT="$2"
      shift 2
      ;;
    --config)
      CONFIG_PATH="$2"
      shift 2
      ;;
    --analysis-json)
      ANALYSIS_JSON="$2"
      shift 2
      ;;
    *)
      echo "Usage: route-high.sh --phase-dir <path> --intent \"text\" --config <path> --analysis-json <path>" >&2
      exit 1
      ;;
  esac
done

if [ -z "$PHASE_DIR" ] || [ -z "$INTENT" ]; then
  echo "Error: --phase-dir and --intent are required" >&2
  exit 1
fi

# --- Detect multi-department from analysis ---
MULTI_DEPT="false"
if [ -n "$ANALYSIS_JSON" ] && [ -f "$ANALYSIS_JSON" ]; then
  DEPT_COUNT=$(jq -r '.departments | length // 0' "$ANALYSIS_JSON" 2>/dev/null || echo "0")
  if [ "$DEPT_COUNT" -gt 1 ]; then
    MULTI_DEPT="true"
  fi
fi

# --- All 11 steps included (per execute-protocol.md) ---
ALL_STEPS='["critique","research","architecture","planning","design_review","test_authoring","implementation","code_review","qa","security","signoff"]'

# --- Output JSON ---
jq -n \
  --arg path "high" \
  --argjson steps_skipped '[]' \
  --argjson steps_included "$ALL_STEPS" \
  --argjson multi_dept "$MULTI_DEPT" \
  --argjson estimated_steps 11 \
  '{
    path: $path,
    steps_skipped: [],
    steps_included: $steps_included,
    multi_dept: $multi_dept,
    estimated_steps: $estimated_steps
  }'
