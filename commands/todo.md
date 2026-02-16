---
name: todo
disable-model-invocation: true
description: Add an item to the persistent backlog in STATE.md.
argument-hint: <todo-description> [--priority=high|normal|low]
allowed-tools: Read, Edit
---

# YOLO Todo: $ARGUMENTS

## Context

Working directory: `!`pwd``

## Guard

1. Guard: no .yolo-planning/ -> STOP "YOLO is not set up yet. Run /yolo:init to get started."
2. **Missing description:** STOP: "Missing required input. Usage: /yolo:todo <description> [--priority=high|normal|low]"

## Steps

1. **Resolve context:** ACTIVE → milestone-scoped STATE_PATH. Otherwise → .yolo-planning/STATE.md.
2. **Parse args:** Description (non-flag text), --priority (default: normal). Format: high=`[HIGH]`, normal=plain, low=`[low]`. Append `(added {YYYY-MM-DD})`.
3. **Add to STATE.md:** Find `### Pending Todos`. Replace "None." or append after last item.
4. **Confirm:** Display ✓ + formatted item + Next Up (/yolo:status).

## Output Format

Per @${CLAUDE_PLUGIN_ROOT}/references/yolo-brand-essentials.toon -- single-line box, ✓ symbols, Next Up, no ANSI.
