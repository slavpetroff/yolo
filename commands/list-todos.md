---
name: yolo:list-todos
category: supporting
description: List pending todos from STATE.md and select one to act on.
argument-hint: [priority filter]
allowed-tools: Read, Edit, Bash, AskUserQuestion
---

# YOLO List Todos $ARGUMENTS

## Context

Working directory: `!`pwd``
Plugin root: `!`echo ${CLAUDE_PLUGIN_ROOT:-$(ls -1d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/yolo-marketplace/yolo/* 2>/dev/null | (sort -V 2>/dev/null || sort -t. -k1,1n -k2,2n -k3,3n) | tail -1)}``
Active milestone: `!`cat .yolo-planning/ACTIVE 2>/dev/null || echo "No active milestone (single-milestone mode)"``

## Guard

1. **Not initialized** (no .yolo-planning/ dir): STOP "Run /yolo:init first."

## Steps

1. **Load todos:** Run `"$HOME/.cargo/bin/yolo" list-todos {priority-filter}` (omit filter arg if none provided). Parse the JSON output.

2. **Handle status:**
   - `"error"`: STOP with the `message` value.
   - `"empty"`: Display the `display` value. Run `"$HOME/.cargo/bin/yolo" suggest-next list-todos empty` and display. Exit.
   - `"no-match"`: Display the `display` value. Run `"$HOME/.cargo/bin/yolo" suggest-next list-todos empty` and display. Exit.
   - `"ok"`: Continue to step 3.

3. **Display list:** Show the `display` value from the script output, followed by:
   ```text
   Reply with a number to select, or `q` to exit.
   ```

4. **Handle selection:** Wait for user to reply with a number. If invalid: "Invalid selection. Reply with a number (1-N) or `q` to exit."

5. **Show selected todo:** Display the full `text` from the matching `items` entry.

6. **Offer actions:** Use AskUserQuestion:
   - header: "Action"
   - question: "What would you like to do with this todo?"
   - options:
     - "/yolo:fix — Quick fix, one commit, no ceremony"
     - "/yolo:debug — Investigate with scientific method"
     - "/yolo:vibe — Full lifecycle (plan → execute → verify)"
     - "/yolo:research — Research only, no code changes"
     - "Remove — Delete from todo list"
     - "Back — Return to list"

7. **Execute action:** Use the `section` and `state_path` values from the script output for edit operations.
   - **/yolo:fix, /yolo:debug, /yolo:vibe, /yolo:research:** Remove the `line` value from the todo section in STATE.md. If no todos remain, replace with "None." Log to `## Recent Activity` with format `- {YYYY-MM-DD}: Picked up todo via /yolo:{command}: {text}`. Then display:
     ```text
     ✓ Todo picked up.

     ➜ Run: /yolo:{command} {todo text}
     ```
     Do NOT execute the command. STOP after displaying the suggested command.
   - **Remove:** Remove the `line` value from the todo section in STATE.md. If no todos remain, replace with "None." Log to `## Recent Activity` with format `- {YYYY-MM-DD}: Removed todo: {text}`. Confirm: "✓ Todo removed." Run `"$HOME/.cargo/bin/yolo" suggest-next list-todos` and display.
   - **Back:** Return to step 3.

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/yolo-brand-essentials.md — ✓ success, ➜ Next Up, no ANSI.
