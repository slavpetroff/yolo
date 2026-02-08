#!/bin/bash
# TeammateIdle hook: Verify teammate's work via structural completion checks
# Exit 2 = block (keep working), Exit 0 = allow idle
# Exit 0 on ANY error (fail-open: never block legitimate work)

# Read stdin to get task context
INPUT=$(cat 2>/dev/null) || exit 0

# Structural Check 1: SUMMARY.md existence
# Check if any *-SUMMARY.md in .planning/phases/*/ was modified within last 2 hours
RECENT_SUMMARY=false
NOW=$(date +%s 2>/dev/null) || exit 0
TWO_HOURS=7200

for summary_file in .planning/phases/*/*-SUMMARY.md; do
  [ -f "$summary_file" ] || continue

  # Get file modification time (macOS vs Linux)
  FILE_MTIME=$(stat -f %m "$summary_file" 2>/dev/null || stat -c %Y "$summary_file" 2>/dev/null) || continue

  if [ -n "$FILE_MTIME" ] && [ "$FILE_MTIME" -gt 0 ] 2>/dev/null; then
    AGE=$(( NOW - FILE_MTIME ))
    if [ "$AGE" -le "$TWO_HOURS" ]; then
      RECENT_SUMMARY=true
      break
    fi
  fi
done

# Structural Check 2: Commit format
# Check if recent commits (last 10, within 2 hours) match GSD conventional format
FORMAT_MATCH=false
RECENT_COMMITS=$(git log --oneline -10 --format="%ct %s" 2>/dev/null) || exit 0

while IFS= read -r line; do
  [ -z "$line" ] && continue
  COMMIT_TS=$(echo "$line" | cut -d' ' -f1)
  COMMIT_MSG=$(echo "$line" | cut -d' ' -f2-)

  if [ -n "$COMMIT_TS" ] && [ "$COMMIT_TS" -gt 0 ] 2>/dev/null; then
    AGE=$(( NOW - COMMIT_TS ))
    if [ "$AGE" -le "$TWO_HOURS" ]; then
      # Check for GSD conventional commit format: type(XX-YY):
      if echo "$COMMIT_MSG" | grep -qE '^(feat|fix|refactor|docs|test|chore)\([0-9]{2}-[0-9]{2}\):'; then
        FORMAT_MATCH=true
        break
      fi
    fi
  fi
done <<< "$RECENT_COMMITS"

# Decision: either structural indicator is sufficient
if [ "$RECENT_SUMMARY" = true ] || [ "$FORMAT_MATCH" = true ]; then
  exit 0
fi

echo "QA gate: no structural completion indicators found (no recent SUMMARY.md, no conventional commits)" >&2
exit 2
