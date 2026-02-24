---
phase: 01
plan: 03
title: "Simplify archive.md to delegate version bumps to CLI"
wave: 1
depends_on: []
must_haves:
  - "archive.md version bump section delegates to yolo bump-version with --major/--minor flags"
  - "No inline bash arithmetic for version computation in archive.md"
---

# Plan 03: Simplify archive.md version bump delegation

**Files modified:** `skills/vibe-modes/archive.md`

The archive skill currently has inline bash for computing major/minor version bumps (lines 58-73). Once the CLI supports --major/--minor flags (Plan 04), all version logic should delegate to the CLI. This plan updates the instructions now, using the flags that Plan 04 will implement.

## Task 1: Replace inline version arithmetic with CLI delegation

**Files:** `skills/vibe-modes/archive.md`

**What to do:**
1. In `skills/vibe-modes/archive.md`, replace the version bump section (lines 56-74, the `if/elif/else` block) with a unified CLI call:
   ```bash
   # Forward --major or --minor if passed, otherwise default patch bump
   if [ "$BUMP_TYPE" = "major" ]; then
     "$HOME/.cargo/bin/yolo" bump-version --major
   elif [ "$BUMP_TYPE" = "minor" ]; then
     "$HOME/.cargo/bin/yolo" bump-version --minor
   else
     "$HOME/.cargo/bin/yolo" bump-version
   fi
   ```
2. Keep the `NEW_VERSION=$(cat VERSION)` line after the block (line 74) unchanged.
3. Verify the rest of the archive.md flow is unaffected.

## Task 2: Update release commit git add to remove .claude-plugin/marketplace.json

**Files:** `skills/vibe-modes/archive.md`

**What to do:**
1. On line 84, the `git add` command includes `.claude-plugin/marketplace.json`. Remove it since that file will be deleted (Plan 02). The line should become:
   ```bash
   git add VERSION .claude-plugin/plugin.json marketplace.json
   ```
2. Keep all other lines in the release commit section unchanged.

**Commit:** `refactor(archive): delegate version bumps to CLI and remove deleted file ref`
