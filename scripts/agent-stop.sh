#!/bin/bash
set -u
# SubagentStop hook: Clear active agent marker and unregister PID
# Removes .vbw-planning/.active-agent so no stale agent is attributed
# Unregisters agent PID from tmux watchdog tracking

INPUT=$(cat)
PLANNING_DIR=".vbw-planning"
[ -f "$PLANNING_DIR/.active-agent" ] && rm -f "$PLANNING_DIR/.active-agent"

# Unregister agent PID
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT_PID=$(echo "$INPUT" | jq -r '.pid // ""' 2>/dev/null)
if [ -n "$AGENT_PID" ] && [ -f "$SCRIPT_DIR/agent-pid-tracker.sh" ]; then
  bash "$SCRIPT_DIR/agent-pid-tracker.sh" unregister "$AGENT_PID" 2>/dev/null || true
fi

exit 0
