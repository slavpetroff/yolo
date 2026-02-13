#!/usr/bin/env bash
set -euo pipefail

# bootstrap-reqs-jsonl.sh — Generate reqs.jsonl from REQUIREMENTS.md
#
# Usage: bootstrap-reqs-jsonl.sh [REQUIREMENTS_MD] [OUTPUT_PATH]
#   REQUIREMENTS_MD  Path to REQUIREMENTS.md (default: .vbw-planning/REQUIREMENTS.md)
#   OUTPUT_PATH      Path to write reqs.jsonl (default: .vbw-planning/reqs.jsonl)
#
# Schema per line: {"id":"REQ-01","t":"title","pri":"must","st":"open","ac":""}
# Priority mapping: Must-have→must, Should-have→should, Nice-to-have→nice

REQUIREMENTS_MD="${1:-.vbw-planning/REQUIREMENTS.md}"
OUTPUT_PATH="${2:-.vbw-planning/reqs.jsonl}"

if [[ ! -f "$REQUIREMENTS_MD" ]]; then
  echo "Error: $REQUIREMENTS_MD not found" >&2
  exit 1
fi

command -v jq >/dev/null 2>&1 || { echo "Error: jq required" >&2; exit 1; }

mkdir -p "$(dirname "$OUTPUT_PATH")"

# Parse REQUIREMENTS.md line by line
# Format: ### REQ-NN: Title\n**Priority**
REQ_ID=""
REQ_TITLE=""
LINES_OUT=0

> "$OUTPUT_PATH"

while IFS= read -r line; do
  # Match requirement header: ### REQ-NN: Title
  if [[ "$line" =~ ^###[[:space:]]+(REQ-[0-9]+):[[:space:]]+(.*) ]]; then
    REQ_ID="${BASH_REMATCH[1]}"
    REQ_TITLE="${BASH_REMATCH[2]}"
    continue
  fi

  # Match priority line: **Must-have** or **Should-have** or **Nice-to-have**
  if [[ -n "$REQ_ID" ]] && [[ "$line" =~ ^\*\*([^*]+)\*\* ]]; then
    RAW_PRI=$(echo "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')
    case "$RAW_PRI" in
      must-have|must) PRI="must" ;;
      should-have|should) PRI="should" ;;
      nice-to-have|nice) PRI="nice" ;;
      *) PRI="must" ;;
    esac

    jq -cn --arg id "$REQ_ID" --arg t "$REQ_TITLE" --arg pri "$PRI" \
      '{"id":$id,"t":$t,"pri":$pri,"st":"open","ac":""}' >> "$OUTPUT_PATH"

    LINES_OUT=$((LINES_OUT + 1))
    REQ_ID=""
    REQ_TITLE=""
  fi
done < "$REQUIREMENTS_MD"

echo "Generated $OUTPUT_PATH ($LINES_OUT requirements)" >&2
exit 0
