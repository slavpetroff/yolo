#!/usr/bin/env bash
# export-research-archive.sh — Export research_archive table to JSONL
# Usage: export-research-archive.sh [--file PATH] [--db PATH]
# Dumps research_archive table back to JSONL for backward compatibility.
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

FILE="${FILE:-.vbw-planning/research-archive.jsonl}"

require_db "$DB"

sqlite3 -batch -json \
  -cmd "PRAGMA journal_mode=WAL;" \
  -cmd "PRAGMA busy_timeout=5000;" \
  "$DB" \
  "SELECT q, finding, conf, phase, dt, src FROM research_archive ORDER BY rowid;" \
  | jq -c '.[]' > "$FILE"

echo "exported to $FILE"
