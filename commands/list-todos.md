---
name: vbw:list-todos
category: supporting
description: List pending todos from STATE.md and select one to act on.
argument-hint: [priority filter]
allowed-tools: Read, Edit, Bash, AskUserQuestion
---

# VBW List Todos $ARGUMENTS

## Context

Working directory: `!`pwd``
Plugin root: `!`echo ${CLAUDE_PLUGIN_ROOT:-$(ls -1d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/vbw-marketplace/vbw/* 2>/dev/null | (sort -V 2>/dev/null || sort -t. -k1,1n -k2,2n -k3,3n) | tail -1)}``
Active milestone: `!`cat .vbw-planning/ACTIVE 2>/dev/null || echo "No active milestone (single-milestone mode)"``

## Guard

1. **Not initialized** (no .vbw-planning/ dir): STOP "Run /vbw:init first."

## Steps

1. **Load todos:** Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/list-todos.sh {priority-filter}` (omit filter arg if none provided). Parse the JSON output.

2. **Handle status:**
   - `"error"`: STOP with the `message` value.
   - `"empty"`: Display the `display` value. Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/suggest-next.sh list-todos empty` and display. Exit.
   - `"no-match"`: Display the `display` value. Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/suggest-next.sh list-todos empty` and display. Exit.
   - `"ok"`: Continue to step 3.

3. **Display list:** Show the `display` value from the script output, followed by:
   ```text
   Reply with a number to select, or `q` to exit.
   ```

4. **Handle selection:** Wait for user to reply with a number. If invalid: "Invalid selection. Reply with a number (1-N) or `q` to exit."

5. **Show selected todo:** Display the full `text` from the matching `items` entry. Use the `section` and `state_path` values from the script output for edit operations.

6. **Offer actions:** Use AskUserQuestion:
   - header: "Action"
   - question: "What would you like to do with this todo?"
   - options:
     - "Work on it now" — remove from todos, begin working
     - "Remove it" — remove from todos (completed or no longer needed)
     - "Go back" — return to list

7. **Execute action:** Remove/edit within whichever section the script reported (the `section` field — either `### Pending Todos` or `## Todos`).
   - **Work on it now:** Remove the `line` value from the section in STATE.md. If no todos remain, replace with "None." Confirm: "✓ Removed todo — ready to work." Then present the todo context and ask how to proceed.
   - **Remove it:** Remove the `line` value from the section in STATE.md. If no todos remain, replace with "None." Confirm: "✓ Todo removed." Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/suggest-next.sh list-todos` and display.
   - **Go back:** Return to step 3.

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md — ✓ success, ➜ Next Up, no ANSI.
