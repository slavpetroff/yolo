---
name: whats-new
disable-model-invocation: true
description: View changelog and recent updates since your installed version.
argument-hint: "[version]"
allowed-tools: Read, Glob
---

# YOLO What's New $ARGUMENTS

## Guard

1. **Missing changelog:** `${CLAUDE_PLUGIN_ROOT}/CHANGELOG.md` missing → STOP: "No CHANGELOG.md found."

## Steps

1. Read `${CLAUDE_PLUGIN_ROOT}/VERSION` for current_version.
2. Read `${CLAUDE_PLUGIN_ROOT}/CHANGELOG.md`, split by `## [` headings.
   - With version arg: show entries newer than that version.
   - No args: show current version's entry.
3. Display Phase Banner "YOLO Changelog" with version context, entries, Next Up (/yolo:help). No entries: "✓ No changelog entry found for v{version}."

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/yolo-brand-essentials.md — double-line box, ✓ up-to-date, Next Up, no ANSI.
