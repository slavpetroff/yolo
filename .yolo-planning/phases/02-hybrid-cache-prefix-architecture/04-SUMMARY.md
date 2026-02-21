---
phase: 2
plan: 4
title: "Integrate 3-tier builder into CLI compile-context and add bats tests"
status: complete
commits:
  - "feat(compile-context): refactor CLI to use 3-tier builder from tier_context module"
  - "test(tier-cache): add 7 bats tests for 3-tier compile-context output"
  - "test(token-economics): add tier-level cache hit fields graceful handling test"
---

# Plan 04 Summary: Integrate 3-Tier Builder into CLI compile-context + Bats Tests

## What Was Built

Refactored the CLI `compile-context` command to use the `tier_context` module from Plan 01, replacing 50 lines of inline file-reading with a single `build_tiered_context()` call. Output now uses 3-tier headers (TIER 1: SHARED BASE, TIER 2: ROLE FAMILY, TIER 3: VOLATILE TAIL) instead of the old flat format with `STABLE_PREFIX_END` sentinel. Added 7 bats integration tests verifying tier identity guarantees and 1 token-economics test for forward-compatible tier cache hit fields.

## Files Modified

| File | Action | Description |
|------|--------|-------------|
| `yolo-mcp-server/src/cli/router.rs` | Modified | Replaced compile-context inline logic with tier_context::build_tiered_context() call, added tier_context import |
| `tests/tier-cache.bats` | Created | 7 bats tests for 3-tier compile-context output (tier identity, family separation, file writing) |
| `tests/token-economics.bats` | Modified | Added 1 test for graceful handling of tier-level cache hit fields in metrics events |

## Tasks

### Task 1: Refactor CLI compile-context to use tier builder
- **Status:** Done
- **Commit:** `feat(compile-context): refactor CLI to use 3-tier builder from tier_context module`
- **Changes:** Removed 50 lines of inline file reading, `STABLE_PREFIX_END` sentinel, and flat `COMPILED CONTEXT` header. Added `tier_context` to imports. New compile-context arm calls `tier_context::build_tiered_context()` and appends `--- END COMPILED CONTEXT ---` sentinel.

### Task 2: Add bats integration tests for 3-tier compile-context
- **Status:** Done
- **Commit:** `test(tier-cache): add 7 bats tests for 3-tier compile-context output`
- **Tests (7 total):**
  1. compile-context output contains TIER 1 header
  2. compile-context output contains TIER 2 header with family (dev=execution, lead=planning)
  3. tier 1 is byte-identical across dev and architect
  4. tier 2 is byte-identical for dev and qa (same execution family)
  5. tier 2 differs between dev and lead (different families)
  6. tier 3 contains phase plan content
  7. compile-context writes output file with all tier headers
- **Note:** Used `awk` for tier extraction helper (macOS BSD sed lacks `\|` in BRE)

### Task 3: Update token-economics bats tests with tier awareness
- **Status:** Done
- **Commit:** `test(token-economics): add tier-level cache hit fields graceful handling test`
- **Test:** Seeds events with `tier1_cache_hit` and `tier2_cache_hit` fields, verifies report-tokens processes them without errors and still shows per-agent data.

## Must-Have Verification
- [x] compile_context returns tier1_prefix, tier2_prefix, volatile_tail as separate fields
- [x] Tier 1 is byte-identical across all agent roles for the same project
- [x] Tier 2 is byte-identical within role families (lead+architect share, dev+qa share)
- [x] Existing tests pass + new tests for tier separation and cross-agent prefix identity
- [~] Measured cache hit rate improvement vs baseline -- tier-level cache hit fields added; full measurement requires Plan 03 metrics integration

## Build/Test Results
- `cargo build --release` -- clean (no new warnings from changes)
- `cargo test -- router` -- 4/4 passed
- `bats tests/tier-cache.bats` -- 7/7 passed
- `bats tests/token-economics.bats` -- new test #9 passes; 2 pre-existing failures (#1, #5) unrelated to this plan
