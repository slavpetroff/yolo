#!/bin/bash
set -u
# PostToolUse/SubagentStop: Validate SUMMARY structure (non-blocking, exit 0)
# Thin wrapper — delegates to validate.sh --type summary

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATE="$SCRIPT_DIR/validate.sh"

if [ -x "$VALIDATE" ]; then
  exec bash "$VALIDATE" --type summary
fi

# Graceful fallback: inline validation if validate.sh not available
INPUT=$(cat)
# Fast exit for non-summary files (check raw stdin for summary patterns)
case "$INPUT" in
  *.summary.jsonl*|*SUMMARY.md*) ;;
  *) exit 0 ;;
esac

FILE_PATH=$(jq -r '.tool_input.file_path // .tool_input.command // ""' <<< "$INPUT")

IS_JSONL=false; IS_MD=false
case "$FILE_PATH" in
  *.yolo-planning/*.summary.jsonl) IS_JSONL=true ;;
  *.yolo-planning/*SUMMARY.md) IS_MD=true ;;
esac

[ "$IS_JSONL" != true ] && [ "$IS_MD" != true ] && exit 0
[ -f "$FILE_PATH" ] || exit 0

MISSING=""

if [ "$IS_JSONL" = true ]; then
  # JSONL validation: batch field checks into single jq call
  if command -v jq >/dev/null 2>&1; then
    MISSING=$(jq -r '[
      (if has("p") then empty else "Missing '\''p'\'' (phase) field. " end),
      (if has("s") then empty else "Missing '\''s'\'' (status) field. " end),
      (if has("fm") then empty else "Missing '\''fm'\'' (files_modified) field. " end),
      (if has("sg") then (if (.sg | type == "array" and all(type == "string" and length > 0)) then empty else "Field '\''sg'\'' must be an array of non-empty strings. " end) else empty end)
    ] | join("")' "$FILE_PATH" 2>/dev/null)
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
