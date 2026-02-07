---
description: View changelog and recent updates since your installed version.
argument-hint: "[version]"
allowed-tools: Read, Glob
---

# VBW What's New $ARGUMENTS

## Context

Current version:
```
!`cat ${CLAUDE_PLUGIN_ROOT}/VERSION 2>/dev/null || echo "unknown"`
```

## Guard

1. **Missing changelog:** If ${CLAUDE_PLUGIN_ROOT}/CHANGELOG.md does not exist (check via Read tool), STOP: "No CHANGELOG.md found. Cannot display version history."

## Steps

### Step 1: Read current version

Read `${CLAUDE_PLUGIN_ROOT}/VERSION` using the Read tool. Store the version string as `current_version`. This is the installed version.

### Step 2: Determine baseline version

If `$ARGUMENTS` contains a version string (e.g., "0.5.0"), use that as the `baseline_version` for comparison. This lets users check "what changed since version X."

If `$ARGUMENTS` is empty or does not contain a version string, use `current_version` as the `baseline_version`. In this case, the user wants to see if there are updates beyond their current version.

### Step 3: Read changelog

Read `${CLAUDE_PLUGIN_ROOT}/CHANGELOG.md` using the Read tool. Store the full contents.

### Step 4: Parse changelog sections

The changelog follows Keep a Changelog format. Each version section starts with `## [X.Y.Z]`.

Versions in CHANGELOG.md are in reverse chronological order (newest first).

Parse strategy:
1. Split the changelog into sections by `## [` headings.
2. For each section, extract the version number from the heading.
3. Collect all sections where the version is newer than `baseline_version`.
4. Use simple string comparison -- read from the top of the file and stop collecting when you reach a version that equals or is older than the baseline.

If `$ARGUMENTS` contained a version string:
- Show all changelog entries newer than that version.

If `$ARGUMENTS` was empty (baseline equals current):
- If no entries are newer than current, the user is on the latest version.
- If there ARE entries newer than current (unlikely in local context, but possible if VERSION was not updated), show them.

### Step 5: Display results

**If new entries exist (versions newer than baseline):**

Display using brand formatting with a double-line box header:

```
╔═══════════════════════════════════════════╗
║  VBW Changelog                            ║
║  Since {baseline_version}                 ║
╚═══════════════════════════════════════════╝

## [{version}] - {date}

### {section}

- {entry}
- {entry}

## [{version}] - {date}

### {section}

- {entry}
```

After the entries, show a Next Up block.

**If no new entries (baseline is current or newer):**

```
╔═══════════════════════════════════════════╗
║  VBW Changelog                            ║
╚═══════════════════════════════════════════╝

✓ You are on the latest version ({current_version}).

  No new changes since {baseline_version}.
```

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand.md for all visual formatting:
- Double-line box for the changelog header banner
- ✓ for "up to date" confirmation
- Next Up Block:
  - If not on latest: `/vbw:update -- Update to the latest version`
  - If on latest: `/vbw:help -- View all available commands`
- No ANSI color codes
