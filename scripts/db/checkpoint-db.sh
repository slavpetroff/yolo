#!/usr/bin/env bash
# checkpoint-db.sh — WAL checkpoint management
# Usage: checkpoint-db.sh [--db PATH] [--mode passive|full|restart|truncate]
# Default mode: passive (non-blocking)
# Output: WAL size, pages checkpointed, pages remaining
set -euo pipefail

source "$(dirname "$0")/db-common.sh"

MODE="passive"

parse_db_flag "$@"
set -- ${_REMAINING_ARGS[@]+"${_REMAINING_ARGS[@]}"}
DB=$(db_path "$_DB_PATH")

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="$2"; shift 2 ;;
    --mode=*) MODE="${1#--mode=}"; shift ;;
    *) shift ;;
  esac
done

# Validate mode
case "$MODE" in
  passive|full|restart|truncate) ;;
  *)
    echo "error: invalid mode '$MODE'. Use: passive, full, restart, truncate" >&2
    exit 1
    ;;
esac

require_db "$DB"

# Run checkpoint and capture result
# wal_checkpoint returns: busy, log_pages, checkpointed_pages
RESULT=$(sqlite3 -batch "$DB" <<SQL
.output /dev/null
PRAGMA busy_timeout=5000;
PRAGMA journal_mode=WAL;
.output stdout
PRAGMA wal_checkpoint($MODE);
SQL
)

IFS='|' read -r BUSY LOG_PAGES CHECKPOINTED <<< "$RESULT"

# Get WAL file size
WAL_FILE="${DB}-wal"
WAL_SIZE=0
if [[ -f "$WAL_FILE" ]]; then
  WAL_SIZE=$(wc -c < "$WAL_FILE" | tr -d ' ')
fi

echo "mode: $MODE"
echo "wal_pages: ${LOG_PAGES:-0}"
echo "checkpointed: ${CHECKPOINTED:-0}"
echo "wal_size_bytes: $WAL_SIZE"
if [[ "${BUSY:-0}" -ne 0 ]]; then
  echo "busy: true"
fi
