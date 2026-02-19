#!/usr/bin/env bash
# search-all.sh — Unified cross-artifact full-text search via FTS5
# Usage: search-all.sh <QUERY> [--phase PHASE] [--limit N] [--db PATH]
# Searches research_fts, decisions_fts, gaps_fts and ra_fts.
# Primary RAG-style entry point for Scout agent and cross-phase retrieval.
# Output: TOON format with type tags sorted by relevance.
set -euo pipefail

source "$(dirname "$0")/db-common.sh"

parse_db_flag "$@"
set -- "${_REMAINING_ARGS[@]+"${_REMAINING_ARGS[@]}"}"
DB=$(db_path "$_DB_PATH")

QUERY="" PHASE="" LIMIT=20

while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase) PHASE="$2"; shift 2 ;;
    --limit) LIMIT="$2"; shift 2 ;;
    *)
      [[ -z "$QUERY" ]] && QUERY="$1"
      shift ;;
  esac
done

if [[ -z "$QUERY" ]]; then
  echo "usage: search-all.sh <QUERY> [--phase PHASE] [--limit N] [--db PATH]" >&2
  exit 1
fi

require_db "$DB"

ESCAPED=$(printf '%s' "$QUERY" | sed "s/'/''/g")

R_FILTER="" D_FILTER="" G_FILTER="" A_FILTER=""
if [[ -n "$PHASE" ]]; then
  R_FILTER="AND research.phase = '$PHASE'"
  D_FILTER="AND decisions.phase = '$PHASE'"
  G_FILTER="AND gaps.phase = '$PHASE'"
  A_FILTER="AND research_archive.phase = '$PHASE'"
fi

SQL="SELECT * FROM (
  SELECT 'research' AS type,
    research.phase,
    snippet(research_fts, 1, '>>>', '<<<', '...', 64) AS content,
    research_fts.rank
  FROM research_fts
  JOIN research ON research.rowid = research_fts.rowid
  WHERE research_fts MATCH '$ESCAPED' $R_FILTER

  UNION ALL

  SELECT 'decision' AS type,
    decisions.phase,
    snippet(decisions_fts, 0, '>>>', '<<<', '...', 64) AS content,
    decisions_fts.rank
  FROM decisions_fts
  JOIN decisions ON decisions.rowid = decisions_fts.rowid
  WHERE decisions_fts MATCH '$ESCAPED' $D_FILTER

  UNION ALL

  SELECT 'gap' AS type,
    gaps.phase,
    snippet(gaps_fts, 0, '>>>', '<<<', '...', 64) AS content,
    gaps_fts.rank
  FROM gaps_fts
  JOIN gaps ON gaps.rowid = gaps_fts.rowid
  WHERE gaps_fts MATCH '$ESCAPED' $G_FILTER

  UNION ALL

  SELECT 'archive' AS type,
    research_archive.phase,
    snippet(ra_fts, 1, '>>>', '<<<', '...', 64) AS content,
    ra_fts.rank
  FROM ra_fts
  JOIN research_archive ON research_archive.rowid = ra_fts.rowid
  WHERE ra_fts MATCH '$ESCAPED' $A_FILTER
) ORDER BY rank LIMIT $LIMIT;"

results=$(sqlite3 -batch -separator $'\x1f' "$DB" <<EOSQL 2>/dev/null || true
.output /dev/null
PRAGMA journal_mode=WAL;
PRAGMA busy_timeout=5000;
.output stdout
$SQL
EOSQL
)

if [[ -z "$results" ]]; then
  echo "no results found for: $QUERY"
  exit 0
fi

while IFS=$'\x1f' read -r type phase content _rank; do
  echo "type: $type"
  echo "phase: $phase"
  echo "content: $content"
  echo "---"
done <<< "$results"
