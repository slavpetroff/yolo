#!/usr/bin/env bash
set -u
# PreToolUse: Hard-block EnterPlanMode and ExitPlanMode
# YOLO projects MUST use /yolo:go for all planning. Claude Code's built-in
# plan mode bypasses the entire YOLO workflow and is strictly prohibited.
#
# This hook fires on PreToolUse for EnterPlanMode|ExitPlanMode and returns
# permissionDecision:deny to prevent the tool call from executing.

# Only enforce if a YOLO project exists
PLANNING_DIR=".yolo-planning"
[ -d "$PLANNING_DIR" ] || exit 0

INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
[ -z "$TOOL" ] && exit 0

case "$TOOL" in
  EnterPlanMode|ExitPlanMode)
    jq -n --arg tool "$TOOL" '{
      "decision": "block",
      "reason": ("YOLO project detected. " + $tool + " is prohibited — all planning MUST go through /yolo:go. See CLAUDE.md rules."),
      "hookSpecificOutput": {
        "permissionDecision": "deny",
        "additionalContext": ("BLOCKED: " + $tool + " is not allowed in YOLO projects. Use /yolo:go for all planning workflows.")
      }
    }'
    ;;
  *)
    exit 0
    ;;
esac
