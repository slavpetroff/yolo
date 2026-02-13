#!/bin/bash
set -u
# SessionStart(compact) hook: Remind agent to re-read key files after compaction
# Reads compaction context from stdin, detects agent role, suggests re-reads

INPUT=$(cat)

# Clean up cost tracking files (stale after compaction)
rm -f .yolo-planning/.cost-ledger.json .yolo-planning/.active-agent 2>/dev/null

# Try to identify agent role from input context
ROLE=""
for pattern in yolo-lead yolo-dev yolo-qa yolo-scout yolo-debugger yolo-architect; do
  if echo "$INPUT" | grep -qi "$pattern"; then
    ROLE="$pattern"
    break
  fi
done

case "$ROLE" in
  yolo-lead)
    FILES="STATE.md, ROADMAP.md, config.json, and current phase plans"
    ;;
  yolo-dev)
    FILES="your assigned plan.jsonl file and relevant source files"
    ;;
  yolo-qa)
    FILES="summary.jsonl files under review, verification criteria, and gap reports"
    ;;
  yolo-scout)
    FILES="research notes, REQUIREMENTS.md, and any scout-specific findings"
    ;;
  yolo-debugger)
    FILES="reproduction steps, hypothesis log, and related source files"
    ;;
  yolo-architect)
    FILES="REQUIREMENTS.md, ROADMAP.md, phase structure, and architecture decisions"
    ;;
  *)
    FILES="STATE.md, your assigned task context, and any in-progress files"
    ;;
esac

jq -n --arg role "${ROLE:-unknown}" --arg files "$FILES" '{
  "hookSpecificOutput": {
    "additionalContext": ("Context was compacted. Agent role: " + $role + ". Re-read these key files from disk: " + $files)
  }
}'

exit 0
