#!/bin/bash
set -u
# PostToolUse/SubagentStop: Validate SUMMARY.md structure (non-blocking, exit 0)

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.command // ""')

# Check both JSONL and legacy MD summary files in .vbw-planning/
IS_JSONL=false
IS_MD=false
if echo "$FILE_PATH" | grep -qE '\.vbw-planning/.*\.summary\.jsonl$'; then
  IS_JSONL=true
elif echo "$FILE_PATH" | grep -qE '\.vbw-planning/.*SUMMARY\.md$'; then
  IS_MD=true
fi

if [ "$IS_JSONL" != true ] && [ "$IS_MD" != true ]; then
  exit 0
fi

[ -f "$FILE_PATH" ] || exit 0

MISSING=""

if [ "$IS_JSONL" = true ]; then
  # JSONL validation: check required fields
  if command -v jq >/dev/null 2>&1; then
    if ! jq -e '.p' "$FILE_PATH" >/dev/null 2>&1; then
      MISSING="Missing 'p' (phase) field. "
    fi
    if ! jq -e '.s' "$FILE_PATH" >/dev/null 2>&1; then
      MISSING="${MISSING}Missing 's' (status) field. "
    fi
    if ! jq -e '.fm' "$FILE_PATH" >/dev/null 2>&1; then
      MISSING="${MISSING}Missing 'fm' (files_modified) field. "
    fi
  fi
else
  # Legacy MD validation
  if ! head -1 "$FILE_PATH" | grep -q '^---$'; then
    MISSING="Missing YAML frontmatter. "
  fi
  if ! grep -q "## What Was Built" "$FILE_PATH"; then
    MISSING="${MISSING}Missing '## What Was Built'. "
  fi
  if ! grep -q "## Files Modified" "$FILE_PATH"; then
    MISSING="${MISSING}Missing '## Files Modified'. "
  fi
fi

if [ -n "$MISSING" ]; then
  jq -n --arg msg "$MISSING" '{
    "hookSpecificOutput": {
      "additionalContext": ("SUMMARY validation: " + $msg)
    }
  }'
fi

exit 0
