#!/usr/bin/env bash
# check-phase-status.sh — Compute phase completion status from DB
# Usage: check-phase-status.sh <PHASE> [--db PATH] [--json]
set -euo pipefail

source "$(dirname "$0")/db-common.sh"

JSON_OUTPUT=0

parse_db_flag "$@"
set -- ${_REMAINING_ARGS[@]+"${_REMAINING_ARGS[@]}"}
DB=$(db_path "$_DB_PATH")

PHASE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) JSON_OUTPUT=1; shift ;;
    -*) shift ;;
    *)
      if [[ -z "$PHASE" ]]; then
        PHASE="$1"
      fi
      shift
      ;;
  esac
done

if [[ -z "$PHASE" ]]; then
  echo "usage: check-phase-status.sh <PHASE> [--db PATH] [--json]" >&2
  exit 1
fi

require_db "$DB"

# Query aggregate stats for the phase
STATS=$(sqlite3 -batch -separator '|' "$DB" <<SQL
.output /dev/null
PRAGMA busy_timeout=5000;
PRAGMA journal_mode=WAL;
.output stdout
SELECT
  count(DISTINCT p.plan_num) AS total_plans,
  count(DISTINCT CASE WHEN s.status = 'complete' THEN p.plan_num END) AS completed_plans,
  count(t.rowid) AS total_tasks,
  count(CASE WHEN t.status = 'complete' THEN 1 END) AS completed_tasks,
  count(CASE WHEN t.status = 'pending' THEN 1 END) AS pending_tasks,
  count(CASE WHEN t.status = 'in_progress' THEN 1 END) AS in_progress_tasks,
  count(CASE WHEN t.status = 'pending' AND EXISTS (
    SELECT 1 FROM json_each(t.task_depends) AS dep
    JOIN tasks t2 ON t2.plan_id = t.plan_id AND t2.task_id = dep.value
    WHERE t2.status != 'complete'
  ) THEN 1 END) AS blocked_tasks
FROM plans p
LEFT JOIN tasks t ON t.plan_id = p.rowid
LEFT JOIN summaries s ON s.plan_id = p.rowid
WHERE p.phase = '$PHASE';
SQL
)

if [[ -z "$STATS" ]]; then
  echo "error: no data for phase $PHASE" >&2
  exit 1
fi

IFS='|' read -r TOTAL_PLANS COMPLETED_PLANS TOTAL_TASKS COMPLETED_TASKS \
  PENDING_TASKS IN_PROGRESS_TASKS BLOCKED_TASKS <<< "$STATS"

# Compute completion percentage
if [[ "$TOTAL_TASKS" -gt 0 ]]; then
  COMPLETION_PCT=$(( (COMPLETED_TASKS * 100) / TOTAL_TASKS ))
else
  COMPLETION_PCT=0
fi

# Per-plan breakdown
PLAN_BREAKDOWN=$(sqlite3 -batch -separator '|' "$DB" <<SQL
.output /dev/null
PRAGMA busy_timeout=5000;
PRAGMA journal_mode=WAL;
.output stdout
SELECT
  p.plan_num,
  count(t.rowid) AS total,
  count(CASE WHEN t.status = 'complete' THEN 1 END) AS done,
  COALESCE(s.status, 'pending') AS plan_status
FROM plans p
LEFT JOIN tasks t ON t.plan_id = p.rowid
LEFT JOIN summaries s ON s.plan_id = p.rowid
WHERE p.phase = '$PHASE'
GROUP BY p.plan_num
ORDER BY p.plan_num ASC;
SQL
)

if [[ "$JSON_OUTPUT" -eq 1 ]]; then
  # Build JSON output
  PLANS_JSON="[]"
  if [[ -n "$PLAN_BREAKDOWN" ]]; then
    PLANS_JSON=$(while IFS='|' read -r PN TOTAL DONE PSTATUS; do
      printf '{"plan":"%s","total":%d,"done":%d,"status":"%s"}\n' \
        "$PN" "$TOTAL" "$DONE" "$PSTATUS"
    done <<< "$PLAN_BREAKDOWN" | jq -s .)
  fi

  jq -n \
    --arg phase "$PHASE" \
    --argjson total_plans "$TOTAL_PLANS" \
    --argjson completed_plans "$COMPLETED_PLANS" \
    --argjson total_tasks "$TOTAL_TASKS" \
    --argjson completed_tasks "$COMPLETED_TASKS" \
    --argjson pending_tasks "$PENDING_TASKS" \
    --argjson in_progress_tasks "$IN_PROGRESS_TASKS" \
    --argjson blocked_tasks "$BLOCKED_TASKS" \
    --argjson completion_pct "$COMPLETION_PCT" \
    --argjson plans "$PLANS_JSON" \
    '{phase:$phase,total_plans:$total_plans,completed_plans:$completed_plans,
      total_tasks:$total_tasks,completed_tasks:$completed_tasks,
      pending_tasks:$pending_tasks,in_progress_tasks:$in_progress_tasks,
      blocked_tasks:$blocked_tasks,completion_pct:$completion_pct,
      plans:$plans}'
else
  # TOON format output
  echo "phase: $PHASE"
  echo "plans: $COMPLETED_PLANS/$TOTAL_PLANS complete"
  echo "tasks: $COMPLETED_TASKS/$TOTAL_TASKS complete ($COMPLETION_PCT%)"
  echo "blocked: $BLOCKED_TASKS"
  echo "in_progress: $IN_PROGRESS_TASKS"

  if [[ -n "$PLAN_BREAKDOWN" ]]; then
    echo "---"
    while IFS='|' read -r PN TOTAL DONE PSTATUS; do
      echo "$PN: $DONE/$TOTAL ($PSTATUS)"
    done <<< "$PLAN_BREAKDOWN"
  fi
fi
