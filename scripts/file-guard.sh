#!/bin/bash
set -u
# file-guard.sh — PreToolUse guard for undeclared file modifications
# Blocks Write/Edit to files not declared in active plan's files_modified
# Outputs JSON permissionDecision:"deny" + exit 0 to block tool calls.
# Fail-open design: exit 0 on any error, deny only on definitive violations.

# Helper: output deny JSON and exit 0 (Claude Code reads JSON on exit 0)
deny() {
  jq -n --arg reason "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

INPUT=$(cat 2>/dev/null) || exit 0
[ -z "$INPUT" ] && exit 0

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null) || exit 0
[ -z "$FILE_PATH" ] && exit 0

# Exempt planning artifacts — these are always allowed
case "$FILE_PATH" in
  *.yolo-planning/*|*SUMMARY.md|*VERIFICATION.md|*STATE.md|*CLAUDE.md|*.execution-state.json|*.summary.jsonl|*.verification.jsonl|*decisions.jsonl|*research.jsonl)
    exit 0
    ;;
esac

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
PHASES_DIR="$PROJECT_ROOT/.yolo-planning/phases"
[ ! -d "$PHASES_DIR" ] && exit 0

# Find active plan: first plan without a corresponding summary (JSONL or legacy MD)
ACTIVE_PLAN=""
ACTIVE_PLAN_FORMAT=""

# Check JSONL plans first
for PLAN_FILE in "$PHASES_DIR"/*/*.plan.jsonl; do
  [ ! -f "$PLAN_FILE" ] && continue
  SUMMARY_FILE="${PLAN_FILE%.plan.jsonl}.summary.jsonl"
  if [ ! -f "$SUMMARY_FILE" ]; then
    ACTIVE_PLAN="$PLAN_FILE"
    ACTIVE_PLAN_FORMAT="jsonl"
    break
  fi
done

# Fall back to legacy MD plans
if [ -z "$ACTIVE_PLAN" ]; then
  for PLAN_FILE in "$PHASES_DIR"/*/*-PLAN.md; do
    [ ! -f "$PLAN_FILE" ] && continue
    SUMMARY_FILE="${PLAN_FILE%-PLAN.md}-SUMMARY.md"
    if [ ! -f "$SUMMARY_FILE" ]; then
      ACTIVE_PLAN="$PLAN_FILE"
      ACTIVE_PLAN_FORMAT="md"
      break
    fi
  done
fi

# No active plan found — fail-open
[ -z "$ACTIVE_PLAN" ] && exit 0

# Extract files_modified from plan
DECLARED_FILES=""
if [ "$ACTIVE_PLAN_FORMAT" = "jsonl" ] && command -v jq >/dev/null 2>&1; then
  # JSONL: extract fm (files_modified) from header line
  DECLARED_FILES=$(head -1 "$ACTIVE_PLAN" | jq -r '.fm // [] | .[]' 2>/dev/null) || exit 0
else
  # Legacy MD: extract files_modified from YAML frontmatter
  DECLARED_FILES=$(awk '
    BEGIN { in_front=0; in_files=0 }
    /^---$/ {
      if (in_front == 0) { in_front=1; next }
      else { exit }
    }
    in_front && /^files_modified:/ { in_files=1; next }
    in_front && in_files && /^[[:space:]]+- / {
      sub(/^[[:space:]]+- /, "")
      gsub(/["'"'"']/, "")
      print
      next
    }
    in_front && in_files && /^[^[:space:]]/ { in_files=0 }
  ' "$ACTIVE_PLAN" 2>/dev/null) || exit 0
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
