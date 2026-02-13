#!/usr/bin/env bash
set -euo pipefail

# department-guard.sh — Enforce department directory boundaries
# Called as a PreToolUse hook for Write|Edit operations.
# Reads tool input from stdin (JSON with file_path).
# Determines department from VBW_AGENT env var (set by agent-start.sh).
# Exits 0 (allow) or 2 (block with message).
#
# Rules:
# - Backend agents cannot write to frontend/ or design/ directories
# - Frontend agents cannot write to backend-specific dirs (scripts/, agents/, hooks/, config/)
# - UI/UX agents cannot write to implementation dirs (src/, scripts/, agents/, hooks/, config/)
# - All agents can write to .vbw-planning/ (shared planning dir)
# - If VBW_AGENT is not set, allow (graceful degradation)

# Read tool input
INPUT=$(cat 2>/dev/null) || INPUT=""
if [ -z "$INPUT" ]; then
  exit 0
fi

# Extract file path from tool input
FILE_PATH=$(echo "$INPUT" | jq -r '.file_path // .filePath // empty' 2>/dev/null) || FILE_PATH=""
if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# Determine agent department
AGENT="${VBW_AGENT:-}"
if [ -z "$AGENT" ]; then
  exit 0  # No agent context — allow (graceful degradation)
fi

# Extract department from agent name
case "$AGENT" in
  vbw-fe-*)  DEPT="frontend" ;;
  vbw-ux-*)  DEPT="uiux" ;;
  vbw-owner) DEPT="shared" ;;
  vbw-critic|vbw-scout|vbw-debugger|vbw-security) DEPT="shared" ;;
  vbw-*)     DEPT="backend" ;;
  *)         exit 0 ;;  # Unknown agent — allow
esac

# Shared agents and owner: read-only enforcement is in their agent definitions
# We don't block shared agents from writing (they have disallowedTools instead)
if [ "$DEPT" = "shared" ]; then
  exit 0
fi

# Planning directory: always allowed for all departments
case "$FILE_PATH" in
  .vbw-planning/*|*/.vbw-planning/*) exit 0 ;;
esac

# Department boundary checks
block_message() {
  echo "BLOCKED: $AGENT ($DEPT department) cannot write to $FILE_PATH — owned by $1 department. Cross-department writes are not allowed." >&2
  exit 2
}

case "$DEPT" in
  backend)
    # Backend cannot write to frontend or design directories
    case "$FILE_PATH" in
      frontend/*|src/components/*|src/pages/*|src/hooks/*|src/styles/*) block_message "frontend" ;;
      design/*|wireframes/*|design-tokens/*) block_message "uiux" ;;
    esac
    ;;
  frontend)
    # Frontend cannot write to backend-specific directories (plugin source)
    case "$FILE_PATH" in
      scripts/*|agents/*|hooks/*|config/*) block_message "backend/plugin" ;;
      design/*|wireframes/*|design-tokens/*) block_message "uiux" ;;
    esac
    ;;
  uiux)
    # UI/UX cannot write to implementation directories
    case "$FILE_PATH" in
      src/*|scripts/*|agents/*|hooks/*|config/*) block_message "implementation" ;;
    esac
    ;;
esac

# Default: allow
exit 0
