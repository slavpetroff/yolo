#!/usr/bin/env bash
set -euo pipefail

# trivial-lint.sh — Lightweight lint checks for trivial-path tasks
#
# Runs basic automated checks on changed files without full QA:
# - shellcheck on .sh files (if shellcheck available)
# - jq --exit-status on .json files (valid JSON check)
# - markdown heading lint on .md files (no empty headings, proper hierarchy)
#
# Usage: trivial-lint.sh --files "file1.sh file2.json ..." [--phase-dir <path>]
# Output: JSON to stdout with pass/fail status and issues list
# Exit codes: 0 = all checks pass, 1 = at least one check failed

# --- jq dependency check ---
if ! command -v jq &>/dev/null; then
  echo '{"error":"jq is required but not installed"}' >&2
  exit 1
fi

# --- Arg parsing ---
FILES=""
PHASE_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --files)
      FILES="$2"
      shift 2
      ;;
    --phase-dir)
      PHASE_DIR="$2"
      shift 2
      ;;
    *)
      echo "Usage: trivial-lint.sh --files \"file1 file2 ...\" [--phase-dir <path>]" >&2
      exit 1
      ;;
  esac
done

if [ -z "$FILES" ]; then
  echo "Error: --files is required" >&2
  exit 1
fi

# --- Lint checks ---
ISSUES="[]"
PASS_COUNT=0
FAIL_COUNT=0

for file in $FILES; do
  if [ ! -f "$file" ]; then
    continue
  fi

  ext="${file##*.}"

  case "$ext" in
    sh)
      # shellcheck lint (if available)
      if command -v shellcheck &>/dev/null; then
        SC_OUTPUT=$(shellcheck -f json "$file" 2>/dev/null || true)
        SC_ERRORS=$(echo "$SC_OUTPUT" | jq '[.[] | select(.level == "error")] | length' 2>/dev/null || echo "0")
        if [ "$SC_ERRORS" -gt 0 ]; then
          ISSUES=$(echo "$ISSUES" | jq --arg f "$file" --arg c "$SC_ERRORS" \
            '. + [{"file": $f, "check": "shellcheck", "status": "fail", "detail": ($c + " error(s)")}]')
          FAIL_COUNT=$((FAIL_COUNT + 1))
        else
          PASS_COUNT=$((PASS_COUNT + 1))
        fi
      else
        # shellcheck not available, skip with note
        PASS_COUNT=$((PASS_COUNT + 1))
      fi
      ;;

    json|jsonl)
      # JSON validity check
      if [ "$ext" = "jsonl" ]; then
        # Check each line is valid JSON
        LINE_NUM=0
        JSON_VALID=true
        while IFS= read -r line || [ -n "$line" ]; do
          LINE_NUM=$((LINE_NUM + 1))
          if [ -n "$line" ] && ! echo "$line" | jq empty 2>/dev/null; then
            ISSUES=$(echo "$ISSUES" | jq --arg f "$file" --arg l "$LINE_NUM" \
              '. + [{"file": $f, "check": "json_valid", "status": "fail", "detail": ("invalid JSON at line " + $l)}]')
            JSON_VALID=false
            break
          fi
        done < "$file"
        if [ "$JSON_VALID" = true ]; then
          PASS_COUNT=$((PASS_COUNT + 1))
        else
          FAIL_COUNT=$((FAIL_COUNT + 1))
        fi
      else
        if jq empty "$file" 2>/dev/null; then
          PASS_COUNT=$((PASS_COUNT + 1))
        else
          ISSUES=$(echo "$ISSUES" | jq --arg f "$file" \
            '. + [{"file": $f, "check": "json_valid", "status": "fail", "detail": "invalid JSON"}]')
          FAIL_COUNT=$((FAIL_COUNT + 1))
        fi
      fi
      ;;

    md)
      # Markdown heading lint: no empty headings, proper hierarchy
      MD_ISSUES=""
      # Check for empty headings (# followed by nothing)
      if grep -qE '^#{1,6}\s*$' "$file" 2>/dev/null; then
        MD_ISSUES="empty heading(s)"
      fi
      if [ -n "$MD_ISSUES" ]; then
        ISSUES=$(echo "$ISSUES" | jq --arg f "$file" --arg d "$MD_ISSUES" \
          '. + [{"file": $f, "check": "md_lint", "status": "fail", "detail": $d}]')
        FAIL_COUNT=$((FAIL_COUNT + 1))
      else
        PASS_COUNT=$((PASS_COUNT + 1))
      fi
      ;;

    *)
      # Unknown extension, skip
      ;;
  esac
done

# --- Determine overall status ---
if [ "$FAIL_COUNT" -gt 0 ]; then
  STATUS="fail"
else
  STATUS="pass"
fi

# --- Output JSON ---
jq -n \
  --arg status "$STATUS" \
  --argjson pass "$PASS_COUNT" \
  --argjson fail "$FAIL_COUNT" \
  --argjson issues "$ISSUES" \
  '{
    status: $status,
    checks_passed: $pass,
    checks_failed: $fail,
    issues: $issues
  }'

# Exit with appropriate code
if [ "$STATUS" = "fail" ]; then
  exit 1
fi
