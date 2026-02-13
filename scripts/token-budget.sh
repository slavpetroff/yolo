#!/usr/bin/env bash
set -u

# token-budget.sh <role> [file]
# Enforces per-role token/line budgets on context content.
# Input: file path as arg, or stdin if no file.
# Output: truncated content within budget (stdout).
# Logs overage to metrics when v3_metrics=true.
# Exit: 0 always (budget enforcement must never block).

PLANNING_DIR=".vbw-planning"
CONFIG_PATH="${PLANNING_DIR}/config.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUDGETS_PATH="${SCRIPT_DIR}/../config/token-budgets.json"

# Check feature flag
ENABLED=false
if [ -f "$CONFIG_PATH" ] && command -v jq &>/dev/null; then
  ENABLED=$(jq -r '.v2_token_budgets // false' "$CONFIG_PATH" 2>/dev/null || echo "false")
fi

if [ $# -lt 1 ]; then
  # No role — pass through
  cat 2>/dev/null
  exit 0
fi

ROLE="$1"
shift

# Read content from file arg or stdin
CONTENT=""
if [ $# -ge 1 ] && [ -f "$1" ]; then
  CONTENT=$(cat "$1" 2>/dev/null) || CONTENT=""
  shift
else
  CONTENT=$(cat 2>/dev/null) || CONTENT=""
fi

# Optional contract metadata for per-task budgets
CONTRACT_PATH="${1:-}"
TASK_NUMBER="${2:-}"

# If flag disabled, pass through
if [ "$ENABLED" != "true" ]; then
  echo "$CONTENT"
  exit 0
fi

# Load budget for role
MAX_LINES=0
if [ -f "$BUDGETS_PATH" ]; then
  MAX_LINES=$(jq -r --arg r "$ROLE" '.budgets[$r].max_lines // 0' "$BUDGETS_PATH" 2>/dev/null || echo "0")
fi

# No budget defined — pass through
if [ "$MAX_LINES" -eq 0 ] || [ "$MAX_LINES" = "0" ]; then
  echo "$CONTENT"
  exit 0
fi

# Count lines
LINE_COUNT=$(echo "$CONTENT" | wc -l | tr -d ' ')

if [ "$LINE_COUNT" -le "$MAX_LINES" ]; then
  # Within budget
  echo "$CONTENT"
  exit 0
fi

# Truncate (tail strategy: keep last N lines for most recent context)
STRATEGY=$(jq -r '.truncation_strategy // "tail"' "$BUDGETS_PATH" 2>/dev/null || echo "tail")
OVERAGE=$((LINE_COUNT - MAX_LINES))

case "$STRATEGY" in
  tail)
    echo "$CONTENT" | tail -n "$MAX_LINES"
    ;;
  head)
    echo "$CONTENT" | head -n "$MAX_LINES"
    ;;
  *)
    echo "$CONTENT" | tail -n "$MAX_LINES"
    ;;
esac

# Log overage to metrics
METRICS_ENABLED=false
if [ -f "$CONFIG_PATH" ]; then
  METRICS_ENABLED=$(jq -r '.v3_metrics // false' "$CONFIG_PATH" 2>/dev/null || echo "false")
fi

if [ "$METRICS_ENABLED" = "true" ] && [ -f "${SCRIPT_DIR}/collect-metrics.sh" ]; then
  bash "${SCRIPT_DIR}/collect-metrics.sh" token_overage 0 \
    "role=${ROLE}" "lines_total=${LINE_COUNT}" "lines_max=${MAX_LINES}" "lines_truncated=${OVERAGE}" 2>/dev/null || true
fi

# Output truncation notice to stderr
echo "[token-budget] ${ROLE}: truncated ${OVERAGE} lines (${LINE_COUNT} -> ${MAX_LINES})" >&2
