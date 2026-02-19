#!/usr/bin/env bash
set -euo pipefail

# route.sh — Consolidated complexity routing script
#
# Replaces route-trivial.sh, route-medium.sh, route-high.sh with a single
# parameterized dispatcher.
#
# Usage: route.sh --path trivial|medium|high --phase-dir <path> --intent "text" \
#                 [--config <path>] [--analysis-json <path>]
# Output: JSON to stdout (format matches original per-path scripts)
# Exit codes: 0 = success, 1 = usage/runtime error

# --- Source shared library ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../lib" && pwd)"
# shellcheck source=../lib/yolo-common.sh
source "$LIB_DIR/yolo-common.sh"

require_jq

# --- Arg parsing ---
PATH_MODE=""
PHASE_DIR=""
INTENT=""
CONFIG_PATH=""
ANALYSIS_JSON=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --path)
      PATH_MODE="$2"
      shift 2
      ;;
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
      echo "Usage: route.sh --path trivial|medium|high --phase-dir <path> --intent \"text\" [--config <path>] [--analysis-json <path>]" >&2
      exit 1
      ;;
  esac
done

# --- Validation ---
if [ -z "$PATH_MODE" ]; then
  echo "Error: --path is required (trivial|medium|high)" >&2
  exit 1
fi

if [ -z "$PHASE_DIR" ] || [ -z "$INTENT" ]; then
  echo "Error: --phase-dir and --intent are required" >&2
  exit 1
fi

case "$PATH_MODE" in
  trivial|medium|high) ;;
  *)
    echo "Error: --path must be trivial, medium, or high (got: $PATH_MODE)" >&2
    exit 1
    ;;
esac

# --- Trivial path ---
route_trivial() {
  # Read analysis for intent type
  local detected_intent="fix"
  if [ -n "$ANALYSIS_JSON" ] && [ -f "$ANALYSIS_JSON" ]; then
    detected_intent=$(jq -r '.intent // "fix"' "$ANALYSIS_JSON" 2>/dev/null)
  fi

  # Map intent to commit type
  local commit_type="fix"
  case "$detected_intent" in
    fix) commit_type="fix" ;;
    refactor) commit_type="refactor" ;;
    document) commit_type="docs" ;;
    test) commit_type="test" ;;
    *) commit_type="feat" ;;
  esac

  # Create minimal inline plan
  local plan_path=""
  if [ -d "$PHASE_DIR" ]; then
    local phase_num
    phase_num=$(basename "$PHASE_DIR" | sed 's/-.*//')

    local existing_plans=0
    for f in "$PHASE_DIR"/*.plan.jsonl; do
      [ -f "$f" ] && existing_plans=$((existing_plans + 1))
    done
    local plan_num
    plan_num=$(printf "%02d" $((existing_plans + 1)))

    plan_path="$PHASE_DIR/${phase_num}-${plan_num}.plan.jsonl"

    {
      jq -n \
        --arg p "$phase_num" \
        --arg n "$plan_num" \
        --arg t "$INTENT" \
        '{p: $p, n: $n, t: $t, w: 1, d: [], mh: [], obj: $t}'
      jq -n \
        --arg tp "$commit_type" \
        --arg a "$INTENT" \
        '{id: "T1", tp: $tp, a: $a, f: [], v: "Task completes without error", done: false}'
    } > "$plan_path"
  fi

  local steps_skipped='["critique","research","architecture","planning","test_authoring","qa","security"]'

  json_output \
    --arg path "trivial" \
    --argjson steps_skipped "$steps_skipped" \
    --argjson estimated_steps 3 \
    --arg plan_path "$plan_path" \
    '{
      path: $path,
      steps_skipped: $steps_skipped,
      estimated_steps: $estimated_steps,
      plan_path: $plan_path
    }'
}

# --- Medium path ---
route_medium() {
  local steps_skipped='["critique","research","architecture","test_authoring","qa","security"]'
  local steps_included='["planning","design_review","implementation","code_review","signoff"]'
  local estimated_steps=5

  local has_architecture="false"
  if [ -d "$PHASE_DIR" ] && [ -f "$PHASE_DIR/architecture.toon" ]; then
    has_architecture="true"
  fi

  json_output \
    --arg path "medium" \
    --argjson steps_skipped "$steps_skipped" \
    --argjson steps_included "$steps_included" \
    --argjson estimated_steps "$estimated_steps" \
    --argjson has_architecture "$has_architecture" \
    '{
      path: $path,
      steps_skipped: $steps_skipped,
      steps_included: $steps_included,
      estimated_steps: $estimated_steps,
      has_architecture: $has_architecture
    }'
}

# --- High path ---
route_high() {
  local multi_dept="false"
  if [ -n "$ANALYSIS_JSON" ] && [ -f "$ANALYSIS_JSON" ]; then
    local dept_count
    dept_count=$(jq -r '.departments | length // 0' "$ANALYSIS_JSON" 2>/dev/null || echo "0")
    if [ "$dept_count" -gt 1 ]; then
      multi_dept="true"
    fi
  fi

  local all_steps='["critique","research","architecture","planning","design_review","test_authoring","implementation","code_review","qa","security","signoff"]'

  json_output \
    --arg path "high" \
    --argjson steps_skipped '[]' \
    --argjson steps_included "$all_steps" \
    --argjson multi_dept "$multi_dept" \
    --argjson estimated_steps 11 \
    '{
      path: $path,
      steps_skipped: [],
      steps_included: $steps_included,
      multi_dept: $multi_dept,
      estimated_steps: $estimated_steps
    }'
}

# --- Dispatch ---
case "$PATH_MODE" in
  trivial) route_trivial ;;
  medium)  route_medium ;;
  high)    route_high ;;
esac
