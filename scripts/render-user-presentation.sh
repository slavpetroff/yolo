#!/usr/bin/env bash
set -u

# render-user-presentation.sh — Render PO user_presentation to formatted string
#
# Reads user_presentation JSON from PO agent and formats it for AskUserQuestion.
# Enforces Owner-first proxy: PO produces user_presentation, orchestrator renders it.
#
# Usage: render-user-presentation.sh --presentation <path-to-json>
# Output: Formatted markdown string to stdout
# Exit codes: 0 = success, 1 = usage/runtime error
#
# Expected JSON schema:
#   {
#     "type": "question|confirmation|choice",
#     "content": "The question or statement text",
#     "options": ["Option A", "Option B", ...],
#     "context": "Background context for the user"
#   }

# --- jq dependency check ---
if ! command -v jq &>/dev/null; then
  echo '{"error":"jq is required but not installed"}' >&2
  exit 1
fi

# --- Arg parsing ---
PRESENTATION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --presentation)
      PRESENTATION="$2"
      shift 2
      ;;
    *)
      echo "Usage: render-user-presentation.sh --presentation <path-to-json>" >&2
      exit 1
      ;;
  esac
done

if [ -z "$PRESENTATION" ]; then
  echo "Error: --presentation is required" >&2
  exit 1
fi

if [ ! -f "$PRESENTATION" ]; then
  echo "Error: presentation file not found: $PRESENTATION" >&2
  exit 1
fi

# --- Validate JSON ---
if ! jq -e '.' "$PRESENTATION" >/dev/null 2>&1; then
  echo "Error: presentation file is not valid JSON: $PRESENTATION" >&2
  exit 1
fi

# --- Extract fields ---
PTYPE=$(jq -r '.type // "question"' "$PRESENTATION")
CONTENT=$(jq -r '.content // ""' "$PRESENTATION")
CONTEXT=$(jq -r '.context // ""' "$PRESENTATION")
OPTIONS_COUNT=$(jq '.options // [] | length' "$PRESENTATION")

# --- Build formatted output ---
OUTPUT=""

# Add context block if present
if [ -n "$CONTEXT" ] && [ "$CONTEXT" != "null" ]; then
  OUTPUT="${OUTPUT}> ${CONTEXT}

"
fi

# Add content
if [ -n "$CONTENT" ] && [ "$CONTENT" != "null" ]; then
  OUTPUT="${OUTPUT}${CONTENT}"
fi

# Add numbered options if present
if [ "$OPTIONS_COUNT" -gt 0 ]; then
  OUTPUT="${OUTPUT}

"
  for (( i=0; i<OPTIONS_COUNT; i++ )); do
    OPT=$(jq -r ".options[$i]" "$PRESENTATION")
    NUM=$((i + 1))
    OUTPUT="${OUTPUT}${NUM}. ${OPT}
"
  done
fi

# Add type-specific prompt suffix
case "$PTYPE" in
  confirmation)
    OUTPUT="${OUTPUT}
Please confirm (yes/no)."
    ;;
  choice)
    if [ "$OPTIONS_COUNT" -gt 0 ]; then
      OUTPUT="${OUTPUT}
Enter your choice (1-${OPTIONS_COUNT})."
    fi
    ;;
  question)
    # No suffix needed for open questions
    ;;
esac

printf '%s' "$OUTPUT"
