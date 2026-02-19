#!/usr/bin/env bash
# search-gaps.sh — Full-text search on gaps/issues via FTS5
# Usage: search-gaps.sh <QUERY> [--phase PHASE] [--status STATUS] [--sev SEVERITY] [--db PATH]
# Output: TOON format with relevance ranking.
set -euo pipefail

source "$(dirname "$0")/db-common.sh"

parse_db_flag "$@"
set -- "${_REMAINING_ARGS[@]+"${_REMAINING_ARGS[@]}"}"
DB=$(db_path "$_DB_PATH")

QUERY="" PHASE="" STATUS="" SEV="" LIMIT=10

while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase)  PHASE="$2"; shift 2 ;;
    --status) STATUS="$2"; shift 2 ;;
    --sev)    SEV="$2"; shift 2 ;;
    --limit)  LIMIT="$2"; shift 2 ;;
    *)
      [[ -z "$QUERY" ]] && QUERY="$1"
      shift ;;
  esac
done

if [[ -z "$QUERY" ]]; then
  echo "usage: search-gaps.sh <QUERY> [--phase PHASE] [--status STATUS] [--sev SEVERITY] [--db PATH]" >&2
  exit 1
fi

require_db "$DB"

ESCAPED=$(printf '%s' "$QUERY" | sed "s/'/''/g")

FILTER=""
[[ -n "$PHASE" ]]  && FILTER="$FILTER AND gaps.phase = '$PHASE'"
[[ -n "$STATUS" ]] && FILTER="$FILTER AND gaps.st = '$STATUS'"
[[ -n "$SEV" ]]    && FILTER="$FILTER AND gaps.sev = '$SEV'"

SQL="SELECT
  gaps.id,
  gaps.sev,
  snippet(gaps_fts, 0, '>>>', '<<<', '...', 64) AS desc_snip,
  gaps.st,
  COALESCE(gaps.res, '') AS res,
  gaps.phase, gaps_fts.rank
FROM gaps_fts
JOIN gaps ON gaps.rowid = gaps_fts.rowid
WHERE gaps_fts MATCH '$ESCAPED' $FILTER
ORDER BY gaps_fts.rank
LIMIT $LIMIT;"

results=$(sqlite3 -batch -separator $'\x1f' "$DB" <<EOSQL 2>/dev/null || true
.output /dev/null
PRAGMA busy_timeout=5000;
PRAGMA journal_mode=WAL;
.output stdout
$SQL
EOSQL
)

if [[ -z "$results" ]]; then
  echo "no results found for: $QUERY"
  exit 0
fi

while IFS=$'\x1f' read -r id sev desc_snip st res phase _rank; do
  echo "id: $id"
  echo "sev: $sev"
  echo "desc: $desc_snip"
  echo "st: $st"
  [[ -n "$res" ]] && echo "res: $res"
  echo "phase: $phase"
  echo "---"
done <<< "$results"
