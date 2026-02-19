#!/usr/bin/env bash
# claim-task.sh — Explicitly claim a specific task for an agent
# Usage: claim-task.sh --plan <PLAN_ID> --task <TASK_ID> --agent <AGENT_NAME> [--db PATH]
set -euo pipefail

source "$(dirname "$0")/db-common.sh"

PLAN=""
TASK=""
AGENT=""

parse_db_flag "$@"
set -- ${_REMAINING_ARGS[@]+"${_REMAINING_ARGS[@]}"}
DB=$(db_path "$_DB_PATH")

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan) PLAN="$2"; shift 2 ;;
    --plan=*) PLAN="${1#--plan=}"; shift ;;
    --task) TASK="$2"; shift 2 ;;
    --task=*) TASK="${1#--task=}"; shift ;;
    --agent) AGENT="$2"; shift 2 ;;
    --agent=*) AGENT="${1#--agent=}"; shift ;;
    *) shift ;;
  esac
done

if [[ -z "$PLAN" || -z "$TASK" || -z "$AGENT" ]]; then
  echo "usage: claim-task.sh --plan <PLAN_ID> --task <TASK_ID> --agent <AGENT_NAME> [--db PATH]" >&2
  exit 1
fi

require_db "$DB"

# Atomic claim: UPDATE only if status is 'pending', check changes()
CHANGES=$(sqlite3 -batch "$DB" <<SQL
.output /dev/null
PRAGMA busy_timeout=5000;
PRAGMA journal_mode=WAL;
PRAGMA foreign_keys=ON;
.output stdout
UPDATE tasks
SET status = 'in_progress',
    assigned_to = '$AGENT',
    updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
WHERE task_id = '$TASK'
  AND status = 'pending'
  AND plan_id = (SELECT rowid FROM plans WHERE plan_num = '$PLAN' LIMIT 1);

SELECT changes();
SQL
)

if [[ "${CHANGES:-0}" -eq 0 ]]; then
  echo "error: task $TASK in plan $PLAN is not pending or does not exist" >&2
  exit 1
fi

echo "claimed $TASK for agent $AGENT"
