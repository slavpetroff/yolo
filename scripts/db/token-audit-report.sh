#!/usr/bin/env bash
# token-audit-report.sh — Phase-level token savings summary and verdict
# Usage: token-audit-report.sh --phase <PHASE> [--db PATH] [--baseline PHASE]
set -euo pipefail

source "$(dirname "$0")/db-common.sh"

# --- Parse arguments ---
PHASE=""
BASELINE=""

parse_db_flag "$@"
DB=$(db_path "$_DB_PATH")
if [[ ${#_REMAINING_ARGS[@]} -gt 0 ]]; then
  set -- "${_REMAINING_ARGS[@]}"
else
  set --
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase)    PHASE="$2"; shift 2 ;;
    --phase=*)  PHASE="${1#--phase=}"; shift ;;
    --baseline) BASELINE="$2"; shift 2 ;;
    --baseline=*) BASELINE="${1#--baseline=}"; shift ;;
    *) echo "error: unknown flag: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$PHASE" ]]; then
  echo "error: --phase required" >&2
  echo "Usage: token-audit-report.sh --phase <PHASE> [--db PATH] [--baseline PHASE]" >&2
  exit 1
fi

require_db "$DB"

# --- Ensure token_audit_reports table exists ---
sql_exec "$DB" "CREATE TABLE IF NOT EXISTS token_audit_reports (
  phase TEXT NOT NULL,
  total_file_tokens INTEGER NOT NULL DEFAULT 0,
  total_sql_tokens INTEGER NOT NULL DEFAULT 0,
  total_savings_pct INTEGER NOT NULL DEFAULT 0,
  verdict TEXT NOT NULL DEFAULT 'UNKNOWN',
  baseline_phase TEXT,
  measured_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  UNIQUE(phase)
);"

# --- Run token-measure.sh to populate measurements ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOKEN_MEASURE="$SCRIPT_DIR/token-measure.sh"

# --- Query measurements from DB (auto-measure if empty) ---
HAS_MEASUREMENTS=$(sqlite3 -batch "$DB" "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='token_measurements';")
MEASUREMENT_COUNT=0
if [[ "$HAS_MEASUREMENTS" -gt 0 ]]; then
  MEASUREMENT_COUNT=$(sql_query "$DB" "SELECT count(*) FROM token_measurements WHERE phase='$PHASE';")
fi

# Only run token-measure.sh if no measurements exist for this phase
if [[ "$MEASUREMENT_COUNT" -eq 0 ]] && [[ -x "$TOKEN_MEASURE" ]]; then
  bash "$TOKEN_MEASURE" --phase "$PHASE" --db "$DB" --output json >/dev/null 2>&1 || true
  # Re-check
  HAS_MEASUREMENTS=$(sqlite3 -batch "$DB" "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='token_measurements';")
  if [[ "$HAS_MEASUREMENTS" -gt 0 ]]; then
    MEASUREMENT_COUNT=$(sql_query "$DB" "SELECT count(*) FROM token_measurements WHERE phase='$PHASE';")
  fi
fi

if [[ "$HAS_MEASUREMENTS" -eq 0 ]]; then
  echo "error: no token_measurements table found. Run token-measure.sh first." >&2
  exit 1
fi

if [[ "$MEASUREMENT_COUNT" -eq 0 ]]; then
  echo "error: no measurements found for phase $PHASE. Run token-measure.sh --phase $PHASE first." >&2
  exit 1
fi

# --- Aggregate totals ---
TOTAL_FILE=$(sql_query "$DB" "SELECT COALESCE(SUM(file_tokens), 0) FROM token_measurements WHERE phase='$PHASE';")
TOTAL_SQL=$(sql_query "$DB" "SELECT COALESCE(SUM(sql_tokens), 0) FROM token_measurements WHERE phase='$PHASE';")

if [[ "$TOTAL_FILE" -gt 0 ]]; then
  TOTAL_SAVINGS_PCT=$(( (TOTAL_FILE - TOTAL_SQL) * 100 / TOTAL_FILE ))
