#!/bin/bash
set -u
# SubagentStart hook: Record active agent type for cost attribution
# Writes agent name to .yolo-planning/.active-agent (full yolo-* prefix preserved)

PLANNING_DIR=".yolo-planning"
[ ! -d "$PLANNING_DIR" ] && exit 0

INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

AGENT_TYPE=$(jq -r '.agent_type // ""' <<< "$INPUT" 2>/dev/null)

# Track all YOLO agents (26 agents across 4 departments)
case "$AGENT_TYPE" in
  yolo-*)
    printf '%s' "$AGENT_TYPE" > "$PLANNING_DIR/.active-agent"
    ;;
esac

# --- Department Lead detection: write initial dept status ---
case "$AGENT_TYPE" in
  yolo-fe-*) DEPT="frontend" ;;
  yolo-ux-*) DEPT="uiux" ;;
  yolo-*) DEPT="backend" ;;
  *) DEPT="" ;;
esac

IS_LEAD=false
case "$AGENT_TYPE" in
  yolo-lead|yolo-fe-lead|yolo-ux-lead) IS_LEAD=true ;;
esac
[ "$IS_LEAD" != "true" ] && exit 0

PHASE_NUM=$(jq -r '.phase // empty' "$PLANNING_DIR/.execution-state.json" 2>/dev/null) || true
PHASE_NAME=$(jq -r '.phase_name // empty' "$PLANNING_DIR/.execution-state.json" 2>/dev/null) || true
PHASE_DIR=""
if [ -n "${PHASE_NUM:-}" ] && [ -n "${PHASE_NAME:-}" ]; then
  PHASE_DIR="$PLANNING_DIR/phases/$(printf '%02d' "$PHASE_NUM")-${PHASE_NAME}"
fi
if [ -z "$PHASE_DIR" ] || [ ! -d "$PHASE_DIR" ]; then
  PHASE_DIR=$(ls -d "$PLANNING_DIR/phases/"*/ 2>/dev/null | sort | tail -1)
  PHASE_DIR="${PHASE_DIR%/}"
fi
[ -z "${PHASE_DIR:-}" ] || [ ! -d "${PHASE_DIR:-}" ] && exit 0

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
DEPT_STATUS="$SCRIPT_DIR/dept-status.sh"
[ ! -f "$DEPT_STATUS" ] && exit 0

bash "$DEPT_STATUS" --dept "$DEPT" --phase-dir "$PHASE_DIR" --action write --status running --step planning 2>/dev/null || true

exit 0
