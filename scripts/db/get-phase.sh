#!/usr/bin/env bash
# get-phase.sh — Retrieve phase metadata from the phases table
# Usage: get-phase.sh <phase-num> [--db PATH] [--goals] [--reqs] [--success] [--full]
# Output: TOON key-value format
# Exit 1 if phase not found
set -euo pipefail

source "$(dirname "$0")/db-common.sh"

usage() {
  echo "Usage: get-phase.sh <phase-num> [--db PATH] [--goals] [--reqs] [--success] [--full]" >&2
  exit 1
}

[[ $# -eq 0 ]] && usage

# Parse args
SHOW_GOALS=false
SHOW_REQS=false
SHOW_SUCCESS=false
SHOW_FULL=false

parse_db_flag "$@"
DB=$(db_path "$_DB_PATH")
set -- ${_REMAINING_ARGS[@]+"${_REMAINING_ARGS[@]}"}

POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --goals)   SHOW_GOALS=true; shift ;;
    --reqs)    SHOW_REQS=true; shift ;;
    --success) SHOW_SUCCESS=true; shift ;;
    --full)    SHOW_FULL=true; shift ;;
    *)         POSITIONAL+=("$1"); shift ;;
  esac
done

if [[ ${#POSITIONAL[@]} -lt 1 ]]; then
  usage
fi

PHASE_NUM="${POSITIONAL[0]}"

require_db "$DB"

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
fi

if $SHOW_SUCCESS; then
  success=$(sql_query "$DB" "SELECT success_criteria FROM phases WHERE phase_num='$PHASE_NUM';")
  output+="success: $success"$'\n'
fi

# Print without trailing newline
printf '%s' "$output" | sed '/^$/d'
