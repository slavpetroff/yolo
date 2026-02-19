#!/usr/bin/env bash
# insert-task.sh — Insert or upsert a task into the artifact store
# Usage: insert-task.sh --plan <PLAN_ID> --id <TASK_ID> --action <TEXT>
#        [--spec TEXT] [--files FILE1,FILE2] [--verify TEXT] [--done TEXT]
#        [--test-spec TEXT] [--deps T1,T2] [--db PATH]
set -euo pipefail

source "$(dirname "$0")/db-common.sh"

# Parse arguments
PLAN_ID=""
TASK_ID=""
ACTION=""
SPEC=""
FILES=""
VERIFY=""
DONE=""
TEST_SPEC=""
DEPS=""

parse_db_flag "$@"
DB_EXPLICIT="$_DB_PATH"
set -- "${_REMAINING_ARGS[@]}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan)   PLAN_ID="$2"; shift 2 ;;
    --id)     TASK_ID="$2"; shift 2 ;;
    --action) ACTION="$2";  shift 2 ;;
    --spec)   SPEC="$2";    shift 2 ;;
    --files)  FILES="$2";   shift 2 ;;
    --verify) VERIFY="$2";  shift 2 ;;
    --done)   DONE="$2";    shift 2 ;;
    --test-spec) TEST_SPEC="$2"; shift 2 ;;
    --deps)   DEPS="$2";    shift 2 ;;
    *) echo "error: unknown flag: $1" >&2; exit 1 ;;
  esac
done

# Validate required fields
if [[ -z "$PLAN_ID" ]]; then
  echo "error: --plan is required" >&2
  exit 1
fi
if [[ -z "$TASK_ID" ]]; then
  echo "error: --id is required" >&2
  exit 1
fi
if [[ -z "$ACTION" ]]; then
  echo "error: --action is required" >&2
  exit 1
fi

DB=$(db_path "$DB_EXPLICIT")
require_db "$DB"

# Convert comma-separated files to JSON array
files_json="[]"
if [[ -n "$FILES" ]]; then
  files_json=$(echo "$FILES" | tr ',' '\n' | jq -R . | jq -s .)
fi

# Convert comma-separated deps to JSON array
deps_json="[]"
if [[ -n "$DEPS" ]]; then
  deps_json=$(echo "$DEPS" | tr ',' '\n' | jq -R . | jq -s .)
fi

# Extract phase and plan_num from PLAN_ID (e.g. "10-03" -> phase="10", plan_num="03")
phase="${PLAN_ID%%-*}"
plan_num="${PLAN_ID#*-}"

# Resolve plan rowid — create plan if it doesn't exist
plan_rowid=$(sql_query "$DB" \
  "SELECT rowid FROM plans WHERE phase='$phase' AND plan_num='$plan_num';")

if [[ -z "$plan_rowid" ]]; then
  sql_exec "$DB" \
    "INSERT INTO plans (phase, plan_num) VALUES ('$phase', '$plan_num');"
  plan_rowid=$(sql_query "$DB" \
    "SELECT rowid FROM plans WHERE phase='$phase' AND plan_num='$plan_num';")
fi

# Escape single quotes for SQL
esc() { echo "${1//\'/\'\'}"; }

action_esc=$(esc "$ACTION")
spec_esc=$(esc "$SPEC")
files_esc=$(esc "$files_json")
verify_esc=$(esc "$VERIFY")
done_esc=$(esc "$DONE")
test_spec_esc=$(esc "$TEST_SPEC")
deps_esc=$(esc "$deps_json")

sql_exec "$DB" "INSERT INTO tasks (plan_id, task_id, action, spec, files, verify, done, test_spec, task_depends, status)
VALUES ($plan_rowid, '$TASK_ID', '$action_esc', '$spec_esc', '$files_esc', '$verify_esc', '$done_esc', '$test_spec_esc', '$deps_esc', 'pending')
ON CONFLICT(plan_id, task_id) DO UPDATE SET
  action=excluded.action,
  spec=excluded.spec,
  files=excluded.files,
  verify=excluded.verify,
  done=excluded.done,
  test_spec=excluded.test_spec,
  task_depends=excluded.task_depends,
  updated_at=strftime('%Y-%m-%dT%H:%M:%SZ', 'now');"

echo "ok: $TASK_ID inserted into plan $PLAN_ID"