else
  TOTAL_SAVINGS_PCT=0
fi

# --- Determine verdict ---
if [[ "$TOTAL_SAVINGS_PCT" -ge 50 ]]; then
  VERDICT="PASS"
elif [[ "$TOTAL_SAVINGS_PCT" -ge 30 ]]; then
  VERDICT="WARN"
else
  VERDICT="FAIL"
fi

# --- Baseline comparison ---
BASELINE_TOTAL_FILE=0
BASELINE_TOTAL_SQL=0
BASELINE_SAVINGS_PCT=0
HAS_BASELINE=false

if [[ -n "$BASELINE" ]]; then
  BASELINE_COUNT=$(sql_query "$DB" "SELECT count(*) FROM token_measurements WHERE phase='$BASELINE';")
  if [[ "$BASELINE_COUNT" -gt 0 ]]; then
    HAS_BASELINE=true
    BASELINE_TOTAL_FILE=$(sql_query "$DB" "SELECT COALESCE(SUM(file_tokens), 0) FROM token_measurements WHERE phase='$BASELINE';")
    BASELINE_TOTAL_SQL=$(sql_query "$DB" "SELECT COALESCE(SUM(sql_tokens), 0) FROM token_measurements WHERE phase='$BASELINE';")
    if [[ "$BASELINE_TOTAL_FILE" -gt 0 ]]; then
      BASELINE_SAVINGS_PCT=$(( (BASELINE_TOTAL_FILE - BASELINE_TOTAL_SQL) * 100 / BASELINE_TOTAL_FILE ))
    fi
  fi
fi

# --- Store report in DB ---
sql_with_retry "$DB" "INSERT INTO token_audit_reports (phase, total_file_tokens, total_sql_tokens, total_savings_pct, verdict, baseline_phase)
  VALUES ('$PHASE', $TOTAL_FILE, $TOTAL_SQL, $TOTAL_SAVINGS_PCT, '$VERDICT', $([ -n "$BASELINE" ] && echo "'$BASELINE'" || echo "NULL"))
  ON CONFLICT(phase) DO UPDATE SET
    total_file_tokens=$TOTAL_FILE, total_sql_tokens=$TOTAL_SQL,
    total_savings_pct=$TOTAL_SAVINGS_PCT, verdict='$VERDICT',
    baseline_phase=$([ -n "$BASELINE" ] && echo "'$BASELINE'" || echo "NULL"),
    measured_at=strftime('%Y-%m-%dT%H:%M:%SZ', 'now');"

# --- Output report ---
echo "=== Token Audit Report: Phase $PHASE ==="
echo ""
echo "Total file-based tokens:  $TOTAL_FILE"
echo "Total SQL-based tokens:   $TOTAL_SQL"
echo "Total savings:            ${TOTAL_SAVINGS_PCT}%"
echo "Verdict:                  $VERDICT"
echo ""

if [[ "$HAS_BASELINE" = true ]]; then
  echo "--- Baseline Comparison (Phase $BASELINE) ---"
  echo "Baseline file tokens:     $BASELINE_TOTAL_FILE"
  echo "Baseline SQL tokens:      $BASELINE_TOTAL_SQL"
  echo "Baseline savings:         ${BASELINE_SAVINGS_PCT}%"
  local_improvement=$(( TOTAL_SAVINGS_PCT - BASELINE_SAVINGS_PCT ))
  echo "Improvement over baseline: ${local_improvement}pp"
  echo ""
fi

echo "--- Per-Role Breakdown ---"
sql_query "$DB" "SELECT role || ': file=' || file_tokens || ' sql=' || sql_tokens ||
  ' savings=' || CASE WHEN file_tokens > 0
    THEN ((file_tokens - sql_tokens) * 100 / file_tokens)
    ELSE 0 END || '%'
  FROM token_measurements WHERE phase='$PHASE' ORDER BY role;"
echo ""
echo "--- Verdict Criteria ---"
echo "  PASS: >50% total savings"
echo "  WARN: 30-50% total savings"
echo "  FAIL: <30% total savings"
