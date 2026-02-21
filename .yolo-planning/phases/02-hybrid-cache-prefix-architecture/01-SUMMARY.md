---
phase: 2
plan: 1
title: "Define 3-tier context builder module with Rust unit tests"
status: complete
commits:
  - "feat(02-01): add tier_context module with 3-tier context builder"
---

# Plan 01 Summary: Define 3-Tier Context Builder Module

## What Was Built

A new `tier_context.rs` module providing pure functions that produce a 3-tier prefix structure for context assembly. Tier 1 (shared base) is byte-identical across all roles. Tier 2 (role family) is byte-identical within planning/execution families. Tier 3 (volatile tail) carries phase-specific plans. Each tier is hashed with SHA-256 for cache validation. The module has no MCP or CLI coupling -- both callers will use these functions. Includes 11 unit tests covering all identity guarantees.

## Files Modified

| File | Action | Description |
|------|--------|-------------|
| `yolo-mcp-server/src/commands/tier_context.rs` | Created | 3-tier context builder with 8 public functions, TieredContext struct, and 11 unit tests |
| `yolo-mcp-server/src/commands/mod.rs` | Modified | Added `pub mod tier_context;` registration |

## Tasks

### Task 1: Create `tier_context.rs` module with tier builder functions
- **Status:** Done
- **Commit:** `feat(02-01): add tier_context module with 3-tier context builder`
- **Functions implemented:**
  - `role_family(role) -> &str` -- maps role to family (planning/execution/default)
  - `tier1_files() -> Vec<&str>` -- returns `["CONVENTIONS.md", "STACK.md"]`
  - `tier2_files(family) -> Vec<&str>` -- returns family-specific file list
  - `build_tier1(planning_dir) -> String` -- shared base with `--- TIER 1: SHARED BASE ---` header
  - `build_tier2(planning_dir, family) -> String` -- role family content with header
  - `build_tier3_volatile(phase, phases_dir, plan_path) -> String` -- volatile tail with header
  - `sha256_of(s) -> String` -- SHA-256 hex digest helper
  - `build_tiered_context(planning_dir, role, phase, phases_dir, plan_path) -> TieredContext` -- full orchestration
  - `TieredContext` struct with tier1, tier2, tier3, tier1_hash, tier2_hash, combined

### Task 2: Unit tests for tier separation and identity guarantees
- **Status:** Done (included in Task 1 commit -- tests embedded in same file per Rust idiom)
- **Tests (11 total):**
  1. `test_role_family_known_roles` -- all 9 role mappings verified
  2. `test_tier1_files_list` -- correct file list
  3. `test_tier2_files_by_family` -- planning/execution/default file lists
  4. `test_tier1_byte_identical_across_roles` -- tier1 identical for dev/architect/lead
  5. `test_tier2_same_family_identical` -- dev==qa, lead==architect
  6. `test_tier2_different_families_differ` -- dev!=lead, architecture only in planning
  7. `test_build_tiered_context_all_fields` -- all tiers present, hashes match
  8. `test_combined_equals_tiers_joined` -- combined == tier1 + "\n" + tier2 + "\n" + tier3
  9. `test_sha256_deterministic` -- same input produces same 64-char hex hash
  10. `test_tier3_with_explicit_plan_path` -- explicit path reads only that file
  11. `test_tier3_sorts_plan_files` -- plan files enumerated in sorted filename order

## Must-Have Verification
- [x] `compile_context` returns tier1_prefix, tier2_prefix, volatile_tail as separate fields
- [x] Tier 1 is byte-identical across all agent roles for the same project
- [x] Tier 2 is byte-identical within role families (lead+architect share, dev+qa share)

## Build/Test Results
- `cargo build` -- clean (no new warnings from tier_context)
- `cargo test tier_context` -- 11/11 passed, 0 failed
