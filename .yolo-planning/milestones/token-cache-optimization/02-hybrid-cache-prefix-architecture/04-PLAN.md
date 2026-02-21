---
phase: 2
plan: 4
title: "Integrate 3-tier builder into CLI compile-context and add bats tests"
wave: 2
depends_on: [1]
must_haves:
  - "compile_context returns tier1_prefix, tier2_prefix, volatile_tail as separate fields"
  - "Tier 1 is byte-identical across all agent roles for the same project"
  - "Tier 2 is byte-identical within role families (lead+architect share, dev+qa share)"
  - "Existing tests pass + new tests for tier separation and cross-agent prefix identity"
  - "Measured cache hit rate improvement vs baseline (Phase 1 dashboard)"
---

# Plan 4: Integrate 3-Tier Builder into CLI compile-context + Bats Tests

## Goal
Refactor the CLI `compile-context` command in `router.rs` to use the `tier_context` module from Plan 01. Update the output `.context-{role}.md` file format to use 3-tier headers. Add bats integration tests verifying tier identity guarantees and cache key behavior. Wire the token economics report to measure tier-level cache hit improvement.

## Design

### CLI Output Format (after)
The `.context-{role}.md` file will contain:
```
--- TIER 1: SHARED BASE ---

# .yolo-planning/codebase/CONVENTIONS.md
<content>

# .yolo-planning/codebase/STACK.md
<content>

--- TIER 2: ROLE FAMILY (planning) ---

# .yolo-planning/codebase/ARCHITECTURE.md
<content>
...

--- TIER 3: VOLATILE TAIL (phase=2) ---

# Plan: 01-PLAN.md
<content>
...

--- END COMPILED CONTEXT ---
```

### Cache Key Update
The `cache-context` CLI command (`cache_context.rs`) currently hashes `phase:role:plan:flags:changed:codebase:rolling`. With 3 tiers, cache keys should also incorporate role family so that same-family roles can share cache entries. However, to avoid scope creep, this plan only updates the compile-context output format. Cache key optimization is a future enhancement.

## Tasks

### Task 1: Refactor CLI compile-context to use tier builder
**Files to modify:**
- `yolo-mcp-server/src/cli/router.rs` (the `"compile-context"` match arm, lines 359-429)

**What to implement:**
1. Add `use crate::commands::tier_context;` import (if not already present from Plan 01's mod.rs registration)
2. Replace the inline file-reading logic with:
   ```rust
   let planning_dir = PathBuf::from(".yolo-planning");
   let phases_dir_path = std::path::Path::new(&args[4]);
   let plan_path_opt = args.get(5).map(|s| std::path::Path::new(s.as_str()));
   let phase_i64 = phase.parse::<i64>().unwrap_or(0);
   let ctx = tier_context::build_tiered_context(
       &planning_dir, role, phase_i64, Some(phases_dir_path), plan_path_opt
   );
   ```
3. Build the output context as `ctx.combined` (tier1 + tier2 + tier3)
4. The current CLI also reads plan files from `phases_dir` — this is now handled by `build_tier3_volatile` in the tier builder. Remove the duplicate plan-reading logic.
5. Preserve: write to `.context-{role}.md` in phases_dir, fall back to stdout if write fails
6. The CLI does NOT include git diff (unlike the MCP tool). If the current CLI includes git diff, remove it — the CLI is called before agents start, so there's no meaningful diff to include.

**Implementation notes:**
- The current CLI reads ALL 5 files for every role (no role filtering). The tier builder fixes this: tier1 gets shared files, tier2 gets family-specific files.
- Preserve the `STABLE_PREFIX_END` sentinel? No — replace it with tier headers. The sentinel was only used internally and is not consumed by any downstream parser.

### Task 2: Add bats integration tests for 3-tier compile-context
**Files to create:**
- `tests/tier-cache.bats`

**What to implement:**
- `setup()`: Create temp dir with `.yolo-planning/codebase/` containing ARCHITECTURE.md, STACK.md, CONVENTIONS.md, ROADMAP.md, REQUIREMENTS.md. Create phases dir with a sample plan file.
- Test: "compile-context output contains TIER 1 header" — run `yolo compile-context 1 dev {phases_dir}`, verify output file contains `--- TIER 1: SHARED BASE ---`
- Test: "compile-context output contains TIER 2 header with family" — run for role=dev, verify `--- TIER 2: ROLE FAMILY (execution) ---`. Run for role=lead, verify `--- TIER 2: ROLE FAMILY (planning) ---`.
- Test: "tier 1 is byte-identical across dev and architect" — run for dev and architect, extract tier 1 section (between TIER 1 header and TIER 2 header), compare with `diff`. Must be identical.
- Test: "tier 2 is byte-identical for dev and qa (same family)" — run for dev and qa, extract tier 2 section, compare. Must be identical.
- Test: "tier 2 differs between dev and lead (different families)" — run for dev and lead, extract tier 2 sections, verify they differ.
- Test: "tier 3 contains phase plan content" — run with phase=1 and a plan file, verify tier 3 section contains plan content.
- Test: "compile-context writes output file" — verify `.context-{role}.md` file is created in phases_dir.

**Helper functions (add to test_helper.bash or inline):**
```bash
# Extract tier section from compiled context
# Usage: extract_tier <file> <tier_header_pattern>
extract_tier() {
  local file="$1" pattern="$2"
  sed -n "/$pattern/,/^--- TIER [0-9]\|^--- END COMPILED/{ /$pattern/d; /^--- TIER [0-9]\|^--- END COMPILED/d; p; }" "$file"
}
```

### Task 3: Update token-economics bats tests with tier awareness
**Files to modify:**
- `tests/token-economics.bats`

**What to change:**
- Add 1 new test: "report-tokens: shows tier-level cache hit rates when tier data available" — seed metrics events that include `tier1_cache_hit=true` and `tier2_cache_hit=true` fields, verify the report output includes tier-level information. (This is forward-looking — the metrics events don't emit tier data yet, but the test verifies the report handles extra fields gracefully.)
- This is a lightweight addition; the main Phase 1 dashboard already works. The test just verifies no regressions.

**Test expectations:**
- 7 new bats tests in `tests/tier-cache.bats`
- 1 updated test in `tests/token-economics.bats`
- All existing bats tests continue to pass
- `cargo test` passes (Plan 03 handles Rust test updates)
