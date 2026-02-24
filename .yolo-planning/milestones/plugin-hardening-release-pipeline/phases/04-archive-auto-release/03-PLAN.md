---
phase: "04"
plan: "03"
title: "archive skill release step update"
wave: 2
depends_on: ["04-02"]
must_haves:
  - "Archive skill Step 8b documents the gh release step from release-suite"
  - "Display output includes release URL when available"
  - "Archive step 11 presentation includes release status"
---

# Plan 03: archive skill release step update

Update the archive skill instructions to document the new GitHub Release behavior from release-suite.

## Task 1

**Files:** `skills/vibe-modes/archive.md` (at plugin root)

**What to do:**

1. In Step 8b "Consolidated release", after the existing parse results section, add documentation for the gh-release step:

   After the existing `delta.steps[]` description, add:
   > - gh-release: `✓ GitHub release created: {url}` or `⚠ gh CLI not found (manual release needed)` or `○ Release skipped (--no-push)`

2. In step 11 (Present), add release URL to the metrics display:
   > If `delta.steps` contains a gh-release step with status "ok", display the release URL in the Phase Banner.

## Task 2

**Files:** `skills/vibe-modes/archive.md` (at plugin root)

**What to do:**

1. Review the full archive.md to confirm the release-suite integration is consistent end-to-end.
2. Verify that `--no-release` flag documentation still makes sense with the new gh-release step (it should — `--no-release` skips the entire release-suite call, which includes gh-release).

**Commit:** `docs(04-03): update archive skill with gh release documentation`
