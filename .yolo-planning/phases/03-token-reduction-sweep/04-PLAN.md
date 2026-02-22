---
phase: 3
plan: 4
title: "Remove dead redirects and compress handoff schemas"
wave: 1
depends_on: []
must_haves:
  - 3 dead redirect files deleted (references/execute-protocol.md, references/discussion-engine.md, references/verification-protocol.md)
  - All @-references to deleted files updated to point to their skill locations
  - references/handoff-schemas.md reduced by removing redundant envelope repetition from JSON examples
  - Handoff schemas file reduced from 262 lines to ~120 lines
  - All existing tests pass
---

# Plan 04: Remove Dead Redirects and Compress Handoff Schemas

## Context

### Dead Redirects (3 files, 565 bytes)

Three files in `references/` are pure redirect stubs that point to skill locations:
- `references/execute-protocol.md` (194 bytes) → `skills/execute-protocol/SKILL.md`
- `references/discussion-engine.md` (177 bytes) → `skills/discussion-engine/SKILL.md`
- `references/verification-protocol.md` (194 bytes) → `skills/verification-protocol/SKILL.md`

These serve no purpose. Any code loading `references/execute-protocol.md` gets a redirect message instead of useful content. The actual content lives in skills/. The redirects waste context tokens whenever an @-reference or compile-context loads them.

### Handoff Schemas Redundancy (8.4KB, 262 lines)

`references/handoff-schemas.md` defines 8 message types. Each JSON example includes the full 9-field envelope (`id`, `type`, `phase`, `task`, `author_role`, `timestamp`, `schema_version`, `confidence`, `payload`). The envelope is defined once at the top, then repeated identically in every example. This means 8 copies of the same 9-field envelope structure.

**Token impact**:
- Dead redirects: ~140 tokens wasted per compile-context that loads them
- Handoff schemas: ~2,800 tokens → ~1,200 tokens (reduce by ~1,600 tokens). This file is loaded by every Dev agent via `Schema ref:` in execute-protocol.

## Tasks

### Task 1: Delete dead redirect files

**Files:** `references/execute-protocol.md`, `references/discussion-engine.md`, `references/verification-protocol.md`

Delete all three redirect files.

### Task 2: Update @-references to deleted files

**Files:** Any file in repo that references the deleted redirect filenames

Search for `references/execute-protocol.md`, `references/discussion-engine.md`, `references/verification-protocol.md` across the codebase. Update references to point directly to their skill locations:
- `references/execute-protocol.md` → `skills/execute-protocol/SKILL.md`
- `references/discussion-engine.md` → `skills/discussion-engine/SKILL.md`
- `references/verification-protocol.md` → `skills/verification-protocol/SKILL.md`

### Task 3: Compress handoff-schemas.md

**Files:** `references/handoff-schemas.md`

Restructure the file:
1. Keep the envelope definition and Role Authorization Matrix as-is (lines 1-34)
2. For each of the 8 message types, show ONLY the `payload` object (not the full envelope wrapper). Add a one-line note at the top of the examples section: "All examples below show only the `payload` field. Wrap in the envelope above before sending."
3. Remove the Backward Compatibility section at the bottom (lines 252-263) — it describes V1 fallback behavior that adds 12 lines but is only relevant when `v2_typed_protocol=false` (a config-gated feature that could move to V3-EXTENSIONS if needed).
4. Condense `shutdown_request` and `shutdown_response` examples (currently 40+ lines) into compact payload-only format.

Target: ~120 lines (from 262).

### Task 4: Run tests and verify

**Files:** (read-only verification)

Run the full test suite. Check for any tests that validate handoff schema format, redirect file existence, or @-reference resolution.
