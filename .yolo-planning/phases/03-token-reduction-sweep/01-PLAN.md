---
phase: 3
plan: 1
title: "Extract V3 experimental blocks from execute-protocol"
wave: 1
depends_on: []
must_haves:
  - V3 conditional blocks (Smart Routing, Monorepo Routing, Validation Gates, Event Log, Snapshot Resume, Metrics, Contract-Lite, Lock-Lite, Lease Locks, Rolling Summary, Event Recovery) extracted to skills/execute-protocol/V3-EXTENSIONS.md
  - SKILL.md loads V3-EXTENSIONS.md only when any v3_* config flag is true, via a single conditional include marker
  - SKILL.md reduced by ~200 lines (from 553 to ~350)
  - All existing tests pass (no behavioral regression)
  - yolo report-tokens shows size reduction for execute-protocol skill
---

# Plan 01: Extract V3 Experimental Blocks from Execute Protocol

## Context

`skills/execute-protocol/SKILL.md` is 553 lines / 36.3KB. It contains ~200 lines of V3 conditional blocks that only activate when `v3_*` config flags are true. All V3 flags default to `false` in `config/defaults.json`. These blocks are loaded into every Dev agent context on every `/yolo:vibe` execution but contribute zero behavioral value unless explicitly enabled.

**Token impact**: ~200 lines * ~20 tokens/line = ~4,000 tokens saved per Dev agent spawn (currently wasted on every standard workflow cycle).

## Tasks

### Task 1: Extract V3 blocks to V3-EXTENSIONS.md

**Files:** `skills/execute-protocol/SKILL.md`, `skills/execute-protocol/V3-EXTENSIONS.md` (new)

Extract all V3 conditional blocks (identified by `**V3 ` prefix pattern) from SKILL.md into a new `skills/execute-protocol/V3-EXTENSIONS.md`. Preserve exact content and ordering. In SKILL.md, replace each extracted block with a single-line placeholder: `<!-- v3: {feature-name} — see V3-EXTENSIONS.md when v3_* flags enabled -->`.

The V3 blocks to extract (by line range in current SKILL.md):
- V3 Event Recovery (REQ-17) — lines 19-21
- V3 Snapshot Resume (REQ-18) — lines 48-51
- V3 Schema Validation (REQ-17) — lines 53-58
- V3 Smart Routing (REQ-15) — lines 92-105
- V3 Monorepo Routing (REQ-17) — lines 115-121
- V3 Validation Gates (REQ-13, REQ-14) — lines 243-255
- V3 Event Log plan lifecycle (REQ-16) — lines 301-327
- V3 Snapshot per-plan checkpoint (REQ-18) — lines 328-332
- V3 Metrics instrumentation (REQ-09) — lines 334-339
- V3 Contract-Lite (REQ-10) — lines 341-351
- V3 Lock-Lite (REQ-11) — lines 380-388
- V3 Lease Locks (REQ-17) — lines 390-398
- V3 Rolling Summary (REQ-03) — lines 470-482
- V3 Event Log phase end (REQ-16) — lines 484-486
- V2 Full Event Types (REQ-09, REQ-10) — lines 310-326 (depends on v3_event_log)

### Task 2: Add conditional include instruction to SKILL.md

**Files:** `skills/execute-protocol/SKILL.md`

At the top of SKILL.md (after frontmatter), add a conditional loading instruction:

```
**V3 Extensions:** If ANY `v3_*` flag is `true` in `.yolo-planning/config.json`, also read `skills/execute-protocol/V3-EXTENSIONS.md` before executing. Otherwise skip it entirely.
```

### Task 3: Verify no behavioral regression

**Files:** (read-only verification)

Run `yolo report-tokens` to capture baseline. Run full test suite. Confirm all tests pass. Document the byte reduction in SKILL.md (before vs after).
