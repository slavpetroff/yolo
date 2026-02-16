#!/usr/bin/env bash
set -euo pipefail

# department-guard.sh — Enforce department directory boundaries
# Called as a PreToolUse hook for Write|Edit|Bash operations.
# Reads tool input from stdin (JSON with file_path or command).
# Determines department from .yolo-planning/.active-agent (written by agent-start.sh).
# Outputs JSON permissionDecision:"deny" + exit 0 to block, or plain exit 0 to allow.
#
# Rules:
# - Backend agents cannot write to frontend/ or design/ directories
# - Frontend agents cannot write to backend-specific dirs (scripts/, agents/, hooks/, config/)
# - UI/UX agents cannot write to implementation dirs (src/, scripts/, agents/, hooks/, config/)
# - All agents can write to .yolo-planning/ (shared planning dir)
# - If .active-agent not found, allow (graceful degradation)
# - Bash tool: best-effort pattern matching for write operations

# Helper: output deny JSON and exit 0 (Claude Code reads JSON on exit 0)
# Uses printf instead of jq -n to save ~7.3ms per deny call.
deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
  exit 0
}

# Check agent context FIRST — if no active agent, skip everything (saves cat+jq)
PLANNING_DIR=".yolo-planning"
if [ ! -f "$PLANNING_DIR/.active-agent" ]; then
  exit 0
fi
AGENT=$(<"$PLANNING_DIR/.active-agent")
[ -z "$AGENT" ] && exit 0

# Read tool input (only when we have an active agent)
INPUT=$(cat 2>/dev/null) || INPUT=""
[ -z "$INPUT" ] && exit 0

# Single jq call to extract tool_name, file_path, and command (saves 2 jq invocations)
_parsed=$(jq -r '[(.tool_name // ""), (.tool_input.file_path // .tool_input.filePath // .file_path // .filePath // ""), (.tool_input.command // "")] | join("\t")' <<< "$INPUT" 2>/dev/null) || exit 0
IFS=$'\t' read -r TOOL_NAME FILE_PATH BASH_CMD <<< "$_parsed"

# Route based on tool type
if [ "${TOOL_NAME:-}" = "Bash" ]; then
  [ -z "${BASH_CMD:-}" ] && exit 0
  FILE_PATH=""  # Bash tool uses BASH_CMD, not FILE_PATH
else
  [ -z "${FILE_PATH:-}" ] && exit 0
fi

# Extract department from agent name
case "$AGENT" in
  yolo-fe-*)  DEPT="frontend" ;;
  yolo-ux-*)  DEPT="uiux" ;;
  yolo-owner) DEPT="shared" ;;
  yolo-critic|yolo-scout|yolo-debugger|yolo-security) DEPT="shared" ;;
  yolo-*)     DEPT="backend" ;;
  *)         exit 0 ;;  # Unknown agent — allow
esac

# Shared agents and owner: read-only enforcement is in their agent definitions
# We don't block shared agents from writing (they have disallowedTools instead)
if [ "$DEPT" = "shared" ]; then
  exit 0
fi

# Planning directory: always allowed for all departments
if [ -n "$FILE_PATH" ]; then
  case "$FILE_PATH" in
    .yolo-planning/*|*/.yolo-planning/*) exit 0 ;;
  esac
fi

# Department boundary checks
block_message() {
  local target_path="${FILE_PATH:-<bash command>}"
  deny "BLOCKED: $AGENT ($DEPT department) cannot write to $target_path — owned by $1 department. Cross-department writes are not allowed."
}

# Check paths against department boundaries
# For Write/Edit: check FILE_PATH directly
# For Bash: check command string for write patterns to protected directories
check_path_boundary() {
  local path="$1"
  case "$DEPT" in
    backend)
      case "$path" in
        frontend/*|src/components/*|src/pages/*|src/hooks/*|src/styles/*) block_message "frontend" ;;
        design/*|wireframes/*|design-tokens/*) block_message "uiux" ;;
      esac
      ;;
    frontend)
      case "$path" in
        scripts/*|agents/*|hooks/*|config/*) block_message "backend/plugin" ;;
        design/*|wireframes/*|design-tokens/*) block_message "uiux" ;;
      esac
      ;;
    uiux)
      case "$path" in
        src/*|scripts/*|agents/*|hooks/*|config/*) block_message "implementation" ;;
      esac
      ;;
  esac
}

if [ -n "$FILE_PATH" ]; then
  # Write/Edit tool: direct path check
  check_path_boundary "$FILE_PATH"
elif [ -n "${BASH_CMD:-}" ]; then
  # Bash tool: check for write patterns to protected directories
  # Protected dir patterns per department
  PROTECTED=""
  case "$DEPT" in
    backend)  PROTECTED="frontend/|src/components/|src/pages/|src/hooks/|src/styles/|design/|wireframes/|design-tokens/" ;;
    frontend) PROTECTED="scripts/|agents/|hooks/|config/|design/|wireframes/|design-tokens/" ;;
    uiux)     PROTECTED="src/|scripts/|agents/|hooks/|config/" ;;
  esac
  if [ -n "$PROTECTED" ]; then
    # Check common write patterns: >, >>, tee, cp, mv, mkdir, sed -i, install targeting protected dirs
    if grep -qE "(>|>>|tee |cp |mv |mkdir |sed -i|install ).*(${PROTECTED})" <<< "$BASH_CMD"; then
      FILE_PATH="<detected in bash command>"
      block_message "another"
    fi
  fi
fi

# Default: allow
exit 0
