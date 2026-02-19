#!/usr/bin/env bash
# search-research.sh — Full-text search on research findings via FTS5
# Usage: search-research.sh <QUERY> [--phase PHASE] [--conf LEVEL] [--limit N] [--db PATH]
# Searches both research and research_archive tables.
# Output: TOON format with snippet highlights.
set -euo pipefail

source "$(dirname "$0")/db-common.sh"

parse_db_flag "$@"
set -- "${_REMAINING_ARGS[@]+"${_REMAINING_ARGS[@]}"}"
DB=$(db_path "$_DB_PATH")

QUERY="" PHASE="" CONF="" LIMIT=10

while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase) PHASE="$2"; shift 2 ;;
    --conf)  CONF="$2"; shift 2 ;;
    --limit) LIMIT="$2"; shift 2 ;;
    *)
      [[ -z "$QUERY" ]] && QUERY="$1"
      shift ;;
  esac
done

if [[ -z "$QUERY" ]]; then
  echo "usage: search-research.sh <QUERY> [--phase PHASE] [--conf LEVEL] [--limit N] [--db PATH]" >&2
  exit 1
fi

require_db "$DB"

ESCAPED=$(printf '%s' "$QUERY" | sed "s/'/''/g")

RESEARCH_FILTER="" ARCHIVE_FILTER=""
[[ -n "$PHASE" ]] && RESEARCH_FILTER="$RESEARCH_FILTER AND research.phase = '$PHASE'"
[[ -n "$PHASE" ]] && ARCHIVE_FILTER="$ARCHIVE_FILTER AND research_archive.phase = '$PHASE'"
[[ -n "$CONF" ]]  && RESEARCH_FILTER="$RESEARCH_FILTER AND research.conf = '$CONF'"
[[ -n "$CONF" ]]  && ARCHIVE_FILTER="$ARCHIVE_FILTER AND research_archive.conf = '$CONF'"

SQL="SELECT * FROM (
  SELECT
    snippet(research_fts, 0, '>>>', '<<<', '...', 32) AS q_snip,
    snippet(research_fts, 1, '>>>', '<<<', '...', 64) AS finding_snip,
    research.conf, research.phase, COALESCE(research.dt, '') AS dt,
    'research' AS source, research_fts.rank
  FROM research_fts
  JOIN research ON research.rowid = research_fts.rowid
  WHERE research_fts MATCH '$ESCAPED' $RESEARCH_FILTER

  UNION ALL

  SELECT
    snippet(ra_fts, 0, '>>>', '<<<', '...', 32),
    snippet(ra_fts, 1, '>>>', '<<<', '...', 64),
    research_archive.conf, research_archive.phase,
    COALESCE(research_archive.dt, '') AS dt,
    'archive' AS source, ra_fts.rank
  FROM ra_fts
  JOIN research_archive ON research_archive.rowid = ra_fts.rowid
  WHERE ra_fts MATCH '$ESCAPED' $ARCHIVE_FILTER
) ORDER BY rank LIMIT $LIMIT;"

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

while IFS=$'\x1f' read -r q_snip finding_snip conf phase dt source _rank; do
  echo "q: $q_snip"
  echo "finding: $finding_snip"
  echo "conf: $conf"
  echo "phase: $phase"
  [[ -n "$dt" ]] && echo "dt: $dt"
  echo "source: $source"
  echo "---"
done <<< "$results"
