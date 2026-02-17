#!/bin/bash
set -u
# UserPromptSubmit: Pre-flight validation for YOLO commands (non-blocking, exit 0)

PLANNING_DIR=".yolo-planning"
[ -d "$PLANNING_DIR" ] || exit 0

INPUT=$(cat)
PROMPT=$(jq -r '.prompt // .content // ""' <<< "$INPUT" 2>/dev/null)
[ -z "$PROMPT" ] && exit 0

# Compute lowercase prompt once for all checks
LOWER_PROMPT=$(printf '%s' "$PROMPT" | tr '[:upper:]' '[:lower:]')

# GSD Isolation: manage .yolo-session marker
if [ -f "$PLANNING_DIR/.gsd-isolation" ]; then
  case "$LOWER_PROMPT" in
    /yolo:*) echo "session" > "$PLANNING_DIR/.yolo-session" ;;
    *) rm -f "$PLANNING_DIR/.yolo-session" ;;
  esac
fi

WARNING=""

# Check: Prompt might trigger EnterPlanMode bypass
# Detect prompts that ask for planning/building outside YOLO commands
if [ -f "$PLANNING_DIR/PROJECT.md" ]; then
  # Project exists — any work should go through /yolo:go
  case "$LOWER_PROMPT" in
    /yolo:*) ;;  # YOLO command — no warning needed
    *)
      # Check for action-oriented keywords (word-boundary matching, no trailing space required)
      case "$LOWER_PROMPT" in
        *plan*|*build*|*implement*|*create*|*refactor*|*develop*|*design*|*architect*|*scope*|*decompose*|*execute*|*ship*|*deploy*|*test*|*debug*|*investigate*|*fix*|*patch*|*hotfix*)
          WARNING="This project uses YOLO workflows. Use /yolo:go instead of direct prompts. NEVER use EnterPlanMode or spawn ad-hoc agents — all work goes through /yolo:go."
          ;;
      esac
      ;;
  esac
fi

# Check: /yolo:go --execute when no PLAN.md exists
case "$LOWER_PROMPT" in
  */yolo:go*--execute*)
    CURRENT_PHASE=""
    if [ -f "$PLANNING_DIR/state.json" ] && command -v jq >/dev/null 2>&1; then
      CURRENT_PHASE=$(jq -r '.ph // ""' "$PLANNING_DIR/state.json" 2>/dev/null)
      [ "$CURRENT_PHASE" != "null" ] && [ -n "$CURRENT_PHASE" ] && CURRENT_PHASE=$(printf '%02d' "$CURRENT_PHASE")
    elif [ -f "$PLANNING_DIR/STATE.md" ]; then
      CURRENT_PHASE=$(grep -m1 "Current Phase" "$PLANNING_DIR/STATE.md" 2>/dev/null | grep -oE '[0-9]+' | head -1)
    fi

    if [ -n "$CURRENT_PHASE" ]; then
      PHASE_DIR="$PLANNING_DIR/phases/$CURRENT_PHASE"
      PLAN_COUNT=0
      for f in "$PHASE_DIR"/*.plan.jsonl "$PHASE_DIR"/*-PLAN.md; do
        [ -f "$f" ] && PLAN_COUNT=$((PLAN_COUNT+1))
      done
      if [ "$PLAN_COUNT" -eq 0 ]; then
        WARNING="No plans for phase $CURRENT_PHASE. Run /yolo:go to plan first."
      fi
    fi
    ;;
esac

# Check: /yolo:go --archive with incomplete phases
case "$LOWER_PROMPT" in
  */yolo:go*--archive*)
    if [ -f "$PLANNING_DIR/STATE.md" ]; then
      INCOMPLETE=$(grep -c "status:.*incomplete\|status:.*in.progress\|status:.*pending" "$PLANNING_DIR/STATE.md" 2>/dev/null || echo 0)
      if [ "$INCOMPLETE" -gt 0 ]; then
        WARNING="$INCOMPLETE incomplete phase(s). Review STATE.md before shipping."
      fi
    fi
    ;;
esac

if [ -n "$WARNING" ]; then
  jq -n --arg msg "$WARNING" '{
    "hookSpecificOutput": {
      "additionalContext": ("YOLO pre-flight warning: " + $msg)
    }
  }'
fi

exit 0
