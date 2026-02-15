#!/bin/bash
set -u
# SubagentStart hook: Record active agent type for cost attribution
# Writes stripped agent name to .vbw-planning/.active-agent

INPUT=$(cat)
PLANNING_DIR=".vbw-planning"
[ ! -d "$PLANNING_DIR" ] && exit 0

AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // ""' 2>/dev/null)

# Only track VBW agents
case "$AGENT_TYPE" in
  vbw-lead|vbw-dev|vbw-qa|vbw-scout|vbw-debugger|vbw-architect)
    echo "${AGENT_TYPE#vbw-}" > "$PLANNING_DIR/.active-agent"

    # Register agent PID for tmux cleanup
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    AGENT_PID=$(echo "$INPUT" | jq -r '.pid // ""' 2>/dev/null)
    if [ -z "$AGENT_PID" ]; then
      AGENT_PID="$PPID"
    fi
    if [ -n "$AGENT_PID" ] && [ -f "$SCRIPT_DIR/agent-pid-tracker.sh" ]; then
      bash "$SCRIPT_DIR/agent-pid-tracker.sh" register "$AGENT_PID" 2>/dev/null || true
    fi
    ;;
esac

exit 0
