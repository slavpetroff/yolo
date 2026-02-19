#!/usr/bin/env bash
# next-task.sh — Find and atomically claim next unblocked pending task
# Usage: next-task.sh [--dept DEPT] [--plan PLAN_ID] [--db PATH]
set -euo pipefail

source "$(dirname "$0")/db-common.sh"

DEPT=""
PLAN=""

parse_db_flag "$@"
set -- ${_REMAINING_ARGS[@]+"${_REMAINING_ARGS[@]}"}
DB=$(db_path "$_DB_PATH")
require_db "$DB"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dept) DEPT="$2"; shift 2 ;;
    --dept=*) DEPT="${1#--dept=}"; shift ;;
    --plan) PLAN="$2"; shift 2 ;;
    --plan=*) PLAN="${1#--plan=}"; shift ;;
    *) shift ;;
  esac
done

# Agent name: use YOLO_AGENT env var or hostname-pid
AGENT="${YOLO_AGENT:-$(hostname -s 2>/dev/null || echo "agent")-$$}"

# Build WHERE clauses for optional filters
DEPT_FILTER=""
if [[ -n "$DEPT" ]]; then
  DEPT_FILTER="AND p.effort = '$DEPT'"
  # dept is not a column on plans yet; filter by plan title or skip
  # For now, filter is a no-op placeholder until dept column exists
  DEPT_FILTER=""
fi

PLAN_FILTER=""
if [[ -n "$PLAN" ]]; then
  PLAN_FILTER="AND p.plan_num = '$PLAN'"
fi

# Set pragmas (suppress output)
sqlite3 -batch "$DB" "PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000; PRAGMA foreign_keys=ON;" >/dev/null

# Atomic claim: find first pending task with all deps complete, update it
# Uses a single UPDATE with subquery to prevent race conditions
RESULT=$(sqlite3 -batch "$DB" <<SQL
UPDATE tasks
SET status = 'in_progress',
    assigned_to = '$AGENT',
    updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
WHERE rowid = (
  SELECT t.rowid
  FROM tasks t
  JOIN plans p ON t.plan_id = p.rowid
  WHERE t.status = 'pending'
    $PLAN_FILTER
    -- All dependencies must be complete
    AND NOT EXISTS (
      SELECT 1
      FROM json_each(t.task_depends) AS dep
      JOIN tasks t2 ON t2.plan_id = t.plan_id AND t2.task_id = dep.value
      WHERE t2.status != 'complete'
    )
  ORDER BY p.phase ASC, p.plan_num ASC, t.task_id ASC
  LIMIT 1
);

-- Return the claimed task if any row was updated
SELECT t.task_id, p.plan_num, t.action, t.spec, t.files
FROM tasks t
JOIN plans p ON t.plan_id = p.rowid
WHERE t.assigned_to = '$AGENT'
  AND t.status = 'in_progress'
  AND t.updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
ORDER BY t.rowid DESC
LIMIT 1;
SQL
)

# No task available — exit silently
if [[ -z "$RESULT" ]]; then
  exit 0
fi

# Parse result and output TOON format
IFS='|' read -r TASK_ID PLAN_NUM ACTION SPEC FILES <<< "$RESULT"

echo "id: $TASK_ID"
echo "plan: $PLAN_NUM"
echo "action: $ACTION"
if [[ -n "${SPEC:-}" ]]; then
  echo "spec: $SPEC"
fi
if [[ -n "${FILES:-}" && "$FILES" != "[]" ]]; then
  echo "files: $FILES"
fi
