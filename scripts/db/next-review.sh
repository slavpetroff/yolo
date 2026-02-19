#!/usr/bin/env bash
# next-review.sh — Find completed tasks that need QA review
# Usage: next-review.sh [--plan PLAN_ID] [--phase PHASE] [--db PATH]
set -euo pipefail

source "$(dirname "$0")/db-common.sh"

PLAN=""
PHASE=""

parse_db_flag "$@"
set -- ${_REMAINING_ARGS[@]+"${_REMAINING_ARGS[@]}"}
DB=$(db_path "$_DB_PATH")
require_db "$DB"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan) PLAN="$2"; shift 2 ;;
    --plan=*) PLAN="${1#--plan=}"; shift ;;
    --phase) PHASE="$2"; shift 2 ;;
    --phase=*) PHASE="${1#--phase=}"; shift ;;
    *) shift ;;
  esac
done

PLAN_FILTER=""
if [[ -n "$PLAN" ]]; then
  PLAN_FILTER="AND p.plan_num = '$PLAN'"
fi

PHASE_FILTER=""
if [[ -n "$PHASE" ]]; then
  PHASE_FILTER="AND p.phase = '$PHASE'"
fi

# Find complete tasks with no matching code_review entry
RESULTS=$(sqlite3 -batch "$DB" <<SQL
.output /dev/null
PRAGMA busy_timeout=5000;
PRAGMA journal_mode=WAL;
.output stdout
SELECT t.task_id, p.plan_num, t.action, t.status, t.completed_at
FROM tasks t
JOIN plans p ON t.plan_id = p.rowid
WHERE t.status = 'complete'
  $PLAN_FILTER
  $PHASE_FILTER
  AND NOT EXISTS (
    SELECT 1 FROM code_review cr
    WHERE cr.plan = p.plan_num
      AND cr.phase = p.phase
  )
ORDER BY t.completed_at ASC;
SQL
)

# No tasks need review — exit silently
if [[ -z "$RESULTS" ]]; then
  exit 0
fi

# Output each result line as TOON-formatted CSV
while IFS='|' read -r TASK_ID PLAN_NUM ACTION STATUS COMPLETED_AT; do
  echo "$TASK_ID,$PLAN_NUM,$ACTION,$STATUS,$COMPLETED_AT"
done <<< "$RESULTS"
