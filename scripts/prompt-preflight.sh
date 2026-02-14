#!/bin/bash
set -u
# UserPromptSubmit: Pre-flight validation for YOLO commands (non-blocking, exit 0)

PLANNING_DIR=".yolo-planning"
[ -d "$PLANNING_DIR" ] || exit 0

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // .content // ""' 2>/dev/null)
[ -z "$PROMPT" ] && exit 0

# GSD Isolation: manage .yolo-session marker
if [ -f "$PLANNING_DIR/.gsd-isolation" ]; then
  if echo "$PROMPT" | grep -qi '^/yolo:'; then
    echo "session" > "$PLANNING_DIR/.yolo-session"
  else
    rm -f "$PLANNING_DIR/.yolo-session"
  fi
fi

WARNING=""

# Check: Prompt might trigger EnterPlanMode bypass
# Detect prompts that ask for planning/building outside YOLO commands
if [ -f "$PLANNING_DIR/PROJECT.md" ]; then
  # Project exists — any work should go through /yolo:go
  if ! echo "$PROMPT" | grep -qi '^/yolo:'; then
    # Not a YOLO command — check for action-oriented keywords
    LOWER_PROMPT=$(echo "$PROMPT" | tr '[:upper:]' '[:lower:]')
    if echo "$LOWER_PROMPT" | grep -qE '(plan|build|implement|create|add|refactor|fix|develop|design|architect|scope|decompose) '; then
      WARNING="This project uses YOLO workflows. Use /yolo:go instead of direct prompts. NEVER use EnterPlanMode — all planning goes through /yolo:go."
    fi
  fi
fi

# Check: /yolo:go --execute when no PLAN.md exists
if echo "$PROMPT" | grep -q '/yolo:go.*--execute'; then
  CURRENT_PHASE=""
  if [ -f "$PLANNING_DIR/state.json" ] && command -v jq >/dev/null 2>&1; then
    CURRENT_PHASE=$(jq -r '.ph // ""' "$PLANNING_DIR/state.json" 2>/dev/null)
    [ "$CURRENT_PHASE" != "null" ] && [ -n "$CURRENT_PHASE" ] && CURRENT_PHASE=$(printf '%02d' "$CURRENT_PHASE")
  elif [ -f "$PLANNING_DIR/STATE.md" ]; then
    CURRENT_PHASE=$(grep -m1 "Current Phase" "$PLANNING_DIR/STATE.md" 2>/dev/null | grep -oE '[0-9]+' | head -1)
  fi

  if [ -n "$CURRENT_PHASE" ]; then
    PHASE_DIR="$PLANNING_DIR/phases/$CURRENT_PHASE"
    PLAN_COUNT=$(find "$PHASE_DIR" -name "*.plan.jsonl" -o -name "*-PLAN.md" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$PLAN_COUNT" -eq 0 ]; then
      WARNING="No plans for phase $CURRENT_PHASE. Run /yolo:go to plan first."
    fi
  fi
fi

# Check: /yolo:go --archive with incomplete phases
if echo "$PROMPT" | grep -q '/yolo:go.*--archive'; then
  if [ -f "$PLANNING_DIR/STATE.md" ]; then
    INCOMPLETE=$(grep -c "status:.*incomplete\|status:.*in.progress\|status:.*pending" "$PLANNING_DIR/STATE.md" 2>/dev/null || echo 0)
    if [ "$INCOMPLETE" -gt 0 ]; then
      WARNING="$INCOMPLETE incomplete phase(s). Review STATE.md before shipping."
    fi
  fi
fi

if [ -n "$WARNING" ]; then
  jq -n --arg msg "$WARNING" '{
    "hookSpecificOutput": {
      "additionalContext": ("YOLO pre-flight warning: " + $msg)
    }
  }'
fi

exit 0
