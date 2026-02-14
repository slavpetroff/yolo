#!/usr/bin/env bash
set -euo pipefail

# validate-send-message.sh — PostToolUse hook: warn on cross-department
# communication violations for SendMessage.
#
# NOTE: PostToolUse hooks CANNOT block — the message was already sent.
# This hook provides advisory feedback via additionalContext.
#
# Rules:
# - Same department: ALLOW
# - Any Lead → Owner: ALLOW (escalation)
# - Owner → any Lead: ALLOW (delegation)
# - Shared agents (scout, debugger, security, critic): ALLOW any
# - Cross-department non-Lead: WARN (message already sent, but flag violation)

INPUT=$(cat 2>/dev/null) || INPUT=""
if [ -z "$INPUT" ]; then
  exit 0
fi

# Only check SendMessage tool
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null) || TOOL_NAME=""
if [ "$TOOL_NAME" != "SendMessage" ]; then
  exit 0
fi

# Get sender from .active-agent
PLANNING_DIR=".yolo-planning"
SENDER=""
if [ -f "$PLANNING_DIR/.active-agent" ]; then
  SENDER=$(<"$PLANNING_DIR/.active-agent")
fi
if [ -z "$SENDER" ]; then
  exit 0  # No sender context — allow (graceful degradation)
fi

# Get recipient from tool input
RECIPIENT=$(echo "$INPUT" | jq -r '.tool_input.recipient // ""' 2>/dev/null) || RECIPIENT=""
if [ -z "$RECIPIENT" ]; then
  exit 0
fi

# Derive departments
get_dept() {
  case "$1" in
    yolo-fe-*)  echo "frontend" ;;
    yolo-ux-*)  echo "uiux" ;;
    yolo-owner) echo "owner" ;;
    yolo-critic|yolo-scout|yolo-debugger|yolo-security) echo "shared" ;;
    yolo-*)     echo "backend" ;;
    *)          echo "unknown" ;;
  esac
}

is_lead() {
  case "$1" in
    yolo-lead|yolo-fe-lead|yolo-ux-lead) return 0 ;;
    *) return 1 ;;
  esac
}

SENDER_DEPT=$(get_dept "$SENDER")
RECIPIENT_DEPT=$(get_dept "$RECIPIENT")

# Shared agents and Owner can talk to anyone
if [ "$SENDER_DEPT" = "shared" ] || [ "$SENDER_DEPT" = "owner" ]; then
  exit 0
fi

# Anyone can talk to shared agents or Owner
if [ "$RECIPIENT_DEPT" = "shared" ] || [ "$RECIPIENT_DEPT" = "owner" ]; then
  exit 0
fi

# Same department: always allowed
if [ "$SENDER_DEPT" = "$RECIPIENT_DEPT" ]; then
  exit 0
fi

# Cross-department: only Leads can communicate (and only with Owner, already handled above)
# PostToolUse cannot block (message already sent) — provide advisory feedback
jq -n --arg reason "WARNING: $SENDER ($SENDER_DEPT) sent cross-department message to $RECIPIENT ($RECIPIENT_DEPT). Cross-department communication must go through department Leads → Owner. Use escalation chain." '{
  hookSpecificOutput: {
    additionalContext: $reason
  }
}'
exit 0
