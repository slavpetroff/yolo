---
description: Update VBW to the latest version.
argument-hint: "[--check]"
allowed-tools: Read, Bash, Glob
---

# VBW Update $ARGUMENTS

## Context

Current version:
```
!`cat ${CLAUDE_PLUGIN_ROOT}/VERSION 2>/dev/null || echo "unknown"`
```

## Steps

### Step 1: Read current version

Read `${CLAUDE_PLUGIN_ROOT}/VERSION` using the Read tool. Store the version string as `old_version`.

### Step 2: Handle --check flag

If `$ARGUMENTS` contains "--check", only report the current version and advise how to update. Do NOT attempt to update.

Display:

```
╔═══════════════════════════════════════════╗
║  VBW Version Check                        ║
╚═══════════════════════════════════════════╝

  Current version: {old_version}

  To update VBW, use the Claude Code plugin manager:
    claude plugin update vbw
```

Then show Next Up block and STOP. Do not continue to Step 3.

### Step 3: Attempt update

Since VBW is distributed as a Claude Code plugin (not npm), the update mechanism is the Claude Code plugin manager.

Run via Bash tool:
```
claude plugin update vbw
```

If this command succeeds, proceed to Step 4.

If this command is not available or fails (exit code non-zero, "command not found", or similar), fall back to manual instructions:

```
⚠ Automatic update not available

  The Claude Code plugin manager could not complete the update.

  To update manually:
  1. Visit the VBW repository
  2. Pull the latest version
  3. Re-install the plugin with: claude plugin install
```

Then show Next Up block and STOP. Do not continue to Step 4.

### Step 4: Verify update

After a successful update attempt, read `${CLAUDE_PLUGIN_ROOT}/VERSION` again using the Read tool to get `new_version`.

### Step 5: Display result

**If version changed (new_version differs from old_version):**

```
╔═══════════════════════════════════════════╗
║  VBW Updated                              ║
╚═══════════════════════════════════════════╝

✓ Updated: {old_version} -> {new_version}
```

Then suggest `/vbw:whats-new {old_version}` to see what changed.

**If version unchanged (new_version equals old_version):**

```
╔═══════════════════════════════════════════╗
║  VBW Update                               ║
╚═══════════════════════════════════════════╝

✓ VBW is already up to date ({new_version}).
```

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand.md for all visual formatting:
- Double-line box for the update header banner
- ✓ for success confirmation (update completed or already up to date)
- ⚠ for fallback warning (automatic update not available)
- Next Up Block:
  - After update success: `/vbw:whats-new {old_version} -- See what changed`
  - After already up to date: `/vbw:help -- View all available commands`
  - After fallback: `/vbw:help -- View all available commands`
- No ANSI color codes
