#!/usr/bin/env bash
set -u

# po-scope-loop.sh — Orchestrate the PO-Questionary dialogue loop
#
# Manages the iterative refinement loop between Product Owner and Questionary
# agents, enforcing a configurable round cap and confidence threshold.
#
# Usage: po-scope-loop.sh --phase-dir <path> --config <path> --scope-draft <path>
# Output: JSON summary to stdout, scope-document.json written to phase-dir
# Exit codes: 0 = success, 1 = usage/runtime error

# --- jq dependency check ---
if ! command -v jq &>/dev/null; then
  echo '{"error":"jq is required but not installed"}' >&2
  exit 1
fi

# --- Arg parsing ---
PHASE_DIR=""
CONFIG_PATH=""
SCOPE_DRAFT=""

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
    --scope-draft)
      SCOPE_DRAFT="$2"
      shift 2
      ;;
    *)
      echo "Usage: po-scope-loop.sh --phase-dir <path> --config <path> --scope-draft <path>" >&2
      exit 1
      ;;
  esac
done

if [ -z "$PHASE_DIR" ] || [ -z "$CONFIG_PATH" ] || [ -z "$SCOPE_DRAFT" ]; then
  echo "Error: --phase-dir, --config, and --scope-draft are all required" >&2
  exit 1
fi

if [ ! -d "$PHASE_DIR" ]; then
  echo "Error: phase-dir does not exist: $PHASE_DIR" >&2
  exit 1
fi

if [ ! -f "$CONFIG_PATH" ]; then
  echo "Error: config file not found: $CONFIG_PATH" >&2
  exit 1
fi

if [ ! -f "$SCOPE_DRAFT" ]; then
  echo "Error: scope-draft file not found: $SCOPE_DRAFT" >&2
  exit 1
fi

# --- Read PO config ---
MAX_ROUNDS=$(jq -r '.po.max_questionary_rounds // 3' "$CONFIG_PATH")
CONFIDENCE_THRESHOLD=$(jq -r '.po.confidence_threshold // 0.85' "$CONFIG_PATH")

# --- Validate scope draft is JSON ---
if ! jq -e '.' "$SCOPE_DRAFT" >/dev/null 2>&1; then
  echo "Error: scope-draft is not valid JSON: $SCOPE_DRAFT" >&2
  exit 1
fi

# --- Initialize loop state ---
CURRENT_SCOPE="$SCOPE_DRAFT"
ROUNDS_USED=0
FINAL_CONFIDENCE=0
EARLY_EXIT=false

# --- Dialogue loop ---
for (( round=1; round<=MAX_ROUNDS; round++ )); do
  ROUNDS_USED=$round

  # Output round status JSON for orchestrator consumption
  jq -n \
    --argjson round "$round" \
    --argjson max_rounds "$MAX_ROUNDS" \
    --argjson threshold "$CONFIDENCE_THRESHOLD" \
    --arg scope_path "$CURRENT_SCOPE" \
    '{
      event: "round_start",
      round: $round,
      max_rounds: $max_rounds,
      confidence_threshold: $threshold,
      scope_source: $scope_path
    }' >&2

  # Read scope_confidence from the current scope document
  # The Questionary agent writes its response back to the scope draft
  SCOPE_CONFIDENCE=$(jq -r '.scope_confidence // 0' "$CURRENT_SCOPE")

  # Check if confidence meets threshold
  MEETS_THRESHOLD=$(echo "$SCOPE_CONFIDENCE >= $CONFIDENCE_THRESHOLD" | bc 2>/dev/null || echo "0")

  if [ "$MEETS_THRESHOLD" = "1" ]; then
    FINAL_CONFIDENCE="$SCOPE_CONFIDENCE"
    EARLY_EXIT=true

    # Output early exit status
    jq -n \
      --argjson round "$round" \
      --argjson confidence "$SCOPE_CONFIDENCE" \
      '{
        event: "early_exit",
        round: $round,
        confidence: $confidence,
        reason: "confidence_threshold_met"
      }' >&2

    break
  fi

  FINAL_CONFIDENCE="$SCOPE_CONFIDENCE"

  # Output round completion status
  jq -n \
    --argjson round "$round" \
    --argjson confidence "$SCOPE_CONFIDENCE" \
    --argjson threshold "$CONFIDENCE_THRESHOLD" \
    '{
      event: "round_complete",
      round: $round,
      confidence: $confidence,
      threshold: $threshold,
      below_threshold: true
    }' >&2
done

# --- Build enriched scope document ---
SCOPE_OUTPUT="$PHASE_DIR/scope-document.json"

if [ "$EARLY_EXIT" = "true" ]; then
  # Confidence met — output enriched scope as-is
  jq --argjson rounds "$ROUNDS_USED" \
     --argjson confidence "$FINAL_CONFIDENCE" \
     '. + {rounds_used: $rounds, final_confidence: $confidence, assumptions: []}' \
     "$CURRENT_SCOPE" > "$SCOPE_OUTPUT"
else
  # Max rounds exhausted — force-output with assumptions noted
  jq --argjson rounds "$ROUNDS_USED" \
     --argjson confidence "$FINAL_CONFIDENCE" \
     --argjson threshold "$CONFIDENCE_THRESHOLD" \
     '. + {
       rounds_used: $rounds,
       final_confidence: $confidence,
       assumptions: ["Max questionary rounds exhausted without meeting confidence threshold (\($confidence) < \($threshold)). Proceeding with best available scope."]
     }' "$CURRENT_SCOPE" > "$SCOPE_OUTPUT"
fi

# --- Output JSON summary to stdout ---
jq -n \
  --argjson rounds_used "$ROUNDS_USED" \
  --argjson confidence "$FINAL_CONFIDENCE" \
  --argjson early_exit "$EARLY_EXIT" \
  --arg scope_path "$SCOPE_OUTPUT" \
  '{
    rounds_used: $rounds_used,
    confidence: $confidence,
    early_exit: $early_exit,
    scope_path: $scope_path
  }'
