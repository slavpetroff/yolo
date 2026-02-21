---
phase: 2
plan: 3
title: "Integrate 3-tier builder into MCP compile_context tool"
wave: 2
depends_on: [1]
must_haves:
  - "compile_context returns tier1_prefix, tier2_prefix, volatile_tail as separate fields"
  - "Tier 1 is byte-identical across all agent roles for the same project"
  - "Tier 2 is byte-identical within role families (lead+architect share, dev+qa share)"
  - "Existing tests pass + new tests for tier separation and cross-agent prefix identity"
---

# Plan 3: Integrate 3-Tier Builder into MCP compile_context Tool

## Goal
Refactor the MCP `compile_context` handler in `tools.rs` to use the `tier_context` module from Plan 01. Return `tier1_prefix`, `tier2_prefix`, and `volatile_tail` as separate JSON fields alongside backward-compatible `content`, `stable_prefix`, and `prefix_hash`. Update all existing Rust unit tests and add new cross-agent identity tests.

## Design

### Response JSON Structure (after)
```json
{
  "content": [{"type": "text", "text": "<combined>"}],
  "tier1_prefix": "<tier 1 content>",
  "tier2_prefix": "<tier 2 content>",
  "volatile_tail": "<tier 3 content>",
  "tier1_hash": "<sha256 of tier1>",
  "tier2_hash": "<sha256 of tier2>",
  "stable_prefix": "<tier1 + tier2 combined for backward compat>",
  "prefix_hash": "<sha256 of stable_prefix>",
  "prefix_bytes": <tier1.len() + tier2.len()>,
  "volatile_bytes": <tier3.len()>,
  "input_tokens_estimate": <total bytes>,
  "cache_read_tokens_estimate": <bytes if cache hit>,
  "cache_write_tokens_estimate": <bytes if cache miss>
}
```

### Backward Compatibility
- `stable_prefix` = tier1 + "\n" + tier2 (preserves existing field)
- `prefix_hash` = sha256 of `stable_prefix` (same as before, but now computed from tiers)
- `content` = combined tier1 + tier2 + tier3 (preserves existing MCP content format)
- `volatile_tail` field name is reused (already existed)
- Cache hit/miss logic uses `prefix_hash` as before (comparing tier1+tier2 combined)

### Git Diff Handling
The MCP tool currently appends git diff to the volatile tail. The `tier_context::build_tier3_volatile` function produces tier 3 WITHOUT git diff (since it's sync-only). The MCP tool appends the async git diff AFTER calling the tier builder:
```rust
let mut ctx = tier_context::build_tiered_context(...);
// Append git diff to tier3 (async operation)
if let Ok(diff) = Command::new("git").arg("diff").arg("HEAD").output().await { ... }
ctx.tier3.push_str(&diff_content);
// Recompute combined
ctx.combined = format!("{}\n{}\n{}", ctx.tier1, ctx.tier2, ctx.tier3);
```

## Tasks

### Task 1: Refactor MCP compile_context handler to use tier builder
**Files to modify:**
- `yolo-mcp-server/src/mcp/tools.rs`

**What to implement:**
1. Add `use crate::commands::tier_context;` import at the top
2. Replace the inline file-reading logic in the `"compile_context"` match arm (lines 32-62) with a call to `tier_context::build_tiered_context()`
3. After getting the `TieredContext`, append async git diff to `tier3` (the existing git diff logic at lines 93-104)
4. Compute `stable_prefix` as `format!("{}\n{}", ctx.tier1, ctx.tier2)` for backward compat
5. Compute `prefix_hash` from `stable_prefix` using sha2 (same as current logic)
6. Build the response JSON with all new fields (`tier1_prefix`, `tier2_prefix`, `tier1_hash`, `tier2_hash`) plus existing backward-compat fields
7. Cache hit/miss detection continues to use `prefix_hash` (comparing against `last_prefix_hashes`)

**Implementation notes:**
- The `build_tiered_context` function uses `std::fs` (sync). In the async MCP handler, this is fine for local file reads (fast, non-blocking in practice). If needed, wrap in `tokio::task::spawn_blocking`, but this is unnecessary for small file reads.
- Preserve the `--- END COMPILED CONTEXT ---` sentinel at the end of tier3 (the tier builder should include it, or the MCP tool appends it).

### Task 2: Update existing Rust unit tests in tools.rs
**Files to modify:**
- `yolo-mcp-server/src/mcp/tools.rs` (test module)

**What to change:**
- `test_compile_context_returns_content`: Update assertions to check for new tier fields (`tier1_prefix`, `tier2_prefix`, `tier1_hash`, `tier2_hash`). Verify `content` field still contains combined text. Verify `stable_prefix` still works (backward compat).
- `test_compile_context_token_estimates`: Verify `prefix_bytes` = tier1.len() + tier2.len() + 1 (newline separator). Verify `input_tokens_estimate` = prefix_bytes + volatile_bytes.
- `test_compile_context_cache_hit_on_second_call`: Same logic, verify cache hit still works with new tier structure.
- `test_compile_context_role_filtering`: Update to verify tier-based filtering. Dev should NOT get ARCHITECTURE.md (it's in tier2/planning family). Architect SHOULD get ARCHITECTURE.md (tier2/planning family). Both should get CONVENTIONS.md and STACK.md (tier1).

### Task 3: Add new cross-agent tier identity tests
**Files to modify:**
- `yolo-mcp-server/src/mcp/tools.rs` (test module)

**What to implement:**
- `test_tier1_identical_across_all_roles`: Call compile_context for roles "dev", "architect", "lead", "qa". Verify `tier1_prefix` and `tier1_hash` are byte-identical across all 4 calls.
- `test_tier2_identical_within_planning_family`: Call for "lead" and "architect". Verify `tier2_prefix` and `tier2_hash` are identical.
- `test_tier2_identical_within_execution_family`: Call for "dev" and "qa". Verify `tier2_prefix` and `tier2_hash` are identical.
- `test_tier2_different_across_families`: Call for "dev" and "lead". Verify `tier2_hash` values differ.
- `test_tier_separation_content_correctness`: Verify tier1 contains CONVENTIONS.md + STACK.md content. Verify tier2/planning contains ARCHITECTURE.md, ROADMAP.md, REQUIREMENTS.md. Verify tier2/execution contains ROADMAP.md only (not ARCHITECTURE.md, not REQUIREMENTS.md).

**Test expectations:**
- All existing tests continue to pass (backward compat)
- 5 new cross-agent identity tests pass
- Total: ~18 tests in the compile_context test section
