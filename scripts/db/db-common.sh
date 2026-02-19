#!/usr/bin/env bash
# db-common.sh — Shared helper library for all DB query/write scripts
# Source pattern: source "$(dirname "$0")/db-common.sh"
set -euo pipefail

# Default DB path relative to project root
_DB_DEFAULT_DIR=".vbw-planning"
_DB_DEFAULT_NAME="yolo.db"

# Resolve DB path from --db flag value or default
# Usage: db_path [explicit_path]
db_path() {
  local explicit="${1:-}"
  if [[ -n "$explicit" ]]; then
    echo "$explicit"
    return 0
  fi
  # Walk up from cwd to find planning dir
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -d "$dir/$_DB_DEFAULT_DIR" ]]; then
      echo "$dir/$_DB_DEFAULT_DIR/$_DB_DEFAULT_NAME"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  # Fallback: cwd-relative
  echo "$PWD/$_DB_DEFAULT_DIR/$_DB_DEFAULT_NAME"
}

# Exit 1 if DB file does not exist
# Usage: require_db <db_path>
require_db() {
  local db="$1"
  if [[ ! -f "$db" ]]; then
    echo "error: database not found: $db" >&2
    exit 1
  fi
}

# Read query wrapper — sets WAL pragma and busy_timeout
# Usage: sql_query <db_path> <sql>
sql_query() {
  local db="$1" sql="$2"
  sqlite3 -batch "$db" <<EOF
.output /dev/null
PRAGMA busy_timeout=5000;
PRAGMA journal_mode=WAL;
.output stdout
.mode list
.headers off
$sql
EOF
}

# Write operation wrapper with transaction
# Usage: sql_exec <db_path> <sql>
sql_exec() {
  local db="$1" sql="$2"
  sqlite3 -batch "$db" <<EOF
.output /dev/null
PRAGMA busy_timeout=5000;
PRAGMA journal_mode=WAL;
PRAGMA foreign_keys=ON;
.output stdout
BEGIN;
$sql
COMMIT;
EOF
}

# Verify a table exists in the database
# Usage: check_table <db_path> <table_name>
# Returns 0 if exists, 1 otherwise
check_table() {
  local db="$1" table="$2"
  local count
  count=$(sqlite3 -batch "$db" \
    "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='$table';")
  [[ "$count" -gt 0 ]]
}

# Convert sqlite output rows to a JSON array of strings
# Usage: echo "row1\nrow2" | json_array
# Output: ["row1","row2"]
json_array() {
  local lines=()
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    lines+=("$line")
  done
  if [[ ${#lines[@]} -eq 0 ]]; then
    echo "[]"
    return 0
  fi
  printf '%s\n' "${lines[@]}" | jq -R . | jq -s .
}

# Parse --db flag from argument list, return remaining args via _REMAINING_ARGS
# Usage: parse_db_flag "$@"; DB=$_DB_PATH; set -- "${_REMAINING_ARGS[@]}"
_DB_PATH=""
_REMAINING_ARGS=()
parse_db_flag() {
  _DB_PATH=""
  _REMAINING_ARGS=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --db)
        _DB_PATH="$2"
        shift 2
        ;;
      --db=*)
        _DB_PATH="${1#--db=}"
        shift
        ;;
      *)
        _REMAINING_ARGS+=("$1")
        shift
        ;;
    esac
  done
}
