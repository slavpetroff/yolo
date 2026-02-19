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

# --- DB path resolution (DB is single source of truth) ---
PLANNING_DIR="$(cd "$PHASE_DIR/../.." 2>/dev/null && pwd)"
DB_PATH="$PLANNING_DIR/yolo.db"

if [ ! -f "$DB_PATH" ] || ! command -v sqlite3 &>/dev/null; then
  echo "Error: Database not found at $DB_PATH. Run init-db.sh first." >&2
  exit 1
fi

# --- Query plans from DB ---
PLANS_JSON=$(sqlite3 -json "$DB_PATH" "
  SELECT p.phase || '-' || p.plan_num AS id,
         p.title,
         p.wave,
         CASE WHEN s.status = 'complete' THEN 'complete' ELSE 'pending' END AS status
  FROM plans p
  LEFT JOIN summaries s ON s.plan_id = p.rowid
  WHERE p.phase = '$PHASE'
  ORDER BY p.plan_num;
" 2>/dev/null) || PLANS_JSON='[]'

if [ "$PLANS_JSON" = "[]" ] || [ -z "$PLANS_JSON" ]; then
  echo "No plans found in DB for phase $PHASE" >&2
  exit 1
fi

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

# Detect completed steps from DB
_critique_count=$(sqlite3 "$DB_PATH" "SELECT count(*) FROM critique WHERE phase='$PHASE';" 2>/dev/null || echo 0)
if [ "${_critique_count:-0}" -gt 0 ]; then
  STEPS_JSON=$(echo "$STEPS_JSON" | jq '.critique.status = "complete"')
fi

# Architecture check: .toon file is a generated context artifact, not a DB record.
# Check if plans exist (architecture step produces plan decomposition).
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
