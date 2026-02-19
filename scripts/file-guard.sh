#!/bin/bash
set -u
# file-guard.sh — PreToolUse guard for undeclared file modifications
# Blocks Write/Edit to files not declared in active plan's files_modified
# Outputs JSON permissionDecision:"deny" + exit 0 to block tool calls.
# Fail-open design: exit 0 on any error, deny only on definitive violations.

# Helper: output deny JSON and exit 0 (Claude Code reads JSON on exit 0)
# Uses printf instead of jq -n to save ~7.3ms per deny call.
deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
  exit 0
}

# Find project root by walking up from $PWD
find_project_root() {
  local dir="$PWD"
  while [ "$dir" != "/" ]; do
    if [ -d "$dir/.yolo-planning/phases" ]; then
      echo "$dir"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 1
}

PROJECT_ROOT=$(find_project_root) || exit 0

# EARLY EXIT: check execution state BEFORE reading stdin (saves cat+jq when not running)
EXEC_STATE="$PROJECT_ROOT/.yolo-planning/.execution-state.json"
if [ ! -f "$EXEC_STATE" ]; then
  exit 0
fi
EXEC_STATUS=$(jq -r '.status // ""' "$EXEC_STATE" 2>/dev/null) || exit 0
if [ "$EXEC_STATUS" != "running" ]; then
  exit 0
fi

# Now read stdin and parse (only when execution is active)
INPUT=$(cat 2>/dev/null) || exit 0
[ -z "$INPUT" ] && exit 0

FILE_PATH=$(jq -r '.tool_input.file_path // ""' <<< "$INPUT" 2>/dev/null) || exit 0
[ -z "$FILE_PATH" ] && exit 0

# Exempt planning artifacts — these are always allowed
case "$FILE_PATH" in
  *.yolo-planning/*|*SUMMARY.md|*VERIFICATION.md|*STATE.md|*CLAUDE.md|*.execution-state.json|*.summary.jsonl|*.verification.jsonl|*decisions.jsonl|*research.jsonl)
    exit 0
    ;;
esac

PHASES_DIR="$PROJECT_ROOT/.yolo-planning/phases"
[ ! -d "$PHASES_DIR" ] && exit 0

# Find active plan via DB (DB is single source of truth)
DECLARED_FILES=""
_FG_DB="$PROJECT_ROOT/.yolo-planning/yolo.db"
if [ -f "$_FG_DB" ] && command -v sqlite3 >/dev/null 2>&1; then
  # Find first plan without a completed summary
  _fm_json=$(sqlite3 "$_FG_DB" "
    SELECT p.fm FROM plans p
    LEFT JOIN summaries s ON s.plan_id = p.rowid
    WHERE s.rowid IS NULL AND p.fm IS NOT NULL AND p.fm != '' AND p.fm != 'null'
    ORDER BY p.phase, p.plan_num
    LIMIT 1;
  " 2>/dev/null) || true

  # Also check task-level files
  if [ -z "$_fm_json" ]; then
    _fm_json=$(sqlite3 "$_FG_DB" "
      SELECT GROUP_CONCAT(t.files, ',') FROM tasks t
      JOIN plans p ON t.plan_id = p.rowid
      LEFT JOIN summaries s ON s.plan_id = p.rowid
      WHERE s.rowid IS NULL AND t.files IS NOT NULL AND t.files != '' AND t.files != 'null'
      ORDER BY p.phase, p.plan_num
      LIMIT 1;
    " 2>/dev/null) || true
  fi

  if [ -n "$_fm_json" ] && command -v jq >/dev/null 2>&1; then
    DECLARED_FILES=$(echo "$_fm_json" | jq -r 'if type == "array" then .[] elif type == "string" then split(",")[] else . end' 2>/dev/null) || true
  fi
fi

# No files_modified declared — fail-open
[ -z "$DECLARED_FILES" ] && exit 0

# Normalize the target file path: strip ./ prefix, convert absolute to relative
normalize_path() {
  local p="$1"
  # Convert absolute to relative (strip project root prefix)
  if [ -n "$PROJECT_ROOT" ]; then
    p="${p#"$PROJECT_ROOT"/}"
  fi
  # Strip leading ./
  p="${p#./}"
  echo "$p"
}

NORM_TARGET=$(normalize_path "$FILE_PATH")

# Check if target file is in declared files
while IFS= read -r declared; do
  [ -z "$declared" ] && continue
  NORM_DECLARED=$(normalize_path "$declared")
  if [ "$NORM_TARGET" = "$NORM_DECLARED" ]; then
    exit 0
  fi
done <<< "$DECLARED_FILES"

# File not declared — block the write
deny "Blocked: $NORM_TARGET is not in active plan's files_modified ($ACTIVE_PLAN)"
