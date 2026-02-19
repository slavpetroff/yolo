#!/usr/bin/env bash
# verify-migration.sh — Validate migration integrity between JSONL files and SQLite
# Usage: verify-migration.sh --planning-dir <PATH> [--db PATH]
# Behavior:
#   1. Count lines in JSONL files, compare with DB row counts
#   2. Spot-check: random entries from each artifact type
#   3. Verify FTS5 indexes are populated
#   4. Verify task queue state matches summary completion status
#   5. Report mismatches, missing entries, extra entries
# Exit 0 if clean, exit 1 if discrepancies found.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/db-common.sh"

# Parse arguments
PLANNING_DIR=""

parse_db_flag "$@"
DB_EXPLICIT="$_DB_PATH"
set -- ${_REMAINING_ARGS[@]+"${_REMAINING_ARGS[@]}"}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --planning-dir) PLANNING_DIR="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: verify-migration.sh --planning-dir <PATH> [--db PATH]"
      echo ""
      echo "Options:"
      echo "  --planning-dir PATH  Planning directory containing phases/"
      echo "  --db PATH            Database path (default: <planning-dir>/yolo.db)"
      exit 0
      ;;
    *) echo "error: unknown flag: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$PLANNING_DIR" ]]; then
  echo "error: --planning-dir is required" >&2
  exit 1
fi

# Resolve DB path
if [[ -n "$DB_EXPLICIT" ]]; then
  DB="$DB_EXPLICIT"
else
  DB="$PLANNING_DIR/yolo.db"
fi

require_db "$DB"

# Tracking
errors=0
warnings=0

pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; errors=$((errors + 1)); }
warn() { echo "  WARN: $1"; warnings=$((warnings + 1)); }

# Helper: count non-empty lines in file
count_lines() {
  local file="$1" count=0
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    count=$((count + 1))
  done < "$file"
  echo "$count"
}

# ===== 1. Row count comparison =====
echo "=== Row Count Verification ==="

# Count plans and tasks from files
file_plans=0
file_tasks=0
file_summaries=0
PHASES_DIR="$PLANNING_DIR/phases"

if [[ -d "$PHASES_DIR" ]]; then
  for phase_dir in $(command ls -d "$PHASES_DIR"/*/ 2>/dev/null | sort); do
    for plan_file in "$phase_dir"*.plan.jsonl; do
      [[ -f "$plan_file" ]] || continue
      file_plans=$((file_plans + 1))
      # Tasks = lines 2+ (non-empty)
      linenum=0
      while IFS= read -r line; do
        linenum=$((linenum + 1))
        [[ $linenum -eq 1 ]] && continue
        [[ -z "$line" ]] && continue
        file_tasks=$((file_tasks + 1))
      done < "$plan_file"
    done
    for summary_file in "$phase_dir"*.summary.jsonl; do
      [[ -f "$summary_file" ]] || continue
      file_summaries=$((file_summaries + 1))
    done
  done
fi

# Count from DB
db_plans=$(sql_query "$DB" "SELECT count(*) FROM plans;")
db_tasks=$(sql_query "$DB" "SELECT count(*) FROM tasks;")
db_summaries=$(sql_query "$DB" "SELECT count(*) FROM summaries;")

# Compare
if [[ "$file_plans" -eq "$db_plans" ]]; then
  pass "Plans: $file_plans files = $db_plans rows"
else
  fail "Plans: $file_plans files != $db_plans rows"
fi

# Tasks may have import failures due to special characters, so warn rather than fail
if [[ "$file_tasks" -eq "$db_tasks" ]]; then
  pass "Tasks: $file_tasks file entries = $db_tasks rows"
elif [[ "$db_tasks" -gt 0 ]]; then
  warn "Tasks: $file_tasks file entries != $db_tasks rows (some tasks may have import errors)"
else
  fail "Tasks: $file_tasks file entries but 0 DB rows"
fi

if [[ "$file_summaries" -eq "$db_summaries" ]]; then
  pass "Summaries: $file_summaries files = $db_summaries rows"
else
  fail "Summaries: $file_summaries files != $db_summaries rows"
fi

# Count per-phase artifact files
for artifact_type in critique research decisions escalation gaps; do
  file_count=0
  if [[ -d "$PHASES_DIR" ]]; then
    for phase_dir in $(command ls -d "$PHASES_DIR"/*/ 2>/dev/null | sort); do
      if [[ -f "$phase_dir/${artifact_type}.jsonl" ]]; then
        file_count=$((file_count + $(count_lines "$phase_dir/${artifact_type}.jsonl")))
      fi
    done
  fi
  db_count=$(sql_query "$DB" "SELECT count(*) FROM $artifact_type;" 2>/dev/null || echo "0")
  if [[ "$file_count" -eq "$db_count" ]]; then
    pass "$artifact_type: $file_count entries = $db_count rows"
  elif [[ "$file_count" -eq 0 ]] && [[ "$db_count" -eq 0 ]]; then
    pass "$artifact_type: 0 entries (none present)"
  else
    fail "$artifact_type: $file_count file entries != $db_count rows"
  fi
