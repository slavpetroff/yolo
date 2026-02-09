---
name: pause
description: Save session notes for next time (state auto-persists).
argument-hint: [notes]
allowed-tools: Read, Write
---

# VBW Pause: $ARGUMENTS

## Context

Working directory: `!`pwd``

Active milestone:
```
!`cat .vbw-planning/ACTIVE 2>/dev/null || echo "No active milestone (single-milestone mode)"`
```

## Guard

1. **Not initialized:** Follow the Initialization Guard in `${CLAUDE_PLUGIN_ROOT}/references/shared-patterns.md`.

## Steps

### Step 1: Resolve paths

If .vbw-planning/ACTIVE exists: use milestone-scoped RESUME_PATH.
Otherwise: use .vbw-planning/RESUME.md.

### Step 2: Handle notes

**If $ARGUMENTS contains notes:**

Write to RESUME_PATH:

```markdown
# Session Notes

**Saved:** {YYYY-MM-DD HH:MM}

{user's notes}

---
*Run /vbw:resume to restore full project context.*
```

**If no notes provided:**

Do not write RESUME.md. Skip to confirmation.

### Step 3: Present confirmation

```
╔═══════════════════════════════════════════╗
║  Session Paused                           ║
╚═══════════════════════════════════════════╝

  {If notes: "Notes saved to {RESUME_PATH}"}

  State is always saved in .vbw-planning/.
  Nothing to lose, nothing to remember.

➜ Next Up
  /vbw:resume -- Restore full project context
```

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md:
- Double-line box for pause confirmation
- ➜ for Next Up block
- No ANSI color codes
