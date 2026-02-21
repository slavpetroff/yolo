---
phase: 3
plan: 3
title: "Prune CLAUDE.md to under 45 lines"
status: complete
commits:
  - "refactor(03-03): merge YOLO/VBW rules into unified Plugin Rules"
  - "refactor(03-03): replace Project Conventions with config reference"
  - "refactor(03-03): extract plugin isolation rules to reference file"
  - "chore(03-03): final CLAUDE.md cleanup, 41 lines (target: <45)"
---

# Plan 03 Summary: Prune CLAUDE.md to Under 45 Lines

## What Was Built

Reduced CLAUDE.md from 67 lines to 41 lines (39% reduction) while preserving all critical behavioral rules. Merged duplicate YOLO Rules and VBW Rules into a single Plugin Rules section (5 shared rules written once, plugin-specific rules as 1-liner each). Extracted verbose PR review protocol (2 long paragraphs) to `references/pr-review-protocol.md`. Moved 11-line Plugin Isolation + Context Isolation block to `references/plugin-isolation.md` (hooks still enforce). Replaced 10-line Project Conventions section with 2-line pointer to `config/` and `CONVENTIONS.md`.

## Files Modified

| File | Action | Description |
|------|--------|-------------|
| `CLAUDE.md` | Modified | Pruned from 67 to 41 lines; merged rules, replaced verbose sections with references |
| `references/pr-review-protocol.md` | Created | PR overlap check and diff-based review rules (extracted from YOLO Rules) |
| `references/plugin-isolation.md` | Created | File isolation and context isolation rules (extracted from Plugin Isolation) |

## Tasks

### Task 1: Merge YOLO/VBW Rules into unified Plugin Rules
- **Status:** Done
- **Commit:** `refactor(03-03): merge YOLO/VBW rules into unified Plugin Rules`
- **Changes:** Combined 12-line YOLO Rules and 9-line VBW Rules into 10-line Plugin Rules. 5 shared rules appear once. YOLO-specific (commands, no QA/Scout) and VBW-specific (commands) noted inline. PR review rules moved to reference file.

### Task 2: Move Project Conventions to config reference
- **Status:** Done
- **Commit:** `refactor(03-03): replace Project Conventions with config reference`
- **Changes:** Replaced 10-line section with 2-line pointer to `config/` and `CONVENTIONS.md`.

### Task 3: Move Plugin Isolation to hook-enforced reference
- **Status:** Done
- **Commit:** `refactor(03-03): extract plugin isolation rules to reference file`
- **Changes:** Moved 11 lines (file isolation + context isolation) to `references/plugin-isolation.md`. CLAUDE.md now has 1-line pointer.

### Task 4: Final cleanup and verification
- **Status:** Done
- **Commit:** `chore(03-03): final CLAUDE.md cleanup, 41 lines (target: <45)`
- **Changes:** Removed extra blank lines, fixed formatting. Verified 41 lines total.

## Must-Have Verification
- [x] CLAUDE.md under 45 lines (41 lines)
- [x] All critical rules preserved (no behavioral regression)
- [x] Verbose sections moved to appropriate locations (2 new reference files)
- [x] Plugin isolation rules moved to reference (hooks still enforce)
