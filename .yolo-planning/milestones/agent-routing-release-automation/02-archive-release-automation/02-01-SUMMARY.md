---
phase: "02"
plan: "01"
title: "Add consolidated release step to archive flow"
status: complete
tasks_completed: 3
tasks_total: 3
commit_hashes:
  - "2db5907"
  - "83f6424"
files_modified:
  - "skills/vibe-modes/archive.md"
---

## What Was Built

Added a consolidated release automation step to the archive flow so that on milestone completion, version is automatically bumped, changelog finalized, release committed, tagged, and optionally pushed -- eliminating the need for a separate manual release phase.

Three changes were made to `skills/vibe-modes/archive.md`:

1. **Release flags** (Task 1): Extended Step 2 args parsing with `--no-release`, `--major`, and `--minor` flags to control release behavior during archive.

2. **Step 8b consolidated release** (Task 2): Inserted a new step between the milestone Git tag (Step 8) and the ACTIVE update (Step 9) that:
   - Skips if `--no-release` flag was passed
   - Reads `auto_push` config from `.yolo-planning/config.json`
   - Bumps version via `yolo bump-version` (patch default), with `--major`/`--minor` forwarding for manual override
   - Finalizes CHANGELOG.md `[Unreleased]` section with version and date
   - Creates release commit: `chore: release v{version}`
   - Tags with `v{version}`
   - Pushes only when `auto_push` is `always` or `after_phase`

3. **Regression verification** (Task 3): Confirmed all key patterns present (`--no-release`, `bump-version`, `chore: release`, `v${NEW_VERSION}`) and all 711 bats tests pass with no new failures.

## Files Modified

| File | Change |
|------|--------|
| `skills/vibe-modes/archive.md` | Added 3 release flags to Step 2 args; inserted Step 8b consolidated release (58 lines) |

## Deviations

None.
