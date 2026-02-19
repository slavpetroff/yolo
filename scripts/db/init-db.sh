#!/usr/bin/env bash
# init-db.sh — Initialize YOLO SQLite artifact store
# Usage: init-db.sh [--planning-dir PATH] [--force] [--verify]
# Creates DB at ${PLANNING_DIR}/yolo.db with WAL mode, FTS5, and all tables.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMA_FILE="$SCRIPT_DIR/schema.sql"

# Defaults
PLANNING_DIR=""
FORCE=false
VERIFY=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --planning-dir)
      PLANNING_DIR="$2"
      shift 2
      ;;
    --force)
      FORCE=true
      shift
      ;;
    --verify)
      VERIFY=true
      shift
      ;;
    -h|--help)
      echo "Usage: init-db.sh [--planning-dir PATH] [--force] [--verify]"
      echo ""
      echo "Options:"
      echo "  --planning-dir PATH  Planning directory (default: .vbw-planning)"
      echo "  --force              Recreate DB even if it exists"
      echo "  --verify             Run integrity check and count tables"
      exit 0
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

# Resolve planning dir
if [[ -z "$PLANNING_DIR" ]]; then
  PLANNING_DIR=".vbw-planning"
fi

DB_PATH="$PLANNING_DIR/yolo.db"

# Verify schema file exists
if [[ ! -f "$SCHEMA_FILE" ]]; then
  echo "ERROR: Schema file not found: $SCHEMA_FILE" >&2
  exit 1
fi

# Verify mode: check existing DB integrity
if [[ "$VERIFY" == true ]]; then
  if [[ ! -f "$DB_PATH" ]]; then
    echo "ERROR: DB not found: $DB_PATH" >&2
    exit 1
  fi
  echo "Verifying: $DB_PATH"
  integrity=$(sqlite3 "$DB_PATH" "PRAGMA integrity_check;")
  if [[ "$integrity" != "ok" ]]; then
    echo "INTEGRITY FAIL: $integrity" >&2
    exit 1
  fi
  echo "Integrity: ok"
  table_count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';")
  echo "Tables: $table_count"
  journal=$(sqlite3 "$DB_PATH" "PRAGMA journal_mode;")
  echo "Journal mode: $journal"
  exit 0
fi

# Force: remove existing DB
if [[ "$FORCE" == true ]] && [[ -f "$DB_PATH" ]]; then
  rm -f "$DB_PATH" "${DB_PATH}-wal" "${DB_PATH}-shm"
fi

# Idempotent: if DB exists and not force, exit success
if [[ -f "$DB_PATH" ]] && [[ "$FORCE" != true ]]; then
  echo "$DB_PATH"
  exit 0
fi

# Create planning dir if needed
mkdir -p "$PLANNING_DIR"

# Create DB with schema
sqlite3 "$DB_PATH" < "$SCHEMA_FILE"

# Set pragmas (suppress PRAGMA output)
sqlite3 "$DB_PATH" "PRAGMA journal_mode=WAL;" >/dev/null
sqlite3 "$DB_PATH" "PRAGMA busy_timeout=5000;" >/dev/null
sqlite3 "$DB_PATH" "PRAGMA foreign_keys=ON;" >/dev/null

# Auto-import ROADMAP.md if present
ROADMAP_FILE="$PLANNING_DIR/ROADMAP.md"
if [[ -f "$ROADMAP_FILE" ]] && [[ -f "$SCRIPT_DIR/import-roadmap.sh" ]]; then
  bash "$SCRIPT_DIR/import-roadmap.sh" --file "$ROADMAP_FILE" --db "$DB_PATH" >/dev/null 2>&1 || true
fi

# Auto-import REQUIREMENTS.md if present
REQS_FILE="$PLANNING_DIR/REQUIREMENTS.md"
if [[ -f "$REQS_FILE" ]] && [[ -f "$SCRIPT_DIR/import-requirements.sh" ]]; then
  bash "$SCRIPT_DIR/import-requirements.sh" --file "$REQS_FILE" --db "$DB_PATH" >/dev/null 2>&1 || true
fi

# Auto-import research-archive.jsonl if present
ARCHIVE_FILE="$PLANNING_DIR/research-archive.jsonl"
if [[ -f "$ARCHIVE_FILE" ]] && [[ -f "$SCRIPT_DIR/import-research-archive.sh" ]]; then
  bash "$SCRIPT_DIR/import-research-archive.sh" --file "$ARCHIVE_FILE" --db "$DB_PATH" >/dev/null 2>&1 || true
fi

# Output DB path
echo "$DB_PATH"
