#!/usr/bin/env bash
# release-task.sh — Release a claimed task back to pending (unclaim/retry)
# Usage: release-task.sh --plan <PLAN_ID> --task <TASK_ID> [--reason TEXT] [--db PATH]
set -euo pipefail

source "$(dirname "$0")/db-common.sh"

PLAN=""
TASK=""
REASON=""

parse_db_flag "$@"
set -- ${_REMAINING_ARGS[@]+"${_REMAINING_ARGS[@]}"}
DB=$(db_path "$_DB_PATH")

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan) PLAN="$2"; shift 2 ;;
    --plan=*) PLAN="${1#--plan=}"; shift ;;
    --task) TASK="$2"; shift 2 ;;
    --task=*) TASK="${1#--task=}"; shift ;;
    --reason) REASON="$2"; shift 2 ;;
    --reason=*) REASON="${1#--reason=}"; shift ;;
    *) shift ;;
  esac
done

if [[ -z "$PLAN" || -z "$TASK" ]]; then
  echo "usage: release-task.sh --plan <PLAN_ID> --task <TASK_ID> [--reason TEXT] [--db PATH]" >&2
  exit 1
fi

require_db "$DB"

# Release: UPDATE only if status is 'in_progress', check changes()
CHANGES=$(sqlite3 -batch "$DB" <<SQL
.output /dev/null
PRAGMA busy_timeout=5000;
PRAGMA journal_mode=WAL;
PRAGMA foreign_keys=ON;
.output stdout
UPDATE tasks
SET status = 'pending',
    assigned_to = NULL,
    updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
WHERE task_id = '$TASK'
  AND status = 'in_progress'
  AND plan_id = (SELECT rowid FROM plans WHERE plan_num = '$PLAN' LIMIT 1);

SELECT changes();
SQL
)

if [[ "${CHANGES:-0}" -eq 0 ]]; then
  echo "error: task $TASK in plan $PLAN is not in_progress or does not exist" >&2
  exit 1
fi

# Optionally store retry reason in gaps table
if [[ -n "$REASON" ]]; then
  sqlite3 -batch "$DB" <<SQL
.output /dev/null
PRAGMA busy_timeout=5000;
PRAGMA journal_mode=WAL;
.output stdout
INSERT INTO gaps (id, sev, desc, st, res, phase, created_at)
SELECT
  'retry-${TASK}-' || strftime('%s', 'now'),
  'info',
  'Retry: task $TASK in plan $PLAN released',
  'open',
  '$REASON',
  p.phase,
  strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
FROM plans p WHERE p.plan_num = '$PLAN' LIMIT 1;
SQL
fi

echo "released $TASK back to pending"
