#!/usr/bin/env bash
# token-measure.sh — Measure token savings per role: file-based vs SQL-based context
# Usage: token-measure.sh --phase <PHASE> [--role ROLE] [--db PATH] [--output json|toon]
set -euo pipefail

source "$(dirname "$0")/db-common.sh"

# --- Parse arguments ---
PHASE=""
ROLE=""
OUTPUT_FMT="toon"

parse_db_flag "$@"
DB=$(db_path "$_DB_PATH")
if [[ ${#_REMAINING_ARGS[@]} -gt 0 ]]; then
  set -- "${_REMAINING_ARGS[@]}"
else
  set --
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase)  PHASE="$2"; shift 2 ;;
    --phase=*) PHASE="${1#--phase=}"; shift ;;
    --role)   ROLE="$2"; shift 2 ;;
    --role=*)  ROLE="${1#--role=}"; shift ;;
    --output) OUTPUT_FMT="$2"; shift 2 ;;
    --output=*) OUTPUT_FMT="${1#--output=}"; shift ;;
    *) echo "error: unknown flag: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$PHASE" ]]; then
  echo "error: --phase required" >&2
  echo "Usage: token-measure.sh --phase <PHASE> [--role ROLE] [--db PATH] [--output json|toon]" >&2
  exit 1
fi

# --- Resolve paths ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMPILE_CONTEXT="$SCRIPT_DIR/../compile-context.sh"

if [[ ! -x "$COMPILE_CONTEXT" ]]; then
  echo "error: compile-context.sh not found at $COMPILE_CONTEXT" >&2
  exit 1
fi

# --- Determine roles to measure ---
ALL_BASE_ROLES="architect lead senior dev qa qa-code tester owner security debugger critic scout documenter analyze po questionary roadmap integration-gate"
ROLES_TO_MEASURE=()

if [[ -n "$ROLE" ]]; then
  ROLES_TO_MEASURE=("$ROLE")
else
  for r in $ALL_BASE_ROLES; do
    ROLES_TO_MEASURE+=("$r")
  done
fi

# --- Ensure token_measurements table exists ---
require_db "$DB"
sql_exec "$DB" "CREATE TABLE IF NOT EXISTS token_measurements (
  phase TEXT NOT NULL,
  role TEXT NOT NULL,
  file_tokens INTEGER NOT NULL DEFAULT 0,
  sql_tokens INTEGER NOT NULL DEFAULT 0,
  measured_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  UNIQUE(phase, role)
);"

# --- Find phase directory ---
# Derive from DB path if explicit --db was provided, else fall back to PROJECT_ROOT
DB_DIR=$(dirname "$DB")
if [[ -d "$DB_DIR/phases" ]]; then
  # DB is inside the planning dir (e.g., .yolo-planning/yolo.db)
  PHASES_DIR="$DB_DIR/phases"
elif [[ -d "$DB_DIR/.yolo-planning/phases" ]]; then
  # DB is sibling to planning dir (e.g., test.db next to .yolo-planning/)
  PHASES_DIR="$DB_DIR/.yolo-planning/phases"
else
  PHASES_DIR="$PROJECT_ROOT/.yolo-planning/phases"
fi
PHASE_DIR=$(command ls -d "$PHASES_DIR/${PHASE}-"*/ 2>/dev/null | head -1 || true)
PHASE_DIR=${PHASE_DIR%/}

if [[ -z "$PHASE_DIR" ]]; then
  echo "error: phase directory not found for phase $PHASE" >&2
  exit 1
fi

