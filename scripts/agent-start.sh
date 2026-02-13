#!/bin/bash
set -u
# SubagentStart hook: Record active agent type for cost attribution
# Writes stripped agent name to .yolo-planning/.active-agent

INPUT=$(cat)
PLANNING_DIR=".yolo-planning"
[ ! -d "$PLANNING_DIR" ] && exit 0

AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // ""' 2>/dev/null)

# Track all YOLO agents (26 agents across 4 departments)
case "$AGENT_TYPE" in
  yolo-*)
    echo "$AGENT_TYPE" > "$PLANNING_DIR/.active-agent"
    ;;
esac

exit 0
