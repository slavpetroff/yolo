---
phase: 1
plan: 04
title: "Update command .md files to call Rust CLI instead of bash scripts"
status: complete
---

## What Was Built

Updated all command and reference files to call Rust CLI subcommands (`yolo resolve-model`, `yolo resolve-turns`, `yolo planning-git`, `yolo bootstrap`) instead of bash scripts (`resolve-agent-model.sh`, `resolve-agent-max-turns.sh`, `planning-git.sh`, `bootstrap-*.sh`). Verified zero remaining bash script references across commands/ and references/. Build passes with 0 errors.

## Tasks

| # | Task | Commit |
|---|------|--------|
| 1 | Update vibe.md to use Rust CLI commands | `2d0f984` |
| 2 | Update init.md to use Rust CLI commands | `1c79de8` |
| 3 | Update config.md to use Rust CLI commands | `45c3c7b` |
| 4 | Update fix.md, debug.md, map.md, execute-protocol.md | `77b9b63` |
| 5 | Verify zero remaining bash script references | (verification only, no commit) |

## Files Modified

- `commands/vibe.md` (8 replacements: bootstrap, resolve-model, resolve-turns, planning-git)
- `commands/init.md` (7 replacements + 6 HTML comment updates)
- `commands/config.md` (14 replacements: resolve-model, planning-git sync-ignore)
- `commands/fix.md` (2 replacements: resolve-model dev, resolve-turns dev)
- `commands/debug.md` (4 replacements: resolve-model debugger, resolve-turns debugger)
- `commands/map.md` (1 replacement: resolve-turns scout)
- `references/execute-protocol.md` (3 replacements: resolve-model dev, resolve-turns dev, planning-git)

## Verification

- `grep -r` across commands/ and references/execute-protocol.md: zero matches for any of the 7 migrated bash scripts
- `cargo build --release`: 0 errors, 19 warnings (all pre-existing)

## Deviations

- Task 3 (config.md) was auto-applied by the linter/formatter before manual editing. Verified changes were correct and committed as-is.
- Task 5 is verification-only with no code changes, so no separate commit was created.
