---
name: pause
disable-model-invocation: true
description: Save session notes for next time (state auto-persists).
argument-hint: [notes]
allowed-tools: Read, Write
---

# YOLO Pause: $ARGUMENTS

## Context

Working directory: `!`pwd``
Active milestone: `!`cat .yolo-planning/ACTIVE 2>/dev/null || echo "No active milestone (single-milestone mode)"``

## Guard

1. **Not initialized** (no .yolo-planning/ dir): STOP "Run /yolo:init first."

## Steps

1. **Resolve paths:** ACTIVE → milestone-scoped RESUME_PATH. Otherwise → .yolo-planning/RESUME.md.
2. **Handle notes:** If $ARGUMENTS has notes: write RESUME.md with timestamp + notes + resume hint. If no notes: skip write.
3. **Present:** Phase Banner "Session Paused". Show notes path if saved. "State is always saved in .yolo-planning/. Nothing to lose, nothing to remember." Next Up: /yolo:resume.

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/yolo-brand-essentials.md — double-line box, ➜ Next Up, no ANSI.
