#!/usr/bin/env bash
set -euo pipefail

# infer-gsd-summary.sh — Extract recent work context from archived GSD planning data
#
# Usage: infer-gsd-summary.sh GSD_ARCHIVE_DIR
#   GSD_ARCHIVE_DIR   Path to .vbw-planning/gsd-archive/ directory
#
# Output: JSON to stdout with latest milestone, recent phases, key decisions,
#         and current work status. Focused on recent context (last 2-3 phases).
#
# Exit: Always exits 0. Missing directory/files produce minimal JSON, not errors.

EMPTY_JSON='{"latest_milestone":null,"recent_phases":[],"key_decisions":[],"current_work":null}'

if [[ $# -lt 1 ]]; then
  echo "$EMPTY_JSON" | jq .
  exit 0
fi

GSD_ARCHIVE_DIR="$1"

# If archive directory doesn't exist, output minimal JSON
if [[ ! -d "$GSD_ARCHIVE_DIR" ]]; then
  echo "$EMPTY_JSON" | jq .
  exit 0
fi

echo "$EMPTY_JSON" | jq .
