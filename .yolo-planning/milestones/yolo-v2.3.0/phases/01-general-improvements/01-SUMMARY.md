---
phase: 01
plan: 01
title: "Fix wrong subcommand names in command markdowns"
status: complete
tasks_completed: 4
commits: 4
deviations: []
---

## What Was Built

Fixed 4 mismatched CLI subcommand names in command markdown files to match the actual router entries:

1. **init.md**: Renamed `infer-gsd-summary` to `gsd-summary` (2 occurrences -- lines 369, 399)
2. **todo.md**: Renamed `persist-state-after-ship` to `persist-state` (1 occurrence -- line 26)
3. **vibe.md**: Renamed `compile-rolling-summary` to `rolling-summary` (1 occurrence -- line 377)
4. **vibe.md**: Renamed `persist-state-after-ship` to `persist-state` (1 occurrence -- line 385)

All acceptance criteria verified via grep: zero occurrences of old names, correct occurrences of new names.

## Files Modified

- `commands/init.md` -- `infer-gsd-summary` -> `gsd-summary` (2 replacements)
- `commands/todo.md` -- `persist-state-after-ship` -> `persist-state` (1 replacement)
- `commands/vibe.md` -- `compile-rolling-summary` -> `rolling-summary`, `persist-state-after-ship` -> `persist-state` (2 replacements)
