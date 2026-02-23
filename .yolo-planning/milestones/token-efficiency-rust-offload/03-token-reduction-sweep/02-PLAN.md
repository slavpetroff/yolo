---
phase: 3
plan: 2
title: "Consolidate effort profiles into single structured reference"
wave: 1
depends_on: []
must_haves:
  - 4 effort profile MDs (effort-profile-fast.md, effort-profile-balanced.md, effort-profile-thorough.md, effort-profile-turbo.md) consolidated into 1 file references/effort-profiles.md
  - Shared preamble ("Effort vs Model Profile" block) appears exactly once
  - All 4 profile matrices, plan approval tables, and effort parameter mappings preserved
  - Old 4 files deleted (not redirected)
  - All @-references updated (agents, commands, other references that point to old files)
  - All existing tests pass
---

# Plan 02: Consolidate Effort Profiles

## Context

There are 4 separate effort profile files in `references/` totaling 8.6KB / 180 lines:
- `effort-profile-balanced.md` (2,194 bytes, 45 lines)
- `effort-profile-fast.md` (2,061 bytes, 43 lines)
- `effort-profile-thorough.md` (2,347 bytes, 47 lines)
- `effort-profile-turbo.md` (2,024 bytes, 45 lines)

Each file repeats an identical 12-line "Effort vs Model Profile" explanatory block (explaining that effort and model profile are independent settings, how to configure them, and a reference to model-profiles.md). This block appears 4 times = 48 lines of pure duplication.

**Token impact**: Consolidating to 1 file saves ~48 lines of duplicated preamble + 4 sets of file headers/frontmatter = ~60 lines / ~1,200 tokens. Additionally, any compile-context that loads multiple profiles loads the duplication multiple times.

## Tasks

### Task 1: Create consolidated references/effort-profiles.md

**Files:** `references/effort-profiles.md` (new)

Create a single file containing:
1. Title and shared preamble (the "Effort vs Model Profile" explanation) — ONCE
2. Four sections (## Thorough, ## Balanced, ## Fast, ## Turbo) each containing:
   - Profile ID, recommended model profile, use-when guidance (one-liner)
   - Agent matrix table
   - Plan approval table
   - Effort parameter mapping table
   - Per-invocation override note

Target: ~100 lines total (vs 180 across 4 files).

### Task 2: Delete old effort profile files

**Files:** `references/effort-profile-balanced.md`, `references/effort-profile-fast.md`, `references/effort-profile-thorough.md`, `references/effort-profile-turbo.md`

Delete all 4 individual files. No redirects needed — the consolidated file replaces them.

### Task 3: Update all @-references to effort profiles

**Files:** Any file referencing `effort-profile-balanced.md`, `effort-profile-fast.md`, `effort-profile-thorough.md`, or `effort-profile-turbo.md`

Search the entire repo for references to the old filenames. Update them to point to `references/effort-profiles.md` (with section anchors where appropriate, e.g., `references/effort-profiles.md#balanced`).

Known references to check:
- `references/model-profiles.md` line 127 references `effort-profile-balanced.md`
- `skills/execute-protocol/SKILL.md` may reference effort profiles
- `commands/` directory may have references

### Task 4: Run tests and verify

**Files:** (read-only verification)

Run the full test suite. Confirm all tests pass. If any tests reference the old filenames, update them.
