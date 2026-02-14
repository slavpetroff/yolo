#!/bin/bash
set -u
# PreToolUse hook: Block access to sensitive files
# Outputs JSON permissionDecision:"deny" + exit 0 to block tool calls.
# Fail-CLOSED: blocks on any parse error (never allow unvalidated input through).
# Uses jq for all JSON operations.

# Helper: output deny JSON and exit 0 (Claude Code reads JSON on exit 0)
deny() {
  jq -n --arg reason "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

# Verify jq is available
if ! command -v jq >/dev/null 2>&1; then
  deny "Blocked: jq not available, cannot validate file path"
fi

INPUT=$(cat 2>/dev/null) || deny "Blocked: could not read hook input"
[ -z "$INPUT" ] && deny "Blocked: empty hook input"

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // .tool_input.pattern // ""' 2>/dev/null) || deny "Blocked: could not parse file path from hook input"

if [ -z "$FILE_PATH" ]; then
  deny "Blocked: no file path in hook input"
fi

# Sensitive file patterns
if echo "$FILE_PATH" | grep -qE '\.env$|\.env\.|\.pem$|\.key$|\.cert$|\.p12$|\.pfx$|credentials\.json$|secrets\.json$|service-account.*\.json$|node_modules/|\.git/|dist/|build/'; then
  deny "Blocked: sensitive file ($FILE_PATH)"
fi

# Block GSD's .planning/ directory when YOLO is actively running.
if echo "$FILE_PATH" | grep -qF '.planning/' && ! echo "$FILE_PATH" | grep -qF '.yolo-planning/'; then
  if [ -f ".yolo-planning/.active-agent" ] || [ -f ".yolo-planning/.yolo-session" ]; then
    deny "Blocked: .planning/ is managed by GSD, not YOLO ($FILE_PATH)"
  fi
fi

# Block .yolo-planning/ when GSD isolation is enabled and no YOLO markers present.
if echo "$FILE_PATH" | grep -qF '.yolo-planning/'; then
  if [ -f ".yolo-planning/.gsd-isolation" ]; then
    if [ ! -f ".yolo-planning/.active-agent" ] && [ ! -f ".yolo-planning/.yolo-session" ]; then
      deny "Blocked: .yolo-planning/ is isolated from non-YOLO access ($FILE_PATH)"
    fi
  fi
fi

exit 0
