#!/bin/bash
set -u
# PreToolUse hook: Block access to sensitive files
# Exit 2 = block tool call, Exit 0 = allow
# Fail-CLOSED: exit 2 on any parse error (never allow unvalidated input through)

# Verify jq is available
if ! command -v jq >/dev/null 2>&1; then
  echo "Blocked: jq not available, cannot validate file path" >&2
  exit 2
fi

INPUT=$(cat 2>/dev/null) || exit 2
[ -z "$INPUT" ] && exit 2

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // .tool_input.pattern // ""' 2>/dev/null) || exit 2

if [ -z "$FILE_PATH" ]; then
  exit 2
fi

# Sensitive file patterns
if echo "$FILE_PATH" | grep -qE '\.env$|\.env\.|\.pem$|\.key$|\.cert$|\.p12$|\.pfx$|credentials\.json$|secrets\.json$|service-account.*\.json$|node_modules/|\.git/|dist/|build/'; then
  echo "Blocked: sensitive file ($FILE_PATH)" >&2
  exit 2
fi

# Block GSD's .planning/ directory when YOLO is actively running.
# Only enforce when YOLO markers are present (session or agent), so GSD can
# still write to its own directory when YOLO is not the active caller.
if echo "$FILE_PATH" | grep -qF '.planning/' && ! echo "$FILE_PATH" | grep -qF '.yolo-planning/'; then
  if [ -f ".yolo-planning/.active-agent" ] || [ -f ".yolo-planning/.yolo-session" ]; then
    echo "Blocked: .planning/ is managed by GSD, not YOLO ($FILE_PATH)" >&2
    exit 2
  fi
fi

# Block .yolo-planning/ when GSD isolation is enabled and no YOLO markers present.
# .gsd-isolation = opt-in flag created during /yolo:init consent flow.
# .active-agent = YOLO subagent is running (managed by agent-start.sh / agent-stop.sh).
# .yolo-session = YOLO command is active (managed by prompt-preflight.sh / session-stop.sh).
if echo "$FILE_PATH" | grep -qF '.yolo-planning/'; then
  if [ -f ".yolo-planning/.gsd-isolation" ]; then
    if [ ! -f ".yolo-planning/.active-agent" ] && [ ! -f ".yolo-planning/.yolo-session" ]; then
      echo "Blocked: .yolo-planning/ is isolated from non-YOLO access ($FILE_PATH)" >&2
      exit 2
    fi
  fi
fi

exit 0
