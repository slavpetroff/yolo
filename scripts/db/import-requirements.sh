#!/usr/bin/env bash
# import-requirements.sh — Parse REQUIREMENTS.md into SQLite requirements table
# Usage: import-requirements.sh --file <REQUIREMENTS_PATH> [--db PATH]
# Parses ### REQ-NN: description lines with **priority** below.
# INSERT INTO requirements ON CONFLICT(req_id) DO UPDATE.
set -euo pipefail

source "$(dirname "$0")/db-common.sh"

usage() {
  echo "Usage: import-requirements.sh --file <REQUIREMENTS_PATH> [--db PATH]" >&2
  exit 1
}

[[ $# -eq 0 ]] && usage

parse_db_flag "$@"
set -- ${_REMAINING_ARGS[@]+"${_REMAINING_ARGS[@]}"}
DB=$(db_path "$_DB_PATH")

FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --file) FILE="$2"; shift 2 ;;
    -h|--help) usage ;;
    *)      shift ;;
  esac
done

if [[ -z "$FILE" ]]; then
  echo "error: --file is required" >&2
  usage
fi

if [[ ! -f "$FILE" ]]; then
  echo "error: file not found: $FILE" >&2
  exit 1
fi

require_db "$DB"

# Ensure requirements table exists
sql_exec "$DB" "
CREATE TABLE IF NOT EXISTS requirements (
  req_id TEXT PRIMARY KEY,
  description TEXT,
  priority TEXT DEFAULT 'must-have'
);
"

# Parse REQUIREMENTS.md with awk
# Outputs: req_id \t description \t priority
parsed=$(awk '
BEGIN { OFS="\t"; req_id="" }

# Match ### REQ-NN: description
/^### REQ-[0-9]+:/ {
  # Emit previous requirement if any
  if (req_id != "") {
    print req_id, desc, priority
  }
  # Extract REQ-NN
  tmp = $0
  sub(/^### /, "", tmp)
  split(tmp, parts, ":")
  req_id = parts[1]
  # Extract description (after colon, trimmed)
  desc = tmp
  sub(/^REQ-[0-9]+:[[:space:]]*/, "", desc)
  priority = "must-have"
  next
}

# Match **Priority** line
req_id != "" && /^\*\*[^*]+\*\*/ {
  p = $0
  gsub(/\*\*/, "", p)
  gsub(/^[[:space:]]+|[[:space:]]+$/, "", p)
  priority = tolower(p)
  next
}

END {
  if (req_id != "") {
    print req_id, desc, priority
  }
}
' "$FILE")

COUNT=0
while IFS=$'\t' read -r req_id desc priority; do
  [[ -z "$req_id" ]] && continue

  req_id_esc=$(printf '%s' "$req_id" | sed "s/'/''/g")
  desc_esc=$(printf '%s' "$desc" | sed "s/'/''/g")
  priority_esc=$(printf '%s' "$priority" | sed "s/'/''/g")

  sql_exec "$DB" "
INSERT INTO requirements (req_id, description, priority)
VALUES ('$req_id_esc', '$desc_esc', '$priority_esc')
ON CONFLICT(req_id) DO UPDATE SET
  description=excluded.description,
  priority=excluded.priority;
"
  COUNT=$((COUNT + 1))
done <<< "$parsed"

echo "imported $COUNT requirements from $FILE"
