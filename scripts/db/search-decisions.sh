#!/usr/bin/env bash
# search-decisions.sh — Full-text search on decisions via FTS5
# Usage: search-decisions.sh <QUERY> [--phase PHASE] [--agent AGENT] [--limit N] [--db PATH]
# Output: TOON format with relevance ranking.
set -euo pipefail

source "$(dirname "$0")/db-common.sh"

parse_db_flag "$@"
set -- "${_REMAINING_ARGS[@]+"${_REMAINING_ARGS[@]}"}"
DB=$(db_path "$_DB_PATH")

QUERY="" PHASE="" AGENT="" LIMIT=10

while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase) PHASE="$2"; shift 2 ;;
    --agent) AGENT="$2"; shift 2 ;;
    --limit) LIMIT="$2"; shift 2 ;;
    *)
      [[ -z "$QUERY" ]] && QUERY="$1"
      shift ;;
  esac
done

if [[ -z "$QUERY" ]]; then
  echo "usage: search-decisions.sh <QUERY> [--phase PHASE] [--agent AGENT] [--limit N] [--db PATH]" >&2
  exit 1
fi

require_db "$DB"

ESCAPED=$(printf '%s' "$QUERY" | sed "s/'/''/g")

FILTER=""
[[ -n "$PHASE" ]] && FILTER="$FILTER AND decisions.phase = '$PHASE'"
[[ -n "$AGENT" ]] && FILTER="$FILTER AND decisions.agent = '$AGENT'"

SQL="SELECT
  snippet(decisions_fts, 0, '>>>', '<<<', '...', 64) AS dec_snip,
  snippet(decisions_fts, 1, '>>>', '<<<', '...', 64) AS reason_snip,
  decisions.agent, decisions.task, COALESCE(decisions.ts, '') AS ts,
  decisions.phase, decisions_fts.rank
FROM decisions_fts
JOIN decisions ON decisions.rowid = decisions_fts.rowid
WHERE decisions_fts MATCH '$ESCAPED' $FILTER
ORDER BY decisions_fts.rank
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

while IFS=$'\x1f' read -r dec_snip reason_snip agent task ts phase _rank; do
  echo "agent: $agent"
  echo "dec: $dec_snip"
  echo "reason: $reason_snip"
  echo "task: $task"
  echo "phase: $phase"
  [[ -n "$ts" ]] && echo "ts: $ts"
  echo "---"
done <<< "$results"
