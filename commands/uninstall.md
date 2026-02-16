---
name: uninstall
disable-model-invocation: true
description: Cleanly remove all YOLO traces from the system before plugin uninstall.
argument-hint:
allowed-tools: Read, Write, Edit, Bash, Glob
---

# YOLO Uninstall

## Context

Settings:
```
!`cat "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json" 2>/dev/null || echo "{}"`
```
Planning dir: `!`ls -d .yolo-planning 2>/dev/null && echo "EXISTS" || echo "NONE"``
CLAUDE.md: `!`ls CLAUDE.md 2>/dev/null && echo "EXISTS" || echo "NONE"``

## Steps

### Step 1: Confirm intent

Display Phase Banner "YOLO Uninstall" explaining system-level config removal. Project files handled separately. Ask confirmation.

### Step 2: Remove global commands

If `CLAUDE_DIR/commands/yolo/` exists (where CLAUDE_DIR = `$CLAUDE_CONFIG_DIR` or `~/.claude`): `rm -rf CLAUDE_DIR/commands/yolo/`. If parent now empty, remove it too. Display ✓.

### Step 3: Clean statusLine

If statusLine contains `yolo-statusline`: remove key, ✓. Not YOLO's: "○ Skipped".

### Step 4: Clean Agent Teams env var

If Agent Teams exists: ask user (other tools may use). Approved: remove. Declined: "○ Kept".

### Step 5: Project data

If `.yolo-planning/` exists: ask keep (recommended) or `rm -rf`.

### Step 6: CLAUDE.md cleanup

If exists: ask keep or delete.

### Step 7: Summary

Display Phase Banner "YOLO Cleanup Complete" with ✓/○ per step. Then:
```
➜ Final Step
  /plugin uninstall yolo@yolo-marketplace
  Then optionally: /plugin marketplace remove yolo-marketplace
```
**Do NOT run plugin uninstall yourself** — it would remove itself mid-execution.

## Output Format

Per @${CLAUDE_PLUGIN_ROOT}/references/yolo-brand-essentials.toon -- double-line box, ✓/○ symbols, Next Up, no ANSI.
