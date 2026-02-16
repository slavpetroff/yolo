#!/bin/bash
set -u
# PostToolUse hook: Validate git commit message format
# Non-blocking feedback only (always exit 0)

# Require jq for JSON output — fail-silent if missing (non-blocking hook)
if ! command -v jq &>/dev/null; then
  exit 0
fi

INPUT=$(cat)
COMMAND=$(jq -r '.tool_input.command // ""' <<< "$INPUT")

# Only check git commit commands
case "$COMMAND" in *git\ commit*) ;; *) exit 0 ;; esac

# Heredoc-style commits can't be parsed from a single line — skip validation
case "$COMMAND" in *cat\ \<\<*) exit 0 ;; esac

# Extract commit message from -m flag (POSIX-compatible, no GNU-only flags)
MSG=$(sed -n 's/.*-m[[:space:]]*"\([^"]*\)".*/\1/p' <<< "$COMMAND")
[ -z "$MSG" ] && MSG=$(sed -n "s/.*-m[[:space:]]*'\\([^']*\\)'.*/\\1/p" <<< "$COMMAND")
[ -z "$MSG" ] && MSG=$(sed -n 's/.*-m[[:space:]]*\([^[:space:]]*\).*/\1/p' <<< "$COMMAND")

if [ -z "$MSG" ]; then
  exit 0
fi

# Validate format: {type}({scope}): {desc}
VALID_TYPES="feat|fix|test|refactor|perf|docs|style|chore"
if ! grep -qE "^($VALID_TYPES)\(.+\): .+" <<< "$MSG"; then
  jq -n --arg msg "$MSG" '{
    "hookSpecificOutput": {
      "additionalContext": ("Commit message does not match format {type}({scope}): {desc}. Got: " + $msg)
    }
  }'
fi

# Version sync warning (YOLO plugin development only)
if [ -f ".claude-plugin/plugin.json" ] && [ -f "./scripts/bump-version.sh" ]; then
  PLUGIN_NAME=$(jq -r '.name // ""' .claude-plugin/plugin.json 2>/dev/null)
  if [ "$PLUGIN_NAME" = "yolo" ]; then
    VERIFY_OUTPUT=$(bash ./scripts/bump-version.sh --verify 2>&1) || {
      DETAILS=$(grep -A 10 "MISMATCH" <<< "$VERIFY_OUTPUT")
      jq -n --arg details "$DETAILS" '{
        "hookSpecificOutput": {
          "additionalContext": ("Version files are out of sync. Run: bash scripts/bump-version.sh\n" + $details)
        }
      }'
    }
  fi
fi

exit 0
