#!/bin/bash
# PreToolUse hook: Block access to sensitive files
# Exit 2 = block tool call, Exit 0 = allow
# Exit 0 on ANY error (fail-open: never block legitimate work)

INPUT=$(cat 2>/dev/null) || exit 0
[ -z "$INPUT" ] && exit 0

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // .tool_input.pattern // ""' 2>/dev/null) || exit 0

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# Sensitive file patterns
if echo "$FILE_PATH" | grep -qE '\.env$|\.env\.|\.pem$|\.key$|\.cert$|\.p12$|\.pfx$|credentials\.json$|secrets\.json$|service-account.*\.json$|node_modules/|\.git/|dist/|build/'; then
  echo "Blocked: sensitive file ($FILE_PATH)" >&2
  exit 2
fi

# Block GSD's .planning/ directory — prevent cross-tool contamination.
# Match any path containing .planning/ but exclude .vbw-planning/ (VBW's own).
if echo "$FILE_PATH" | grep -qF '.planning/' && ! echo "$FILE_PATH" | grep -qF '.vbw-planning/'; then
  echo "Blocked: .planning/ is managed by GSD, not VBW ($FILE_PATH)" >&2
  exit 2
fi

exit 0
