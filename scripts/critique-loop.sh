#!/usr/bin/env bash
# critique-loop.sh — Orchestrate multi-round critique with confidence gating
#
# Runs up to max_rounds of critique, exiting early when confidence >= threshold.
# Hard cap prevents runaway loops regardless of confidence.
#
# Usage: critique-loop.sh --phase-dir <path> --config <path> --role <critic|fe-critic|ux-critic>
#
# Output: stdout = JSON summary with rounds_used, final_confidence, early_exit, findings_total, findings_per_round
# Exit 0 on success, exit 1 on usage error

set -euo pipefail

# Defaults (used when config keys are missing)
DEFAULT_MAX_ROUNDS=3
DEFAULT_CONFIDENCE_THRESHOLD=85

PHASE_DIR=""
CONFIG_PATH=""
ROLE=""

# Parse flags
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
    --role)
      ROLE="$2"
      shift 2
      ;;
    *)
      echo "Unknown flag: $1" >&2
      echo "Usage: critique-loop.sh --phase-dir <path> --config <path> --role <critic|fe-critic|ux-critic>" >&2
      exit 1
      ;;
  esac
done

# Validate required flags
if [[ -z "$PHASE_DIR" || -z "$CONFIG_PATH" || -z "$ROLE" ]]; then
  echo "Usage: critique-loop.sh --phase-dir <path> --config <path> --role <critic|fe-critic|ux-critic>" >&2
  exit 1
fi

# Validate role
case "$ROLE" in
  critic|fe-critic|ux-critic) ;;
  *)
    echo "Invalid role: $ROLE (must be critic, fe-critic, or ux-critic)" >&2
    exit 1
    ;;
esac

# jq dependency check
if ! command -v jq &>/dev/null; then
  echo '{"error":"jq not found","rounds_used":0,"final_confidence":0,"early_exit":false,"findings_total":0,"findings_per_round":[]}'
  exit 1
fi

# Read config values via jq with fallback defaults
max_rounds="$DEFAULT_MAX_ROUNDS"
confidence_threshold="$DEFAULT_CONFIDENCE_THRESHOLD"

if [[ -f "$CONFIG_PATH" ]]; then
  max_rounds=$(jq -r ".critique.max_rounds // $DEFAULT_MAX_ROUNDS" "$CONFIG_PATH")
  confidence_threshold=$(jq -r ".critique.confidence_threshold // $DEFAULT_CONFIDENCE_THRESHOLD" "$CONFIG_PATH")
fi

# Validate max_rounds is within bounds (1-3 hard cap)
if [[ "$max_rounds" -gt 3 ]]; then
  max_rounds=3
fi
if [[ "$max_rounds" -lt 1 ]]; then
  max_rounds=1
fi

# Resolve critique file path based on role
case "$ROLE" in
  critic)     critique_file="$PHASE_DIR/critique.jsonl" ;;
  fe-critic)  critique_file="$PHASE_DIR/fe-critique.jsonl" ;;
  ux-critic)  critique_file="$PHASE_DIR/ux-critique.jsonl" ;;
esac

# Resolve DB path and phase number (DB is single source of truth)
PLANNING_DIR="$(cd "$PHASE_DIR/../.." 2>/dev/null && pwd)"
DB_PATH="$PLANNING_DIR/yolo.db"
PHASE_NUM=$(basename "$(dirname "$PHASE_DIR")" | sed 's/-.*//')

# Track per-round findings
findings_per_round=()
final_confidence=0
early_exit=false
rounds_used=0

for round in $(seq 1 "$max_rounds"); do
  rounds_used=$round

  # Count findings for this round from critique.jsonl
  round_findings=0
  round_confidence=0

  # DB-only query (DB is single source of truth)
  if [[ -f "$DB_PATH" ]] && command -v sqlite3 &>/dev/null; then
    _db_findings=$(sqlite3 "$DB_PATH" "SELECT count(*) FROM critique WHERE phase='$PHASE_NUM' AND round=$round;" 2>/dev/null || echo 0)
    _db_conf=$(sqlite3 "$DB_PATH" "SELECT COALESCE(max(confidence),0) FROM critique WHERE phase='$PHASE_NUM' AND round=$round;" 2>/dev/null || echo 0)
    round_findings=${_db_findings:-0}
    round_confidence=${_db_conf:-0}
  fi

  findings_per_round+=("$round_findings")
  final_confidence=$round_confidence

  # Check confidence threshold for early exit
  if [[ "$round_confidence" -ge "$confidence_threshold" ]]; then
    early_exit=true
    break
  fi
done

# Calculate total findings
findings_total=0
# DB-only total count (DB is single source of truth)
if [[ -f "$DB_PATH" ]] && command -v sqlite3 &>/dev/null; then
  findings_total=$(sqlite3 "$DB_PATH" "SELECT count(*) FROM critique WHERE phase='$PHASE_NUM';" 2>/dev/null || echo 0)
fi

# Build findings_per_round JSON array
fpr_json="["
for i in "${!findings_per_round[@]}"; do
  if [[ $i -gt 0 ]]; then
    fpr_json+=","
  fi
  fpr_json+="${findings_per_round[$i]}"
done
fpr_json+="]"

# Output JSON summary
jq -n \
  --argjson rounds_used "$rounds_used" \
  --argjson final_confidence "$final_confidence" \
  --argjson early_exit "$early_exit" \
  --argjson findings_total "$findings_total" \
  --argjson findings_per_round "$fpr_json" \
  '{
    rounds_used: $rounds_used,
    final_confidence: $final_confidence,
    early_exit: $early_exit,
    findings_total: $findings_total,
    findings_per_round: $findings_per_round
  }'
