#!/usr/bin/env bash
set -euo pipefail

# route-trivial.sh — Trivial complexity routing path
#
# Implements the trivial shortcut: skip Critic, Scout, Architect, Lead planning,
# formal QA, and security. Routes directly to department Senior -> Dev with a
# minimal inline plan.
#
# Usage: route-trivial.sh --phase-dir <path> --intent "text" --config <path> --analysis-json <path>
# Output: JSON to stdout with path, steps_skipped, estimated_steps, plan_path
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
      echo "Usage: route-trivial.sh --phase-dir <path> --intent \"text\" --config <path> --analysis-json <path>" >&2
      exit 1
      ;;
  esac
done

if [ -z "$PHASE_DIR" ] || [ -z "$INTENT" ]; then
  echo "Error: --phase-dir and --intent are required" >&2
  exit 1
fi

# --- Read analysis for intent type ---
DETECTED_INTENT="fix"
if [ -n "$ANALYSIS_JSON" ] && [ -f "$ANALYSIS_JSON" ]; then
  DETECTED_INTENT=$(jq -r '.intent // "fix"' "$ANALYSIS_JSON" 2>/dev/null)
fi

# --- Map intent to commit type ---
COMMIT_TYPE="fix"
case "$DETECTED_INTENT" in
  fix) COMMIT_TYPE="fix" ;;
  refactor) COMMIT_TYPE="refactor" ;;
  document) COMMIT_TYPE="docs" ;;
  test) COMMIT_TYPE="test" ;;
  *) COMMIT_TYPE="feat" ;;
esac

# --- Create minimal inline plan ---
PLAN_PATH=""
if [ -d "$PHASE_DIR" ]; then
  # Determine phase number from directory name
  PHASE_NUM=$(basename "$PHASE_DIR" | sed 's/-.*//')

  # Find next available plan number
  EXISTING_PLANS=0
  for f in "$PHASE_DIR"/*.plan.jsonl; do
    [ -f "$f" ] && EXISTING_PLANS=$((EXISTING_PLANS + 1))
  done
  PLAN_NUM=$(printf "%02d" $((EXISTING_PLANS + 1)))

  PLAN_PATH="$PHASE_DIR/${PHASE_NUM}-${PLAN_NUM}.plan.jsonl"

  # Write minimal plan with single task
  {
    jq -n \
      --arg p "$PHASE_NUM" \
      --arg n "$PLAN_NUM" \
      --arg t "$INTENT" \
      '{p: $p, n: $n, t: $t, w: 1, d: [], mh: [], obj: $t}'
    jq -n \
      --arg tp "$COMMIT_TYPE" \
      --arg a "$INTENT" \
      '{id: "T1", tp: $tp, a: $a, f: [], v: "Task completes without error", done: false}'
  } > "$PLAN_PATH"
fi

# --- Steps skipped in trivial path ---
STEPS_SKIPPED='["critique","research","architecture","planning","test_authoring","qa","security"]'

# --- Output JSON ---
jq -n \
  --arg path "trivial" \
  --argjson steps_skipped "$STEPS_SKIPPED" \
  --argjson estimated_steps 3 \
  --arg plan_path "$PLAN_PATH" \
  '{
    path: $path,
    steps_skipped: $steps_skipped,
    estimated_steps: $estimated_steps,
    plan_path: $plan_path
  }'
