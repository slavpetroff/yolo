#!/bin/bash
set -euo pipefail
# Orchestrates Dev→Senior code review cycle with max 2 rounds.
# Reads code-review.jsonl verdict and returns status for orchestrator routing.
# Does NOT spawn agents — reads artifacts and returns JSON status.

usage() {
  echo "Usage: review-loop.sh --phase-dir DIR --plan-id ID [--config PATH]" >&2
  exit 1
}

PHASE_DIR=""
PLAN_ID=""
CONFIG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase-dir) PHASE_DIR="$2"; shift 2 ;;
    --plan-id)   PLAN_ID="$2"; shift 2 ;;
    --config)    CONFIG="$2"; shift 2 ;;
    *) usage ;;
  esac
done

[[ -z "$PHASE_DIR" || -z "$PLAN_ID" ]] && usage

# Read max_cycles from config (default 2)
MAX_CYCLES=2
if [[ -n "$CONFIG" && -f "$CONFIG" ]]; then
  CFG_VAL=$(jq -r '.review_loop.max_cycles // empty' "$CONFIG" 2>/dev/null || true)
  if [[ -n "$CFG_VAL" ]]; then
    MAX_CYCLES="$CFG_VAL"
  fi
fi

REVIEW_FILE="$PHASE_DIR/code-review.jsonl"

if [[ ! -f "$REVIEW_FILE" ]]; then
  jq -n --arg mc "$MAX_CYCLES" '{cycles_used:0,result:"pending",reason:"no code-review.jsonl found",max_cycles:($mc|tonumber)}'
  exit 1
fi

# Read the latest verdict line for this plan
VERDICT=$(jq -s --arg plan "$PLAN_ID" '[.[] | select(.plan == $plan and has("r"))] | last' "$REVIEW_FILE" 2>/dev/null)

if [[ -z "$VERDICT" || "$VERDICT" == "null" ]]; then
  jq -n --arg plan "$PLAN_ID" '{cycles_used:0,result:"pending",reason:"no verdict for plan",plan:$plan}'
  exit 1
fi

RESULT=$(jq -r '.r' <<< "$VERDICT")
CYCLE=$(jq -r '.cycle // 1' <<< "$VERDICT")
SG_PROMOTED=$(jq -c '.sg_promoted // []' <<< "$VERDICT")

if [[ "$RESULT" == "approve" ]]; then
  jq -n --argjson cycle "$CYCLE" --argjson sg "$SG_PROMOTED" \
    '{cycles_used:$cycle,result:"approve",sg_promoted:$sg}'
  exit 0
fi

if [[ "$RESULT" == "changes_requested" ]]; then
  if [[ "$CYCLE" -lt "$MAX_CYCLES" ]]; then
    # Extract findings for orchestrator to route to Dev
    FINDINGS=$(jq -s --arg plan "$PLAN_ID" '[.[] | select(.plan == $plan and has("sev"))]' "$REVIEW_FILE" 2>/dev/null)
    jq -n --argjson cycle "$CYCLE" --arg status "changes_requested" --argjson findings "$FINDINGS" \
      '{cycle:$cycle,status:$status,findings:$findings}'
    exit 0
  else
    jq -n --argjson cycle "$CYCLE" --argjson mc "$MAX_CYCLES" \
      '{cycles_used:$cycle,result:"escalated",reason:"max cycles exceeded",max_cycles:$mc}'
    exit 1
  fi
fi

# Unknown result
jq -n --arg r "$RESULT" '{cycles_used:0,result:"unknown",reason:("unexpected verdict: " + $r)}'
exit 1