# --- Find a plan file for roles that need one ---
PLAN_PATH=$(command ls "$PHASE_DIR"/*.plan.jsonl 2>/dev/null | head -1 || true)

# --- Measurement function ---
# Runs compile-context.sh --measure and captures the JSON from stderr
measure_role() {
  local role="$1"
  local use_db="$2"  # "true" or "false"
  local plan_arg=""

  # Roles that benefit from plan path
  case "$role" in
    dev|senior|qa|qa-code|tester|security|documenter)
      if [[ -n "$PLAN_PATH" ]]; then
        plan_arg="$PLAN_PATH"
      fi
      ;;
  esac

  # Temporarily control DB availability by renaming
  local db_path_file="$DB"

  local measure_json=""
  if [[ "$use_db" = "false" ]] && [[ -f "$db_path_file" ]]; then
    # Hide DB to force file-based path
    local tmp_hide="${db_path_file}.measure-hide.$$"
    mv "$db_path_file" "$tmp_hide" 2>/dev/null || true
    measure_json=$(bash "$COMPILE_CONTEXT" --measure "$PHASE" "$role" "$PHASES_DIR" "$plan_arg" 2>&1 >/dev/null || true)
    mv "$tmp_hide" "$db_path_file" 2>/dev/null || true
  else
    measure_json=$(bash "$COMPILE_CONTEXT" --measure "$PHASE" "$role" "$PHASES_DIR" "$plan_arg" 2>&1 >/dev/null || true)
  fi

  # Extract filtered_tokens from JSON output
  local tokens=0
  if [[ -n "$measure_json" ]] && echo "$measure_json" | grep -q '"filtered_tokens"'; then
    tokens=$(echo "$measure_json" | grep -o '"filtered_tokens":[0-9]*' | grep -o '[0-9]*' || echo 0)
  fi
  echo "$tokens"
}

# --- Run measurements ---
declare -a RESULTS=()
TOTAL_FILE=0
TOTAL_SQL=0

for role in "${ROLES_TO_MEASURE[@]}"; do
  # Measure file-based (no DB)
  file_tokens=$(measure_role "$role" "false")
  # Measure SQL-based (with DB)
  sql_tokens=$(measure_role "$role" "true")

  # Calculate savings
  if [[ "$file_tokens" -gt 0 ]]; then
    savings_pct=$(( (file_tokens - sql_tokens) * 100 / file_tokens ))
  else
    savings_pct=0
  fi
  savings_abs=$(( file_tokens - sql_tokens ))

  TOTAL_FILE=$(( TOTAL_FILE + file_tokens ))
  TOTAL_SQL=$(( TOTAL_SQL + sql_tokens ))

  # Store in DB (upsert)
  sql_with_retry "$DB" "INSERT INTO token_measurements (phase, role, file_tokens, sql_tokens)
    VALUES ('$PHASE', '$role', $file_tokens, $sql_tokens)
    ON CONFLICT(phase, role) DO UPDATE SET
      file_tokens=$file_tokens, sql_tokens=$sql_tokens,
      measured_at=strftime('%Y-%m-%dT%H:%M:%SZ', 'now');"

  RESULTS+=("${role}|${file_tokens}|${sql_tokens}|${savings_pct}|${savings_abs}")
done

# --- Calculate totals ---
if [[ "$TOTAL_FILE" -gt 0 ]]; then
  TOTAL_SAVINGS_PCT=$(( (TOTAL_FILE - TOTAL_SQL) * 100 / TOTAL_FILE ))
else
  TOTAL_SAVINGS_PCT=0
fi

# --- Output ---
if [[ "$OUTPUT_FMT" = "json" ]]; then
  echo "{"
  echo "  \"phase\": \"$PHASE\","
  echo "  \"total_file_tokens\": $TOTAL_FILE,"
  echo "  \"total_sql_tokens\": $TOTAL_SQL,"
  echo "  \"total_savings_pct\": $TOTAL_SAVINGS_PCT,"
  echo "  \"roles\": ["
  first=true
  for entry in "${RESULTS[@]}"; do
    IFS='|' read -r r ft st sp sa <<< "$entry"
    if [[ "$first" = true ]]; then
      first=false
    else
      echo ","
    fi
    printf '    {"role":"%s","file_tokens":%s,"sql_tokens":%s,"savings_pct":%s,"savings_abs":%s}' "$r" "$ft" "$st" "$sp" "$sa"
  done
  echo ""
  echo "  ]"
  echo "}"
else
  # TOON format
  echo "token_measurement:"
  echo "  phase: $PHASE"
  echo "  total_file: $TOTAL_FILE"
  echo "  total_sql: $TOTAL_SQL"
  echo "  savings: ${TOTAL_SAVINGS_PCT}%"
  echo "  roles:"
  for entry in "${RESULTS[@]}"; do
    IFS='|' read -r r ft st sp sa <<< "$entry"
    echo "    $r: file=$ft sql=$st savings=${sp}% (${sa} tokens)"
  done
fi
