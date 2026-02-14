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

Read `CLAUDE_DIR/settings.json`. If statusLine contains `yolo-statusline`: remove entire statusLine key, display ✓. If not YOLO's: "○ Statusline is not YOLO's — skipped".

### Step 4: Clean Agent Teams env var

If `env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` exists: ask user (it's a Claude Code feature other tools may use). Approved: remove (if env then empty, remove env key). Declined: "○ Agent Teams setting kept".

### Step 5: Project data

If `.yolo-planning/` exists: ask keep (recommended) or delete. Delete: `rm -rf .yolo-planning/`.

### Step 6: CLAUDE.md cleanup

If CLAUDE.md exists: ask keep or delete.

### Step 7: Summary

Display Phase Banner "YOLO Cleanup Complete" with ✓/○ per step. Then:
```
➜ Final Step
  /plugin uninstall yolo@yolo-marketplace
  Then optionally: /plugin marketplace remove yolo-marketplace
```
**Do NOT run plugin uninstall yourself** — it would remove itself mid-execution.

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/yolo-brand-essentials.toon — Phase Banner (double-line box), ✓ completed, ○ skipped, Next Up, no ANSI.
