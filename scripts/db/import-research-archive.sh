#!/usr/bin/env bash
# import-research-archive.sh — Import research-archive.jsonl into SQLite
# Usage: import-research-archive.sh [--file PATH] [--db PATH]
# Reads research-archive.jsonl, inserts into research_archive + ra_fts.
# Dedup: ON CONFLICT(q, finding) DO NOTHING.
set -euo pipefail

source "$(dirname "$0")/db-common.sh"

parse_db_flag "$@"
set -- "${_REMAINING_ARGS[@]+"${_REMAINING_ARGS[@]}"}"
DB=$(db_path "$_DB_PATH")

FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --file) FILE="$2"; shift 2 ;;
    *)      shift ;;
  esac
done

# Default archive file location
FILE="${FILE:-.vbw-planning/research-archive.jsonl}"

if [[ ! -f "$FILE" ]]; then
  echo "error: archive file not found: $FILE" >&2
  exit 1
fi

require_db "$DB"

COUNT=0
# Read line by line, parse with jq, insert
while IFS= read -r line; do
  [[ -z "$line" ]] && continue

  q=$(printf '%s' "$line" | jq -r '.q // empty')
  finding=$(printf '%s' "$line" | jq -r '.finding // empty')
  conf=$(printf '%s' "$line" | jq -r '.conf // "medium"')
  phase=$(printf '%s' "$line" | jq -r '.phase // ""')
  dt=$(printf '%s' "$line" | jq -r '.dt // ""')
  src=$(printf '%s' "$line" | jq -r '.src // ""')

  [[ -z "$q" || -z "$finding" ]] && continue

  # Escape single quotes for SQL
  q_esc=$(printf '%s' "$q" | sed "s/'/''/g")
  finding_esc=$(printf '%s' "$finding" | sed "s/'/''/g")
  conf_esc=$(printf '%s' "$conf" | sed "s/'/''/g")
  phase_esc=$(printf '%s' "$phase" | sed "s/'/''/g")
  dt_esc=$(printf '%s' "$dt" | sed "s/'/''/g")
  src_esc=$(printf '%s' "$src" | sed "s/'/''/g")

  sqlite3 -batch "$DB" <<EOSQL > /dev/null
PRAGMA busy_timeout=5000;
PRAGMA journal_mode=WAL;
INSERT OR IGNORE INTO research_archive (q, finding, conf, phase, dt, src)
VALUES ('$q_esc', '$finding_esc', '$conf_esc', '$phase_esc', '$dt_esc', '$src_esc');
EOSQL

  COUNT=$((COUNT + 1))
done < "$FILE"

echo "imported $COUNT entries from $FILE"
