#!/usr/bin/env bash
set -euo pipefail

# dept-orchestrate.sh — Generate JSON spawn plan from resolve-departments.sh output
#
# Reads department config via resolve-departments.sh and outputs a structured
# JSON spawn plan with waves, department assignments, and gate names.
#
# Usage: dept-orchestrate.sh <config_path> <phase_dir>
# Output: JSON {waves:[{id:N,depts:[...],gate:string}],timeout_minutes:N}
#
# Examples:
#   Parallel UX+FE+BE: {"waves":[{"id":1,"depts":["uiux"],"gate":"handoff-ux-complete"},{"id":2,"depts":["frontend","backend"],"gate":"all-depts-complete"}],"timeout_minutes":30}
#   Backend only:       {"waves":[{"id":1,"depts":["backend"],"gate":"all-depts-complete"}],"timeout_minutes":30}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_TIMEOUT=30

# --- Arg validation ---
if [ $# -lt 2 ]; then
  echo "Usage: dept-orchestrate.sh <config_path> <phase_dir>" >&2
  exit 1
fi

CONFIG_PATH="$1"
PHASE_DIR="$2"

# --- Lead-to-department mapping ---
lead_to_dept() {
  case "$1" in
    ux-lead) echo "uiux" ;;
    fe-lead) echo "frontend" ;;
    lead)    echo "backend" ;;
    *)       echo "$1" ;;
  esac
}

# --- Gate assignment ---
assign_gate() {
  local depts_csv="$1" is_last="$2"
  if [ "$is_last" = true ]; then
    echo "all-depts-complete"
  elif [ "$depts_csv" = "uiux" ]; then
    echo "handoff-ux-complete"
  elif [ "$depts_csv" = "frontend" ]; then
    echo "handoff-frontend-complete"
  elif [ "$depts_csv" = "backend" ]; then
    echo "handoff-backend-complete"
  else
    echo "all-depts-complete"
  fi
}

# --- Step 1: Call resolve-departments.sh ---
RESOLVE_OUTPUT="$(bash "$SCRIPT_DIR/resolve-departments.sh" "$CONFIG_PATH")" || {
  echo "ERROR: resolve-departments.sh failed" >&2
  exit 1
}

# Parse key=value pairs into shell vars (case whitelist for safety)
multi_dept="" workflow="" active_depts="" leads_to_spawn="" spawn_order="" ux_active="" fe_active=""
while IFS= read -r line; do
  local_key="${line%%=*}"
  local_val="${line#*=}"
  case "$local_key" in
    multi_dept)      multi_dept="$local_val" ;;
    workflow)        workflow="$local_val" ;;
    active_depts)    active_depts="$local_val" ;;
    leads_to_spawn)  leads_to_spawn="$local_val" ;;
    spawn_order)     spawn_order="$local_val" ;;
    ux_active)       ux_active="$local_val" ;;
    fe_active)       fe_active="$local_val" ;;
  esac
done <<< "$RESOLVE_OUTPUT"

# --- Step 2: Build waves array ---
WAVE_ITEMS=()
WAVE_ID=1

if [ "$multi_dept" = "false" ] || [ "$workflow" = "backend_only" ]; then
  # Single backend wave
  WAVE_ITEMS+=("$(jq -n --argjson id "$WAVE_ID" --argjson depts '["backend"]' --arg gate "all-depts-complete" '{id:$id,depts:$depts,gate:$gate}')")

elif [ "$workflow" = "parallel" ]; then
  # Parse leads_to_spawn: | separates waves, , separates parallel depts within wave
  IFS='|' read -ra WAVES <<< "$leads_to_spawn"
  TOTAL_WAVES=${#WAVES[@]}

  for i in "${!WAVES[@]}"; do
    local_wave="${WAVES[$i]}"
    is_last=false
    if [ "$((i + 1))" -eq "$TOTAL_WAVES" ]; then
      is_last=true
    fi

    # Map leads to depts within this wave
    IFS=',' read -ra LEADS_IN_WAVE <<< "$local_wave"
    DEPTS_JSON="["
    DEPTS_CSV=""
    for j in "${!LEADS_IN_WAVE[@]}"; do
      dept=$(lead_to_dept "${LEADS_IN_WAVE[$j]}")
      if [ "$j" -gt 0 ]; then
        DEPTS_JSON+=","
        DEPTS_CSV+=","
      fi
      DEPTS_JSON+="\"$dept\""
      DEPTS_CSV+="$dept"
    done
    DEPTS_JSON+="]"

    GATE=$(assign_gate "$DEPTS_CSV" "$is_last")
    WAVE_ITEMS+=("$(jq -n --argjson id "$WAVE_ID" --argjson depts "$DEPTS_JSON" --arg gate "$GATE" '{id:$id,depts:$depts,gate:$gate}')")
    WAVE_ID=$((WAVE_ID + 1))
  done

elif [ "$workflow" = "sequential" ]; then
  # Parse leads_to_spawn: | separates each sequential lead
  IFS='|' read -ra WAVES <<< "$leads_to_spawn"
  TOTAL_WAVES=${#WAVES[@]}

  for i in "${!WAVES[@]}"; do
    local_lead="${WAVES[$i]}"
    is_last=false
    if [ "$((i + 1))" -eq "$TOTAL_WAVES" ]; then
      is_last=true
    fi

    dept=$(lead_to_dept "$local_lead")
    GATE=$(assign_gate "$dept" "$is_last")
    WAVE_ITEMS+=("$(jq -n --argjson id "$WAVE_ID" --argjson depts "[\"$dept\"]" --arg gate "$GATE" '{id:$id,depts:$depts,gate:$gate}')")
    WAVE_ID=$((WAVE_ID + 1))
  done
fi

# Guard: if no waves built, default to single backend wave
if [ ${#WAVE_ITEMS[@]} -eq 0 ]; then
  WAVE_ITEMS+=("$(jq -n --argjson id 1 --argjson depts '["backend"]' --arg gate "all-depts-complete" '{id:$id,depts:$depts,gate:$gate}')")
fi

# --- Step 3: Output JSON ---
printf '%s\n' "${WAVE_ITEMS[@]}" | jq -s --argjson timeout "$DEFAULT_TIMEOUT" '{waves:.,timeout_minutes:$timeout}'
