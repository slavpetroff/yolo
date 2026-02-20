---
phase: 1
plan: 04
title: "Update command .md files to call Rust CLI instead of bash scripts"
status: complete
---

## What Was Built

Updated all command .md files and references/execute-protocol.md to call Rust CLI subcommands instead of the 7 migrated bash scripts. Zero remaining bash script references for: resolve-agent-model.sh, resolve-agent-max-turns.sh, planning-git.sh, bootstrap-project.sh, bootstrap-requirements.sh, bootstrap-roadmap.sh, bootstrap-state.sh.

## Tasks

| # | Title | Commit |
|---|-------|--------|
| 1 | Update vibe.md to use Rust CLI commands | 2d0f984 |
| 2 | Update init.md to use Rust CLI commands | 1c79de8 |
| 3 | Update config.md to use Rust CLI commands | 45c3c7b |
| 4 | Update fix.md, debug.md, map.md, execute-protocol.md | 77b9b63 |
| 5 | Verify zero remaining bash script references | (verified, no code changes) |

## Files Modified

- `commands/vibe.md` (7 replacements)
- `commands/init.md` (7 replacements + HTML comment updates)
- `commands/config.md` (13 resolve-model + 1 planning-git)
- `commands/fix.md` (2 replacements)
- `commands/debug.md` (4 replacements)
- `commands/map.md` (1 replacement)
- `references/execute-protocol.md` (4 replacements)

## Test Results

- grep verification: zero remaining references to any of the 7 migrated scripts in commands/ and references/
- cargo build: succeeds

## Deviations

- Tasks 1 and 2 (vibe.md and init.md) were completed and committed by a parallel agent before this agent started. Commits 2d0f984 and 1c79de8 are attributed to that agent.
