#!/usr/bin/env bash
# get-task.sh — Retrieve a single task from the tasks table
# Usage: get-task.sh <plan-id> <task-id> [--db PATH] [--fields FIELD1,FIELD2]
# Output: TOON format (comma-separated values on one line)
# Exit 1 if task not found
set -euo pipefail

source "$(dirname "$0")/db-common.sh"

usage() {
  echo "Usage: get-task.sh <plan-id> <task-id> [--db PATH] [--fields FIELD1,FIELD2]" >&2
  exit 1
}

# Default fields
DEFAULT_FIELDS="task_id,action,files,done,spec"

# Parse args
FIELDS=""
[[ $# -eq 0 ]] && usage
parse_db_flag "$@"
DB=$(db_path "$_DB_PATH")
set -- ${_REMAINING_ARGS[@]+"${_REMAINING_ARGS[@]}"}

# Parse remaining flags
POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --fields)
      FIELDS="$2"
      shift 2
      ;;
    --fields=*)
      FIELDS="${1#--fields=}"
      shift
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

if [[ ${#POSITIONAL[@]} -lt 2 ]]; then
  usage
fi

PLAN_ID="${POSITIONAL[0]}"
TASK_ID="${POSITIONAL[1]}"

require_db "$DB"

# Use provided fields or defaults
SELECT_FIELDS="${FIELDS:-$DEFAULT_FIELDS}"

result=$(sql_query "$DB" "SELECT $SELECT_FIELDS FROM tasks WHERE plan_id='$PLAN_ID' AND task_id='$TASK_ID';")

if [[ -z "$result" ]]; then
  echo "error: task $TASK_ID not found in plan $PLAN_ID" >&2
  exit 1
fi

echo "$result"
