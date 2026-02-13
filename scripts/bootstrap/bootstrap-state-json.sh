#!/usr/bin/env bash
set -euo pipefail

# bootstrap-state-json.sh — Generate state.json for machine consumption
#
# Usage: bootstrap-state-json.sh OUTPUT_PATH MILESTONE_NAME PHASE_COUNT
#   OUTPUT_PATH      Path to write state.json
#   MILESTONE_NAME   Name of the current milestone
#   PHASE_COUNT      Number of phases in the roadmap

if [[ $# -lt 3 ]]; then
  echo "Usage: bootstrap-state-json.sh OUTPUT_PATH MILESTONE_NAME PHASE_COUNT" >&2
  exit 1
fi

OUTPUT_PATH="$1"
MILESTONE_NAME="$2"
PHASE_COUNT="$3"

STARTED=$(date +%Y-%m-%d)

mkdir -p "$(dirname "$OUTPUT_PATH")"

jq -n \
  --arg ms "$MILESTONE_NAME" \
  --argjson ph 1 \
  --argjson tt "$PHASE_COUNT" \
  --arg st "planning" \
  --arg step "none" \
  --argjson pr 0 \
  --arg started "$STARTED" \
  '{ms:$ms, ph:$ph, tt:$tt, st:$st, step:$step, pr:$pr, started:$started}' \
  > "$OUTPUT_PATH"

exit 0
