#!/bin/bash
set -u
# PreCompact hook: Inject agent-specific summarization priorities
# Reads agent context and returns additionalContext for compaction

INPUT=$(cat)
AGENT_NAME=$(echo "$INPUT" | jq -r '.agent_name // .agentName // ""')
MATCHER=$(echo "$INPUT" | jq -r '.matcher // "auto"')

case "$AGENT_NAME" in
  *scout*)
    PRIORITIES="Preserve research findings, URLs, confidence assessments"
    ;;
  *dev*)
    PRIORITIES="Preserve commit hashes, file paths modified, deviation decisions, current task number. After compaction, if .yolo-planning/codebase/META.md exists, re-read CONVENTIONS.md, PATTERNS.md, STRUCTURE.md, and DEPENDENCIES.md (whichever exist) from .yolo-planning/codebase/"
    ;;
  *qa*)
    PRIORITIES="Preserve pass/fail status, gap descriptions, verification results. After compaction, if .yolo-planning/codebase/META.md exists, re-read TESTING.md, CONCERNS.md, and ARCHITECTURE.md (whichever exist) from .yolo-planning/codebase/"
    ;;
  *lead*)
    PRIORITIES="Preserve phase status, plan structure, coordination decisions. After compaction, if .yolo-planning/codebase/META.md exists, re-read ARCHITECTURE.md, CONCERNS.md, and STRUCTURE.md (whichever exist) from .yolo-planning/codebase/"
    ;;
  *architect*)
    PRIORITIES="Preserve requirement IDs, phase structure, success criteria, key decisions. After compaction, if .yolo-planning/codebase/META.md exists, re-read ARCHITECTURE.md and STACK.md (whichever exist) from .yolo-planning/codebase/"
    ;;
  *debugger*)
    PRIORITIES="Preserve reproduction steps, hypotheses, evidence gathered, diagnosis. After compaction, if .yolo-planning/codebase/META.md exists, re-read ARCHITECTURE.md, CONCERNS.md, PATTERNS.md, and DEPENDENCIES.md (whichever exist) from .yolo-planning/codebase/"
    ;;
  *)
    PRIORITIES="Preserve active command being executed, user's original request, current phase/plan context, file modification paths, any pending user decisions. Discard: tool output details, reference file contents (re-read from disk), previous command results"
    ;;
esac

# Add compact trigger context
if [ "$MATCHER" = "manual" ]; then
  PRIORITIES="$PRIORITIES. User requested compaction."
else
  PRIORITIES="$PRIORITIES. This is an automatic compaction at context limit."
fi

# Write compaction marker for Dev re-read guard (REQ-14)
if [ -d ".yolo-planning" ]; then
  date +%s > .yolo-planning/.compaction-marker 2>/dev/null || true
fi

# --- Save agent state snapshot ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f ".yolo-planning/.execution-state.json" ] && [ -f "$SCRIPT_DIR/snapshot-resume.sh" ]; then
  SNAP_PHASE=$(jq -r '.phase // ""' ".yolo-planning/.execution-state.json" 2>/dev/null)
  if [ -n "$SNAP_PHASE" ]; then
    bash "$SCRIPT_DIR/snapshot-resume.sh" save "$SNAP_PHASE" ".yolo-planning/.execution-state.json" "$AGENT_NAME" "$MATCHER" 2>/dev/null || true
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%d %H:%M:%S")
    echo "[$TIMESTAMP] Snapshot saved: phase=$SNAP_PHASE agent=$AGENT_NAME" >> ".yolo-planning/.hook-errors.log" 2>/dev/null || true
  fi
fi

jq -n --arg ctx "$PRIORITIES" '{
  "hookEventName": "PreCompact",
  "hookSpecificOutput": {
    "hookEventName": "PreCompact",
    "additionalContext": ("Compaction priorities: " + $ctx + " Re-read assigned files from disk after compaction.")
  }
}'

exit 0
