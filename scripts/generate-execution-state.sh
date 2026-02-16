#!/usr/bin/env bash
set -euo pipefail

# generate-execution-state.sh — Generate initial .execution-state.json from plan.jsonl files
#
# Scans *.plan.jsonl in a phase directory, extracts metadata, and builds the
# full execution state schema per execute-protocol.md Step 3 item 7.
#
# Usage: generate-execution-state.sh --phase-dir <path> --phase <N> [--force]
# Output: writes .execution-state.json to phase dir, prints path to stdout
# Exit codes: 0 = success, 1 = error

# --- jq dependency check ---
if ! command -v jq &>/dev/null; then
  echo '{"error":"jq is required but not installed. Install: brew install jq (macOS) / apt install jq (Linux)"}' >&2
  exit 1
fi

# --- Arg parsing ---
PHASE_DIR=""
PHASE=""
FORCE=false

while [ $# -gt 0 ]; do
  case "$1" in
    --phase-dir) PHASE_DIR="$2"; shift 2 ;;
    --phase) PHASE="$2"; shift 2 ;;
    --force) FORCE=true; shift ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

if [ -z "$PHASE_DIR" ] || [ -z "$PHASE" ]; then
  echo "Usage: generate-execution-state.sh --phase-dir <path> --phase <N> [--force]" >&2
  exit 1
fi

if [ ! -d "$PHASE_DIR" ]; then
  echo "Error: Phase directory does not exist: $PHASE_DIR" >&2
  exit 1
fi

# --- Constants ---
OUTPUT_FILE="$PHASE_DIR/.execution-state.json"
STEP_NAMES="critique architecture planning design_review test_authoring implementation code_review qa security signoff"

# --- Resume check ---
if [ -f "$OUTPUT_FILE" ] && [ "$FORCE" != "true" ]; then
  existing_status=$(jq -r '.status // ""' "$OUTPUT_FILE" 2>/dev/null) || true
  if [ "$existing_status" = "running" ]; then
    echo "Existing state found (status: running). Use --force to regenerate." >&2
    exit 1
  fi
  if [ "$existing_status" = "complete" ]; then
    echo "Phase already complete." >&2
    exit 1
  fi
fi

# --- Extract phase name from directory basename ---
PHASE_NAME=$(basename "$PHASE_DIR" | sed 's/^[0-9]*-//')

# --- Scan plan files ---
PLAN_FILES=$(ls "$PHASE_DIR"/*.plan.jsonl 2>/dev/null) || true
if [ -z "$PLAN_FILES" ]; then
  echo "No plan.jsonl files found in $PHASE_DIR" >&2
  exit 1
fi

# --- Build plans array ---
PLANS_JSON='[]'
while IFS= read -r plan_file; do
  [ -z "$plan_file" ] && continue
  [ ! -f "$plan_file" ] && continue

  local_header=$(head -1 "$plan_file") || continue

  # Extract fields
  local_p=$(echo "$local_header" | jq -r '.p // ""' 2>/dev/null) || continue
  local_n=$(echo "$local_header" | jq -r '.n // ""' 2>/dev/null) || continue
  local_title=$(echo "$local_header" | jq -r '.t // ""' 2>/dev/null) || continue
  local_wave=$(echo "$local_header" | jq -r '.w // 1' 2>/dev/null) || continue

  local_id="${local_p}-${local_n}"

  # Determine status: check for completed summary
  local_status="pending"
  local_summary_file="$PHASE_DIR/${local_id}.summary.jsonl"
  if [ -f "$local_summary_file" ]; then
    local_summary_status=$(head -1 "$local_summary_file" | jq -r '.s // ""' 2>/dev/null) || true
    if [ "$local_summary_status" = "complete" ]; then
      local_status="complete"
    fi
  fi

  PLANS_JSON=$(echo "$PLANS_JSON" | jq \
    --arg id "$local_id" \
    --arg title "$local_title" \
    --argjson wave "$local_wave" \
    --arg status "$local_status" \
    '. + [{id:$id,title:$title,wave:$wave,status:$status}]')

done <<< "$PLAN_FILES"

# --- Compute waves ---
TOTAL_WAVES=$(echo "$PLANS_JSON" | jq '[.[].wave] | max')
CURRENT_WAVE=$(echo "$PLANS_JSON" | jq '[.[] | select(.status != "complete") | .wave] | if length > 0 then min else ([.[].wave] | max) end')

# --- Build steps object ---
# Start with all 10 steps as pending
STEPS_JSON=$(jq -n '{}'  )
for step_name in $STEP_NAMES; do
  STEPS_JSON=$(echo "$STEPS_JSON" | jq \
    --arg s "$step_name" \
    '. + {($s): {status:"pending",started_at:"",completed_at:"",artifact:"",reason:""}}')
done

# Detect completed steps from existing artifacts
if [ -f "$PHASE_DIR/critique.jsonl" ] && [ -s "$PHASE_DIR/critique.jsonl" ]; then
  STEPS_JSON=$(echo "$STEPS_JSON" | jq '.critique.status = "complete"')
fi

if [ -f "$PHASE_DIR/architecture.toon" ] && [ -s "$PHASE_DIR/architecture.toon" ]; then
  STEPS_JSON=$(echo "$STEPS_JSON" | jq '.architecture.status = "complete"')
fi

# Planning is being set to complete since we are generating state
STEPS_JSON=$(echo "$STEPS_JSON" | jq '.planning.status = "complete"')

# --- Assemble full state ---
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
PHASE_NUM=$((10#$PHASE))

TEMP_FILE="${OUTPUT_FILE}.tmp.$$"
jq -n \
  --argjson phase "$PHASE_NUM" \
  --arg phase_name "$PHASE_NAME" \
  --arg status "running" \
  --arg started_at "$NOW" \
  --arg step "planning" \
  --argjson wave "$CURRENT_WAVE" \
  --argjson total_waves "$TOTAL_WAVES" \
  --argjson plans "$PLANS_JSON" \
  --argjson steps "$STEPS_JSON" \
  '{
    phase: $phase,
    phase_name: $phase_name,
    status: $status,
    started_at: $started_at,
    step: $step,
    wave: $wave,
    total_waves: $total_waves,
    plans: $plans,
    steps: $steps
  }' > "$TEMP_FILE"

mv "$TEMP_FILE" "$OUTPUT_FILE"

# --- Output path ---
echo "$OUTPUT_FILE"
