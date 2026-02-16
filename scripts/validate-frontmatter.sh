#!/bin/bash
set -u
# PostToolUse hook: Validate YAML frontmatter in markdown files
# Non-blocking feedback only (always exit 0)

if ! command -v jq &>/dev/null; then
  exit 0
fi

INPUT=$(cat 2>/dev/null) || exit 0
[ -z "$INPUT" ] && exit 0
FILE_PATH=$(jq -r '.tool_input.file_path // ""' <<< "$INPUT" 2>/dev/null) || exit 0

# Only check .md files
case "$FILE_PATH" in
  *.md) ;;
  *) exit 0 ;;
esac

[ ! -f "$FILE_PATH" ] && exit 0
HEAD=$(head -1 "$FILE_PATH" 2>/dev/null)
[ "$HEAD" != "---" ] && exit 0

# Single awk pass: extract frontmatter, find description, check all conditions
WARNING=$(awk '
  BEGIN { in_fm=0; found_desc=0; desc_val=""; has_continuation=0 }
  NR==1 && $0=="---" { in_fm=1; next }
  in_fm && $0=="---" { in_fm=0; next }
  !in_fm { next }
  /^description:/ {
    found_desc=1
    sub(/^description:[[:space:]]*/, "")
    desc_val=$0
    next
  }
  found_desc==1 && /^[[:space:]]/ { has_continuation=1; next }
  found_desc==1 && !/^[[:space:]]/ { found_desc=2 }
  END {
    if (!found_desc) print "ok"
    else if (desc_val ~ /^[|>]/) print "multiline_indicator"
    else if (desc_val == "" && has_continuation) print "multiline_empty"
    else if (desc_val == "" && !has_continuation) print "empty"
    else if (has_continuation) print "multiline_continuation"
    else print "ok"
  }
' "$FILE_PATH" 2>/dev/null)

case "$WARNING" in
  multiline_indicator|multiline_empty|multiline_continuation)
    jq -n --arg file "$FILE_PATH" '{
      "hookSpecificOutput": {
        "additionalContext": ("Frontmatter warning: description field in " + $file + " must be a single line. Multi-line descriptions break plugin command/skill discovery. Fix: collapse to one line.")
      }
    }'
    ;;
  empty)
    jq -n --arg file "$FILE_PATH" '{
      "hookSpecificOutput": {
        "additionalContext": ("Frontmatter warning: description field in " + $file + " is empty. Empty descriptions break plugin command/skill discovery. Fix: add a single-line description.")
      }
    }'
    ;;
  ok|*) ;;
esac

exit 0
