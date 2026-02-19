#!/usr/bin/env bash
# complete-task.sh — Mark a task as complete in the artifact store
# Usage: complete-task.sh <TASK_ID> --plan <PLAN_ID>
#        [--files FILE1,FILE2] [--summary TEXT] [--commit HASH] [--db PATH]
set -euo pipefail

source "$(dirname "$0")/db-common.sh"

# Parse arguments
TASK_ID=""
PLAN_ID=""
FILES=""
SUMMARY=""
COMMIT_HASH=""

parse_db_flag "$@"
DB_EXPLICIT="$_DB_PATH"
set -- "${_REMAINING_ARGS[@]}"

# First positional arg is TASK_ID
if [[ $# -gt 0 && "${1:0:1}" != "-" ]]; then
  TASK_ID="$1"
  shift
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan)    PLAN_ID="$2";     shift 2 ;;
    --files)   FILES="$2";       shift 2 ;;
    --summary) SUMMARY="$2";     shift 2 ;;
    --commit)  COMMIT_HASH="$2"; shift 2 ;;
    *) echo "error: unknown flag: $1" >&2; exit 1 ;;
  esac
done

# Validate required fields
if [[ -z "$TASK_ID" ]]; then
  echo "error: TASK_ID is required (first positional arg)" >&2
  exit 1
fi
if [[ -z "$PLAN_ID" ]]; then
  echo "error: --plan is required" >&2
  exit 1
fi

DB=$(db_path "$DB_EXPLICIT")
require_db "$DB"

# Extract phase and plan_num
phase="${PLAN_ID%%-*}"
plan_num="${PLAN_ID#*-}"

# Resolve plan rowid
plan_rowid=$(sql_query "$DB" \
  "SELECT rowid FROM plans WHERE phase='$phase' AND plan_num='$plan_num';")

if [[ -z "$plan_rowid" ]]; then
  echo "error: plan $PLAN_ID not found" >&2
  exit 1
fi

# Check task exists and is not already complete
current_status=$(sql_query "$DB" \
  "SELECT status FROM tasks WHERE plan_id=$plan_rowid AND task_id='$TASK_ID';")

if [[ -z "$current_status" ]]; then
  echo "error: task $TASK_ID not found in plan $PLAN_ID" >&2
  exit 1
fi

if [[ "$current_status" == "complete" ]]; then
  echo "error: task $TASK_ID is already complete" >&2
  exit 1
fi

# Convert comma-separated files to JSON array
files_json=""
if [[ -n "$FILES" ]]; then
  files_json=$(echo "$FILES" | tr ',' '\n' | jq -R . | jq -s .)
fi

# Escape single quotes for SQL
esc() { echo "${1//\'/\'\'}"; }

summary_esc=$(esc "$SUMMARY")
files_esc=$(esc "$files_json")
commit_esc=$(esc "$COMMIT_HASH")

# Build SET clause
set_clause="status='complete', completed_at=strftime('%Y-%m-%dT%H:%M:%SZ', 'now'), updated_at=strftime('%Y-%m-%dT%H:%M:%SZ', 'now')"
if [[ -n "$files_json" ]]; then
  set_clause="$set_clause, files_written='$files_esc'"
fi
if [[ -n "$SUMMARY" ]]; then
  set_clause="$set_clause, summary='$summary_esc'"
fi

sql_with_retry "$DB" \
  "UPDATE tasks SET $set_clause WHERE plan_id=$plan_rowid AND task_id='$TASK_ID';"

echo "ok: $TASK_ID complete (plan $PLAN_ID)"
