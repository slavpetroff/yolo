#!/bin/bash
set -u
# SubagentStart hook: Record active agent type for cost attribution
# Writes stripped agent name to .yolo-planning/.active-agent

INPUT=$(cat)
PLANNING_DIR=".yolo-planning"
[ ! -d "$PLANNING_DIR" ] && exit 0

AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // ""' 2>/dev/null)

# Only track YOLO agents
case "$AGENT_TYPE" in
  yolo-lead|yolo-dev|yolo-qa|yolo-scout|yolo-debugger|yolo-architect)
    echo "${AGENT_TYPE#yolo-}" > "$PLANNING_DIR/.active-agent"
    ;;
esac

exit 0
