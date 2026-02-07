---
description: Add an item to the persistent backlog in STATE.md.
argument-hint: <todo-description> [--priority=high|normal|low]
allowed-tools: Read, Edit
---

# VBW Todo: $ARGUMENTS

## Context

Working directory: `!`pwd``

Current state:
```
!`cat .planning/STATE.md 2>/dev/null || echo "No state found"`
```

Active milestone:
```
!`cat .planning/ACTIVE 2>/dev/null || echo "No active milestone (single-milestone mode)"`
```

## Guard

1. **Not initialized:** If .planning/ directory doesn't exist, STOP: "Run /vbw:init first."
2. **Missing description:** If $ARGUMENTS is empty, STOP: "Usage: /vbw:todo <description> [--priority=high|normal|low]"

## Steps

### Step 1: Resolve milestone context

Standard milestone resolution:
- If .planning/ACTIVE exists: read slug, set STATE_PATH to .planning/{slug}/STATE.md
- If .planning/ACTIVE does not exist: set STATE_PATH to .planning/STATE.md

### Step 2: Parse arguments

Extract the todo description from $ARGUMENTS (everything that is not a flag).
Extract optional --priority flag (default: normal).

Format the todo item based on priority:
- **high priority:** `- [HIGH] {description} (added {YYYY-MM-DD})`
- **normal priority:** `- {description} (added {YYYY-MM-DD})`
- **low priority:** `- [low] {description} (added {YYYY-MM-DD})`

### Step 3: Add to STATE.md

Read STATE_PATH and find the `### Pending Todos` section.

- If the section currently contains "None." or "None", replace that line with the new todo item.
- Otherwise, append the new todo item after the last existing item in the Pending Todos section (before the next section heading or end of file).

Use the Edit tool to make the change.

### Step 4: Present confirmation

Display using brand formatting from @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand.md:

```
✓ Todo added to backlog

  {todo-item-as-formatted}

➜ View all: /vbw:status
```

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand.md for all visual formatting:
- ✓ for success confirmation
- Next Up Block for navigation
- No ANSI color codes
