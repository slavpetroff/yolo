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

exit 0
