#!/usr/bin/env bash
# import-roadmap.sh — Parse ROADMAP.md into SQLite phases table
# Usage: import-roadmap.sh --file <ROADMAP_PATH> [--db PATH]
# Parses ## Phase N: Title headers with **Goal:**, **Requirements:**,
# **Success Criteria:**, **Dependencies:** subsections.
# INSERT INTO phases ON CONFLICT(phase_num) DO UPDATE.
set -euo pipefail

source "$(dirname "$0")/db-common.sh"

usage() {
  echo "Usage: import-roadmap.sh --file <ROADMAP_PATH> [--db PATH]" >&2
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

# Ensure phases table exists
sql_exec "$DB" "
CREATE TABLE IF NOT EXISTS phases (
  phase_num TEXT PRIMARY KEY,
  slug TEXT,
  goal TEXT,
  reqs TEXT,
  success_criteria TEXT,
  deps TEXT,
  status TEXT DEFAULT 'planned'
);
"

# Parse ROADMAP.md with awk — outputs tab-separated fields per phase
# Fields: phase_num \t slug \t goal \t reqs \t success_criteria \t deps
parsed=$(awk '
BEGIN { OFS="\t"; phase="" }

# Match ## Phase N: Title
/^## Phase [0-9]+:/ {
  # Emit previous phase if any
  if (phase != "") {
    # Clean up trailing whitespace
    gsub(/[[:space:]]+$/, "", goal)
    gsub(/[[:space:]]+$/, "", reqs)
    gsub(/[[:space:]]+$/, "", sc)
    gsub(/[[:space:]]+$/, "", deps)
    print phase, slug, goal, reqs, sc, deps
  }
  # Extract phase number: strip prefix, split on colon
  tmp = $0
  sub(/^## Phase /, "", tmp)
  split(tmp, parts, ":")
  phase = sprintf("%02d", parts[1]+0)
  # Extract title for slug
  title = $0
  sub(/^## Phase [0-9]+:[[:space:]]*/, "", title)
  # Convert title to slug: lowercase, spaces to hyphens, strip non-alnum
  slug = tolower(title)
  gsub(/[^a-z0-9 -]/, "", slug)
  gsub(/[[:space:]]+/, "-", slug)
  gsub(/-+/, "-", slug)
  gsub(/^-|-$/, "", slug)
  # Reset fields
  goal = ""; reqs = ""; sc = ""; deps = ""
  section = ""
  next
}

# Track current section within a phase
phase != "" && /^\*\*Goal:\*\*/ {
  section = "goal"
  line = $0
  sub(/^\*\*Goal:\*\*[[:space:]]*/, "", line)
  goal = line
  next
}
phase != "" && /^\*\*Requirements:\*\*/ {
  section = "reqs"
  line = $0
  sub(/^\*\*Requirements:\*\*[[:space:]]*/, "", line)
  reqs = line
  next
}
phase != "" && /^\*\*Success Criteria:\*\*/ {
  section = "sc"
  line = $0
  sub(/^\*\*Success Criteria:\*\*[[:space:]]*/, "", line)
  sc = line
  next
}
phase != "" && /^\*\*Dependencies:\*\*/ {
  section = "deps"
  line = $0
  sub(/^\*\*Dependencies:\*\*[[:space:]]*/, "", line)
  deps = line
  next
}

# New section or separator resets section
phase != "" && /^---/ { section = ""; next }
phase != "" && /^## / { section = ""; next }

# Collect multi-line content within a section
phase != "" && section != "" && /^[^*#]/ && !/^\*\*[A-Z]/ {
  line = $0
  # Trim leading "- " for bullet points
  sub(/^[[:space:]]*-[[:space:]]*/, "", line)
  if (section == "goal") goal = goal " " line
  else if (section == "reqs") reqs = reqs " " line
  else if (section == "sc") sc = sc " " line
  else if (section == "deps") deps = deps " " line
}

END {
  if (phase != "") {
    gsub(/[[:space:]]+$/, "", goal)
    gsub(/[[:space:]]+$/, "", reqs)
    gsub(/[[:space:]]+$/, "", sc)
    gsub(/[[:space:]]+$/, "", deps)
    print phase, slug, goal, reqs, sc, deps
  }
}
' "$FILE")

COUNT=0
while IFS=$'\t' read -r phase_num slug goal reqs success_criteria deps; do
  [[ -z "$phase_num" ]] && continue

  # Escape single quotes for SQL
  slug_esc=$(printf '%s' "$slug" | sed "s/'/''/g")
  goal_esc=$(printf '%s' "$goal" | sed "s/'/''/g")
  reqs_esc=$(printf '%s' "$reqs" | sed "s/'/''/g")
  sc_esc=$(printf '%s' "$success_criteria" | sed "s/'/''/g")
  deps_esc=$(printf '%s' "$deps" | sed "s/'/''/g")

  sql_exec "$DB" "
INSERT INTO phases (phase_num, slug, goal, reqs, success_criteria, deps)
VALUES ('$phase_num', '$slug_esc', '$goal_esc', '$reqs_esc', '$sc_esc', '$deps_esc')
ON CONFLICT(phase_num) DO UPDATE SET
  slug=excluded.slug,
  goal=excluded.goal,
  reqs=excluded.reqs,
  success_criteria=excluded.success_criteria,
  deps=excluded.deps;
"
  COUNT=$((COUNT + 1))
done <<< "$parsed"

echo "imported $COUNT phases from $FILE"
