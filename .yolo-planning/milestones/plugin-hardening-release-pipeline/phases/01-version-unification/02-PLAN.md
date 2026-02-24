---
phase: 01
plan: 02
title: "Delete duplicate .claude-plugin/marketplace.json"
wave: 1
depends_on: []
must_haves:
  - ".claude-plugin/marketplace.json deleted from repo"
  - "Root marketplace.json confirmed as canonical"
---

# Plan 02: Delete duplicate marketplace.json

**Files modified:** `.claude-plugin/marketplace.json` (deleted)

The root `marketplace.json` and `.claude-plugin/marketplace.json` are identical duplicates. The root copy is canonical. This plan removes the duplicate.

## Task 1: Delete .claude-plugin/marketplace.json

**Files:** `.claude-plugin/marketplace.json`

**What to do:**
1. Delete the file `.claude-plugin/marketplace.json` from the repository.
2. Verify `marketplace.json` (root) still exists and contains the correct version `2.9.5`.
3. Run `git rm .claude-plugin/marketplace.json` to stage the deletion.

**Commit:** `chore(cleanup): delete duplicate .claude-plugin/marketplace.json`
