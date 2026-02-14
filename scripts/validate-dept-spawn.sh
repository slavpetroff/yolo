#!/usr/bin/env bash
set -euo pipefail

# validate-dept-spawn.sh — SubagentStart hook: warns when department agents
# are spawned but their department is disabled in config.
#
# NOTE: SubagentStart hooks CANNOT block agent creation — only observe.
# This hook shows stderr warnings to the user when a disabled department
# agent is spawned, but cannot prevent it.
#
# Exit codes:
#   0 = allow (always — SubagentStart cannot block)
#
# Routed through hook-wrapper.sh for graceful degradation.

INPUT="$(cat)"
AGENT_NAME="${TOOL_INPUT_agent_name:-}"

# Extract agent name from hook input if env var not set
if [ -z "$AGENT_NAME" ]; then
  AGENT_NAME="$(echo "$INPUT" | jq -r '.agent_name // .tool_input.name // empty' 2>/dev/null || true)"
fi

# Only validate yolo- agents
case "$AGENT_NAME" in
  yolo-fe-*|yolo-ux-*|yolo-owner) ;;
  *) exit 0 ;;  # Not a department agent, allow
esac

CONFIG=".yolo-planning/config.json"
if [ ! -f "$CONFIG" ]; then
  exit 0  # No config, fail-open
fi

IFS='|' read -r FRONTEND UIUX WORKFLOW <<< "$(jq -r '[
  (.departments.frontend // false),
  (.departments.uiux // false),
  (.department_workflow // "backend_only")
] | join("|")' "$CONFIG" 2>/dev/null || echo "false|false|backend_only")"

case "$AGENT_NAME" in
  yolo-fe-*)
    if [ "$FRONTEND" != "true" ] || [ "$WORKFLOW" = "backend_only" ]; then
      echo "WARNING: Frontend agent '$AGENT_NAME' spawned but departments.frontend is not enabled or workflow is backend_only" >&2
    fi
    ;;
  yolo-ux-*)
    if [ "$UIUX" != "true" ] || [ "$WORKFLOW" = "backend_only" ]; then
      echo "WARNING: UX agent '$AGENT_NAME' spawned but departments.uiux is not enabled or workflow is backend_only" >&2
    fi
    ;;
  yolo-owner)
    if [ "$FRONTEND" != "true" ] && [ "$UIUX" != "true" ]; then
      echo "WARNING: Owner agent spawned but no multi-department mode (frontend and uiux both disabled)" >&2
    fi
    if [ "$WORKFLOW" = "backend_only" ]; then
      echo "WARNING: Owner agent spawned but department_workflow is backend_only" >&2
    fi
    ;;
esac

exit 0
