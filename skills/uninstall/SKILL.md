---
description: Cleanly remove VBW from Claude Code — statusline, settings, then plugin.
allowed-tools: Read, Write, Edit, Bash
---

# VBW Uninstall

## Context

Settings file:
```
!`cat ~/.claude/settings.json 2>/dev/null || echo "{}"`
```

## Steps

### Step 1: Confirm intent

Display:
```
╔══════════════════════════════════════════╗
║  VBW Uninstall                           ║
╚══════════════════════════════════════════╝

This will remove VBW from Claude Code:
  - Statusline configuration
  - Agent Teams setting (optional)
  - Plugin cache and registration

Your project files (.vbw-planning/, CLAUDE.md) are NOT touched.
```

Ask the user to confirm they want to proceed.

### Step 2: Clean statusLine from settings.json

Read `~/.claude/settings.json`. Check if the `statusLine` field exists and its `command` value (or string value) contains `vbw-statusline`.

If it does:
1. Remove the entire `statusLine` key from the JSON
2. Write the file back
3. Display "✓ Statusline removed"

If it doesn't contain `vbw-statusline`: display "○ Statusline is not VBW's — kept"

If `statusLine` doesn't exist: skip silently.

### Step 3: Clean Agent Teams env var

Check if `env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` exists in `~/.claude/settings.json`.

If it does, ask:
```
○ Agent Teams is enabled. VBW set this but other tools may use it.
  Remove it?
```

If user approves: remove `env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` from settings. If the `env` object is then empty, remove the `env` key entirely. Display "✓ Agent Teams setting removed"

If user declines: display "○ Agent Teams setting kept"

### Step 4: Summary and final command

Display:
```
╔══════════════════════════════════════════╗
║  VBW Cleanup Complete                    ║
╚══════════════════════════════════════════╝

  {✓ or ○ for each step above}

➜ Final Step
  /plugin uninstall vbw@vbw-marketplace

  Optionally remove the marketplace too:
  /plugin marketplace remove vbw-marketplace
```

**IMPORTANT:** Do NOT run the plugin uninstall command yourself. The user must run it manually — `/vbw:uninstall` is part of the plugin and would remove itself mid-execution.

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand.md:
- Phase Banner (double-line box) for header and completion
- ✓ for completed steps, ○ for skipped
- Next Up Block for the final uninstall command
- No ANSI color codes
