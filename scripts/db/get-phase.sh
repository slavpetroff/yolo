#!/usr/bin/env bash
# get-phase.sh — Retrieve phase metadata from the phases table
# Usage: get-phase.sh <phase-num> [--db PATH] [--goals] [--reqs] [--success] [--full]
#        get-phase.sh --all-phases [--db PATH]
# Flags: --reqs-detail expands REQ-IDs into full descriptions from requirements table
# Output: TOON key-value format
# Exit 1 if phase not found
set -euo pipefail

source "$(dirname "$0")/db-common.sh"

usage() {
  echo "Usage: get-phase.sh <phase-num> [--db PATH] [--goals] [--reqs] [--reqs-detail] [--success] [--full]" >&2
  echo "       get-phase.sh --all-phases [--db PATH]" >&2
  exit 1
}

[[ $# -eq 0 ]] && usage

# Parse args
SHOW_GOALS=false
SHOW_REQS=false
SHOW_SUCCESS=false
SHOW_FULL=false
SHOW_REQS_DETAIL=false
ALL_PHASES=false

parse_db_flag "$@"
DB=$(db_path "$_DB_PATH")
set -- ${_REMAINING_ARGS[@]+"${_REMAINING_ARGS[@]}"}

POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --goals)       SHOW_GOALS=true; shift ;;
    --reqs)        SHOW_REQS=true; shift ;;
    --reqs-detail) SHOW_REQS_DETAIL=true; SHOW_REQS=true; shift ;;
    --success)     SHOW_SUCCESS=true; shift ;;
    --full)        SHOW_FULL=true; shift ;;
    --all-phases)  ALL_PHASES=true; shift ;;
    *)             POSITIONAL+=("$1"); shift ;;
  esac
done

require_db "$DB"

# --all-phases mode: list all phases as compact TOON
if $ALL_PHASES; then
  results=$(sql_query "$DB" "SELECT phase_num, slug, status FROM phases ORDER BY phase_num;")
  if [[ -z "$results" ]]; then
    echo "error: no phases found" >&2
    exit 1
  fi
  while IFS='|' read -r pnum slug status; do
    [[ -z "$pnum" ]] && continue
    echo "phase: $pnum | $slug | ${status:-planned}"
  done <<< "$results"
  exit 0
fi

if [[ ${#POSITIONAL[@]} -lt 1 ]]; then
  usage
fi

PHASE_NUM="${POSITIONAL[0]}"

# If no specific flags, default to --full
if ! $SHOW_GOALS && ! $SHOW_REQS && ! $SHOW_SUCCESS; then
  SHOW_FULL=true
fi

if $SHOW_FULL; then
  SHOW_GOALS=true
  SHOW_REQS=true
  SHOW_SUCCESS=true
fi

# Check phase exists
exists=$(sql_query "$DB" "SELECT count(*) FROM phases WHERE phase_num='$PHASE_NUM';")
if [[ "$exists" -eq 0 ]]; then
  echo "error: phase $PHASE_NUM not found" >&2
  exit 1
fi

# Build output
output=""
if $SHOW_GOALS; then
  goal=$(sql_query "$DB" "SELECT goal FROM phases WHERE phase_num='$PHASE_NUM';")
  slug=$(sql_query "$DB" "SELECT slug FROM phases WHERE phase_num='$PHASE_NUM';")
  output+="phase: $PHASE_NUM"$'\n'
  output+="slug: $slug"$'\n'
  output+="goal: $goal"$'\n'
fi

if $SHOW_REQS; then
  reqs=$(sql_query "$DB" "SELECT reqs FROM phases WHERE phase_num='$PHASE_NUM';")
  output+="reqs: $reqs"$'\n'
  # --reqs-detail: expand REQ-IDs to full descriptions
  if $SHOW_REQS_DETAIL; then
    # Check if requirements table exists
    if check_table "$DB" "requirements"; then
      # Extract REQ-NN patterns from reqs string
      req_ids=$(printf '%s' "$reqs" | grep -oE 'REQ-[0-9]+' || true)
      if [[ -n "$req_ids" ]]; then
        while IFS= read -r rid; do
          [[ -z "$rid" ]] && continue
          rid_esc=$(printf '%s' "$rid" | sed "s/'/''/g")
          detail=$(sql_query "$DB" "SELECT description FROM requirements WHERE req_id='$rid_esc';")
          if [[ -n "$detail" ]]; then
            output+="  $rid: $detail"$'\n'
          fi
        done <<< "$req_ids"
      fi
    fi
  fi
fi

if $SHOW_SUCCESS; then
  success=$(sql_query "$DB" "SELECT success_criteria FROM phases WHERE phase_num='$PHASE_NUM';")
  output+="success: $success"$'\n'
fi

# Print without trailing newline
printf '%s' "$output" | sed '/^$/d'
