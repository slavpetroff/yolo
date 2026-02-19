#!/usr/bin/env bash
# get-summaries.sh — Retrieve plan summaries from the summaries table
# Usage: get-summaries.sh <phase-num> [--db PATH] [--status STATUS] [--plan PLAN_ID] [--fields FIELD1,FIELD2]
# Output: TOON format (one line per summary)
set -euo pipefail

source "$(dirname "$0")/db-common.sh"

usage() {
  echo "Usage: get-summaries.sh <phase-num> [--db PATH] [--status STATUS] [--plan PLAN_ID] [--fields FIELD1,FIELD2]" >&2
  exit 1
}

[[ $# -eq 0 ]] && usage

# Default fields
DEFAULT_FIELDS="plan_id,status,tasks_completed,tasks_total,files_modified"

# Parse args
STATUS_FILTER=""
PLAN_FILTER=""
FIELDS=""

parse_db_flag "$@"
DB=$(db_path "$_DB_PATH")
set -- ${_REMAINING_ARGS[@]+"${_REMAINING_ARGS[@]}"}

POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --status)   STATUS_FILTER="$2"; shift 2 ;;
    --status=*) STATUS_FILTER="${1#--status=}"; shift ;;
    --plan)     PLAN_FILTER="$2"; shift 2 ;;
    --plan=*)   PLAN_FILTER="${1#--plan=}"; shift ;;
    --fields)   FIELDS="$2"; shift 2 ;;
    --fields=*) FIELDS="${1#--fields=}"; shift ;;
    *)          POSITIONAL+=("$1"); shift ;;
  esac
done

if [[ ${#POSITIONAL[@]} -lt 1 ]]; then
  usage
fi

PHASE_NUM="${POSITIONAL[0]}"

require_db "$DB"

# Build query
SELECT_FIELDS="${FIELDS:-$DEFAULT_FIELDS}"
WHERE="WHERE phase='$PHASE_NUM'"

if [[ -n "$STATUS_FILTER" ]]; then
  WHERE="$WHERE AND status='$STATUS_FILTER'"
fi

if [[ -n "$PLAN_FILTER" ]]; then
  WHERE="$WHERE AND plan_id='$PLAN_FILTER'"
fi

result=$(sql_query "$DB" "SELECT $SELECT_FIELDS FROM summaries $WHERE ORDER BY plan_id ASC;")

if [[ -z "$result" ]]; then
  # Empty is valid — no matching summaries
  exit 0
fi

echo "$result"