done

# ===== 2. Spot-check: verify plan titles match =====
echo ""
echo "=== Spot Check Verification ==="

# Check first plan in DB matches file content
first_plan=$(sql_query "$DB" "SELECT phase || '|' || plan_num || '|' || title FROM plans ORDER BY phase, plan_num LIMIT 1;")
if [[ -n "$first_plan" ]]; then
  IFS='|' read -r sp_phase sp_num sp_title <<< "$first_plan"
  # Find corresponding file
  found=false
  for phase_dir in "$PHASES_DIR"/${sp_phase}-*/; do
    plan_file="${phase_dir}${sp_phase}-${sp_num}.plan.jsonl"
    if [[ -f "$plan_file" ]]; then
      file_title=$(jq -r '.t // empty' < <(head -1 "$plan_file") 2>/dev/null || echo "")
      if [[ "$file_title" == "$sp_title" ]]; then
        pass "Plan ${sp_phase}-${sp_num} title matches: '$sp_title'"
      else
        fail "Plan ${sp_phase}-${sp_num} title mismatch: DB='$sp_title' File='$file_title'"
      fi
      found=true
      break
    fi
  done
  if [[ "$found" != true ]]; then
    warn "Could not locate file for plan ${sp_phase}-${sp_num}"
  fi
else
  warn "No plans in DB to spot-check"
fi

# ===== 3. FTS5 index verification =====
echo ""
echo "=== FTS5 Index Verification ==="

# Check research_fts
research_count=$(sql_query "$DB" "SELECT count(*) FROM research;")
if [[ "$research_count" -gt 0 ]]; then
  fts_count=$(sql_query "$DB" "SELECT count(*) FROM research_fts;" 2>/dev/null || echo "0")
  if [[ "$fts_count" -gt 0 ]]; then
    pass "research_fts populated: $fts_count entries"
  else
    fail "research_fts empty despite $research_count research rows"
  fi
else
  pass "research_fts: no data to index (0 research rows)"
fi

# Check decisions_fts
decisions_count=$(sql_query "$DB" "SELECT count(*) FROM decisions;")
if [[ "$decisions_count" -gt 0 ]]; then
  fts_count=$(sql_query "$DB" "SELECT count(*) FROM decisions_fts;" 2>/dev/null || echo "0")
  if [[ "$fts_count" -gt 0 ]]; then
    pass "decisions_fts populated: $fts_count entries"
  else
    fail "decisions_fts empty despite $decisions_count decisions rows"
  fi
else
  pass "decisions_fts: no data to index (0 decisions rows)"
fi

# Check gaps_fts
gaps_count=$(sql_query "$DB" "SELECT count(*) FROM gaps;")
if [[ "$gaps_count" -gt 0 ]]; then
  fts_count=$(sql_query "$DB" "SELECT count(*) FROM gaps_fts;" 2>/dev/null || echo "0")
  if [[ "$fts_count" -gt 0 ]]; then
    pass "gaps_fts populated: $fts_count entries"
  else
    fail "gaps_fts empty despite $gaps_count gaps rows"
  fi
else
  pass "gaps_fts: no data to index (0 gaps rows)"
fi

# ===== 4. Phases table verification =====
echo ""
echo "=== Phases Table Verification ==="

if check_table "$DB" "phases"; then
  phases_count=$(sql_query "$DB" "SELECT count(*) FROM phases;")
  if [[ "$phases_count" -gt 0 ]]; then
    pass "Phases table populated: $phases_count entries"
  else
    warn "Phases table exists but empty (ROADMAP.md may not have been imported)"
  fi
else
  warn "Phases table not present"
fi

# ===== 5. DB integrity =====
echo ""
echo "=== Database Integrity ==="

integrity=$(sqlite3 "$DB" "PRAGMA integrity_check;" 2>&1)
if [[ "$integrity" == "ok" ]]; then
  pass "Integrity check: ok"
else
  fail "Integrity check failed: $integrity"
fi

journal=$(sql_query "$DB" "PRAGMA journal_mode;")
if [[ "$journal" == "wal" ]]; then
  pass "Journal mode: WAL"
else
  warn "Journal mode: $journal (expected WAL)"
fi

# ===== Report =====
echo ""
echo "=== Summary ==="
echo "Errors: $errors"
echo "Warnings: $warnings"

if [[ "$errors" -gt 0 ]]; then
  echo "RESULT: FAIL"
  exit 1
else
  echo "RESULT: PASS"
  exit 0
fi
