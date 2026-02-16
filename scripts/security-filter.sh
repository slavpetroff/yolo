#!/bin/bash
set -u
# PreToolUse hook: Block access to sensitive files
# Outputs JSON permissionDecision:"deny" + exit 0 to block tool calls.
# Fail-CLOSED: blocks on any parse error (never allow unvalidated input through).
# Uses jq for all JSON operations.

# Helper: output deny JSON and exit 0 (Claude Code reads JSON on exit 0)
# Uses printf instead of jq -n to save ~7.3ms per deny call.
# Reason strings are hardcoded literals — no injection risk.
deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
  exit 0
}

# Verify jq is available
if ! command -v jq >/dev/null 2>&1; then
  deny "Blocked: jq not available, cannot validate file path"
fi

INPUT=$(cat 2>/dev/null) || deny "A security check could not complete. Try again, or run /yolo:init to reset hooks."
[ -z "$INPUT" ] && deny "A security check could not complete. Try again, or run /yolo:init to reset hooks."

FILE_PATH=$(jq -r '.tool_input.file_path // .tool_input.path // .tool_input.pattern // ""' <<< "$INPUT" 2>/dev/null) || deny "A security check could not complete. Try again, or run /yolo:init to reset hooks."

if [ -z "$FILE_PATH" ]; then
  deny "A security check could not complete. Try again, or run /yolo:init to reset hooks."
fi

# Sensitive file patterns
if grep -qE '\.env$|\.env\.|\.pem$|\.key$|\.cert$|\.p12$|\.pfx$|credentials\.json$|secrets\.json$|service-account.*\.json$|node_modules/|\.git/|dist/|build/' <<< "$FILE_PATH"; then
  deny "This file is protected ($FILE_PATH). Sensitive files cannot be modified through YOLO."
fi

# Block GSD's .planning/ directory when YOLO is actively running.
# Uses case instead of grep to avoid fork+exec overhead.
case "$FILE_PATH" in
  *.yolo-planning/*) ;;  # Not GSD's .planning/ — skip this check
  *.planning/*|.planning/*)
    if [ -f ".yolo-planning/.active-agent" ] || [ -f ".yolo-planning/.yolo-session" ]; then
      deny "Blocked: .planning/ is managed by GSD, not YOLO ($FILE_PATH)"
    fi
    ;;
esac

# Block .yolo-planning/ when GSD isolation is enabled and no YOLO markers present.
case "$FILE_PATH" in
  *.yolo-planning/*|.yolo-planning/*)
    if [ -f ".yolo-planning/.gsd-isolation" ]; then
      if [ ! -f ".yolo-planning/.active-agent" ] && [ ! -f ".yolo-planning/.yolo-session" ]; then
        deny "Blocked: .yolo-planning/ is isolated from non-YOLO access ($FILE_PATH)"
      fi
    fi
    ;;
esac

exit 0
