#!/usr/bin/env bash
# update-status.sh — Update status with state transition validation
# Usage: update-status.sh --type <TYPE> --id <ID> --status <STATUS>
#        [--phase PHASE] [--resolution TEXT] [--db PATH]
# Types: task (pending->in_progress->complete),
#        escalation (open->escalated->resolved),
#        gap (open->fixed->accepted),
#        critique (open->addressed->deferred->rejected)
set -euo pipefail

source "$(dirname "$0")/db-common.sh"

# Parse arguments
TYPE=""
ID=""
STATUS=""
PHASE=""
RESOLUTION=""

parse_db_flag "$@"
DB_EXPLICIT="$_DB_PATH"
set -- "${_REMAINING_ARGS[@]}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --type)       TYPE="$2";       shift 2 ;;
    --id)         ID="$2";        shift 2 ;;
    --status)     STATUS="$2";    shift 2 ;;
    --phase)      PHASE="$2";     shift 2 ;;
    --resolution) RESOLUTION="$2"; shift 2 ;;
    *) echo "error: unknown flag: $1" >&2; exit 1 ;;
  esac
done

# Validate required fields
if [[ -z "$TYPE" ]]; then
  echo "error: --type is required" >&2
  exit 1
fi
if [[ -z "$ID" ]]; then
  echo "error: --id is required" >&2
  exit 1
fi
if [[ -z "$STATUS" ]]; then
  echo "error: --status is required" >&2
  exit 1
fi

DB=$(db_path "$DB_EXPLICIT")
require_db "$DB"

# Escape single quotes for SQL
esc() { echo "${1//\'/\'\'}"; }

# Validate state transition: returns 0 if valid, 1 if invalid
# Args: type current_status new_status
validate_transition() {
  local type="$1" current="$2" new="$3"
  local pair="${current}:${new}"
  case "$type" in
    task)
      # pending -> in_progress -> complete
      case "$pair" in
        pending:in_progress|pending:complete|in_progress:complete) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    escalation)
      # open -> escalated -> resolved
      case "$pair" in
        open:escalated|open:resolved|escalated:resolved) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    gap)
      # open -> fixed -> accepted
      case "$pair" in
        open:fixed|open:accepted|fixed:accepted) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    critique)
      # open -> addressed/deferred/rejected
      # addressed -> deferred/rejected
      # deferred -> rejected
      case "$pair" in
        open:addressed|open:deferred|open:rejected) return 0 ;;
        addressed:deferred|addressed:rejected) return 0 ;;
        deferred:rejected) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    *)
      echo "error: unknown type '$type'" >&2
      return 1
      ;;
  esac
}

# Determine table, id column, and status column based on type
case "$TYPE" in
  task)
    TABLE="tasks"
    ID_COL="task_id"
    ST_COL="status"
    # Task needs plan context — ID format: TASK_ID with --phase providing plan context
    # For tasks, --id is the task_id and we look across all plans (or within phase)
    if [[ -n "$PHASE" ]]; then
      CURRENT=$(sql_query "$DB" \
        "SELECT t.status FROM tasks t JOIN plans p ON t.plan_id=p.rowid WHERE t.task_id='$(esc "$ID")' AND p.phase='$(esc "$PHASE")' LIMIT 1;")
    else
      CURRENT=$(sql_query "$DB" \
        "SELECT status FROM tasks WHERE task_id='$(esc "$ID")' LIMIT 1;")
    fi
    ;;
  escalation)
    TABLE="escalation"
    ID_COL="id"
    ST_COL="st"
    CURRENT=$(sql_query "$DB" "SELECT st FROM escalation WHERE id='$(esc "$ID")' LIMIT 1;")
    ;;
  gap)
    TABLE="gaps"
    ID_COL="id"
    ST_COL="st"
    CURRENT=$(sql_query "$DB" "SELECT st FROM gaps WHERE id='$(esc "$ID")' LIMIT 1;")
    ;;
  critique)
    TABLE="critique"
    ID_COL="id"
    ST_COL="st"
    CURRENT=$(sql_query "$DB" "SELECT st FROM critique WHERE id='$(esc "$ID")' LIMIT 1;")
    ;;
  *)
    echo "error: unknown type '$TYPE'. Supported: task, escalation, gap, critique" >&2
    exit 1
    ;;
esac

# Check record exists
if [[ -z "$CURRENT" ]]; then
  echo "error: $TYPE '$ID' not found" >&2
  exit 1
fi

# Validate transition
if ! validate_transition "$TYPE" "$CURRENT" "$STATUS"; then
  echo "error: invalid transition $CURRENT -> $STATUS for $TYPE" >&2
  exit 1
fi

# Build UPDATE
res_esc=$(esc "$RESOLUTION")

if [[ "$TYPE" == "task" ]]; then
  # Task UPDATE — needs join through plan for phase-scoped
  set_clause="$ST_COL='$(esc "$STATUS")', updated_at=strftime('%Y-%m-%dT%H:%M:%SZ', 'now')"
  if [[ "$STATUS" == "complete" ]]; then
    set_clause="$set_clause, completed_at=strftime('%Y-%m-%dT%H:%M:%SZ', 'now')"
  fi
  if [[ -n "$PHASE" ]]; then
    sql_with_retry "$DB" "UPDATE tasks SET $set_clause WHERE task_id='$(esc "$ID")' AND plan_id IN (SELECT rowid FROM plans WHERE phase='$(esc "$PHASE")');"
  else
    sql_with_retry "$DB" "UPDATE tasks SET $set_clause WHERE task_id='$(esc "$ID")';"
  fi
else
  set_clause="$ST_COL='$(esc "$STATUS")'"
  if [[ -n "$RESOLUTION" ]]; then
    set_clause="$set_clause, res='$res_esc'"
  fi
  if [[ -n "$PHASE" ]]; then
    sql_with_retry "$DB" "UPDATE $TABLE SET $set_clause WHERE $ID_COL='$(esc "$ID")' AND phase='$(esc "$PHASE")';"
  else
    sql_with_retry "$DB" "UPDATE $TABLE SET $set_clause WHERE $ID_COL='$(esc "$ID")';"
  fi
fi

echo "$CURRENT -> $STATUS"
