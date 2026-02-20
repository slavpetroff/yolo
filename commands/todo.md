---
name: yolo:todo
category: supporting
disable-model-invocation: true
description: Add an item to the persistent backlog in STATE.md.
argument-hint: <todo-description> [--priority=high|normal|low]
allowed-tools: Read, Edit
---

# YOLO Todo: $ARGUMENTS

## Context

Working directory: `!`pwd``
Plugin root: `!`echo ${CLAUDE_PLUGIN_ROOT:-$(ls -1d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/yolo-marketplace/yolo/* 2>/dev/null | (sort -V 2>/dev/null || sort -t. -k1,1n -k2,2n -k3,3n) | tail -1)}``
Active milestone: `!`cat .yolo-planning/ACTIVE 2>/dev/null || echo "No active milestone (single-milestone mode)"``

## Guard

1. **Not initialized** (no .yolo-planning/ dir): STOP "Run /yolo:init first."
2. **Missing description:** STOP: "Usage: /yolo:todo <description> [--priority=high|normal|low]"

## Steps

1. **Resolve context:** Always use `.yolo-planning/STATE.md` for todos — project-level data lives at the root, not in milestone subdirectories. If `.yolo-planning/STATE.md` does not exist:
   - **ACTIVE milestone exists:** Create root STATE.md by running: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/persist-state-after-ship.sh .yolo-planning/milestones/{SLUG}/STATE.md .yolo-planning/STATE.md "{PROJECT_NAME}"` (read SLUG from `.yolo-planning/ACTIVE`, PROJECT_NAME from the milestone STATE.md `**Project:**` line).
   - **No ACTIVE but archived milestones exist** (any `.yolo-planning/milestones/*/STATE.md`): Recover by running `bash ${CLAUDE_PLUGIN_ROOT}/scripts/migrate-orphaned-state.sh .yolo-planning` — this picks the most recent archived milestone by modification time and creates root STATE.md.
   - **No STATE.md anywhere:** STOP: "STATE.md not found. Run /yolo:init to set up your project."
2. **Parse args:** Description (non-flag text), --priority (default: normal). Format: high=`[HIGH]`, normal=plain, low=`[low]`. Append `(added {YYYY-MM-DD})`.
3. **Add to STATE.md:** Find `## Todos` section. Replace "None." / placeholder or append after last item.
4. **Confirm:** Display ✓ + formatted item + Next Up (/yolo:status).

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/yolo-brand-essentials.md — ✓ success, Next Up, no ANSI.
