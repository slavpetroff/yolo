#!/usr/bin/env bash
# get-context.sh — Retrieve role-filtered context from the database
# Usage: get-context.sh <phase-num> <role> [--db PATH] [--plan PLAN_ID] [--budget TOKENS] [--manifest PATH]
# Reads context-manifest.json for role-specific artifact/field filtering.
# SQL-powered replacement for compile-context.sh role-specific sections.
set -euo pipefail

source "$(dirname "$0")/db-common.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

usage() {
  echo "Usage: get-context.sh <phase-num> <role> [--db PATH] [--plan PLAN_ID] [--budget TOKENS] [--manifest PATH]" >&2
  exit 1
}

[[ $# -eq 0 ]] && usage

# Parse args
PLAN_FILTER=""
BUDGET=""
MANIFEST=""

parse_db_flag "$@"
DB=$(db_path "$_DB_PATH")
set -- ${_REMAINING_ARGS[@]+"${_REMAINING_ARGS[@]}"}

POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan)     PLAN_FILTER="$2"; shift 2 ;;
    --plan=*)   PLAN_FILTER="${1#--plan=}"; shift ;;
    --budget)   BUDGET="$2"; shift 2 ;;
    --budget=*) BUDGET="${1#--budget=}"; shift ;;
    --manifest)   MANIFEST="$2"; shift 2 ;;
    --manifest=*) MANIFEST="${1#--manifest=}"; shift ;;
    *)          POSITIONAL+=("$1"); shift ;;
  esac
done

if [[ ${#POSITIONAL[@]} -lt 2 ]]; then
  usage
fi

PHASE_NUM="${POSITIONAL[0]}"
ROLE="${POSITIONAL[1]}"

require_db "$DB"

# Resolve manifest path
MANIFEST_PATH="${MANIFEST:-$PROJECT_ROOT/config/context-manifest.json}"
if [[ ! -f "$MANIFEST_PATH" ]]; then
  echo "error: manifest not found: $MANIFEST_PATH" >&2
  exit 1
fi

# Read role config from manifest
ROLE_CONFIG=$(jq -r --arg role "$ROLE" '.roles[$role] // empty' "$MANIFEST_PATH")
if [[ -z "$ROLE_CONFIG" ]]; then
  echo "error: role '$ROLE' not found in manifest" >&2
  exit 1
fi

# Extract role's artifacts and fields
ARTIFACTS=$(echo "$ROLE_CONFIG" | jq -r '.artifacts[]' 2>/dev/null)
ROLE_BUDGET=$(echo "$ROLE_CONFIG" | jq -r '.budget // 3000')

# Use explicit budget if provided, otherwise role's default
EFFECTIVE_BUDGET="${BUDGET:-$ROLE_BUDGET}"

output=""
token_estimate=0

# Map artifact type to table name and query
query_artifact() {
  local artifact="$1"
  local fields_json
  fields_json=$(echo "$ROLE_CONFIG" | jq -r --arg a "$artifact" '.fields[$a] // empty')

  local table_name=""
  local select_fields="*"
  local where_clause="WHERE phase='$PHASE_NUM'"

  case "$artifact" in
    plan)
      table_name="tasks"
      where_clause="WHERE plan_id LIKE '${PHASE_NUM}-%'"
      if [[ -n "$PLAN_FILTER" ]]; then
        where_clause="WHERE plan_id='$PLAN_FILTER'"
      fi
      ;;
    summary)
      table_name="summaries"
      where_clause="WHERE phase='$PHASE_NUM'"
      if [[ -n "$PLAN_FILTER" ]]; then
        where_clause="WHERE plan_id='$PLAN_FILTER'"
      fi
      ;;
    critique)      table_name="critique" ;;
    research)      table_name="research" ;;
    decisions)     table_name="decisions" ;;
    escalation)    table_name="escalation" ;;
    gaps)          table_name="gaps" ;;
    test-results)  table_name="test_results" ;;
    code-review)   table_name="code_review" ;;
    *)
      return 0
      ;;
  esac

  # Check table exists
  if ! check_table "$DB" "$table_name"; then
    return 0
  fi

  # Build field selection from manifest
  if [[ -n "$fields_json" ]]; then
    # Convert JSON array of field names to comma-separated SQL columns
    select_fields=$(echo "$fields_json" | jq -r 'join(",")' 2>/dev/null)
    if [[ -z "$select_fields" || "$select_fields" == "null" ]]; then
      select_fields="*"
    fi
  fi

  local result
  result=$(sql_query "$DB" "SELECT $select_fields FROM $table_name $where_clause;")

  if [[ -n "$result" ]]; then
    echo "--- $artifact ---"
    echo "$result"
  fi
}

# Build context for each artifact
for artifact in $ARTIFACTS; do
  section=$(query_artifact "$artifact")
  if [[ -n "$section" ]]; then
    # Rough token estimate: 1 token per 4 chars
    section_tokens=$(( ${#section} / 4 ))
    new_total=$(( token_estimate + section_tokens ))

    if [[ -n "$EFFECTIVE_BUDGET" && "$new_total" -gt "$EFFECTIVE_BUDGET" ]]; then
      # Budget exceeded — truncate
      echo "$section" | head -5
      echo "... (truncated, budget: $EFFECTIVE_BUDGET tokens)"
      break
    fi

    echo "$section"
    token_estimate=$new_total
  fi
done
