---
phase: 2
plan: 1
title: "Define 3-tier context builder module with Rust unit tests"
wave: 1
depends_on: []
must_haves:
  - "compile_context returns tier1_prefix, tier2_prefix, volatile_tail as separate fields"
  - "Tier 1 is byte-identical across all agent roles for the same project"
  - "Tier 2 is byte-identical within role families (lead+architect share, dev+qa share)"
---

# Plan 1: Define 3-Tier Context Builder Module

## Goal
Create a new `tier_context.rs` module with pure functions that produce the 3-tier prefix structure. This module contains no MCP or CLI coupling — just data assembly logic with SHA-256 hashing. Both the MCP tool (Plan 03) and CLI command (Plan 04) will call these functions.

## Design

### Tier Definitions
- **Tier 1 (Shared Base):** Project meta, stack, conventions — files that are identical for ALL roles. Read from `.yolo-planning/codebase/CONVENTIONS.md` and `.yolo-planning/codebase/STACK.md`. Header: `--- TIER 1: SHARED BASE ---`. Must be byte-identical for every role.
- **Tier 2 (Role Family):** Role-family-specific references. Two families:
  - **planning** (lead, architect): ARCHITECTURE.md, ROADMAP.md, REQUIREMENTS.md
  - **execution** (dev, senior, qa, security, debugger): ROADMAP.md only
  - **default**: ROADMAP.md only
  Header: `--- TIER 2: ROLE FAMILY ({family}) ---`
- **Tier 3 (Volatile Tail):** Phase-specific plans, git diff — same as current `volatile_tail`. Header: `--- TIER 3: VOLATILE TAIL (phase={N}) ---`

### Role Family Mapping
```rust
fn role_family(role: &str) -> &'static str {
    match role {
        "architect" | "lead" => "planning",
        "dev" | "senior" | "qa" | "security" | "debugger" => "execution",
        _ => "default",
    }
}
```

### Output Struct
```rust
pub struct TieredContext {
    pub tier1: String,       // shared base content
    pub tier2: String,       // role-family content
    pub tier3: String,       // volatile tail
    pub tier1_hash: String,  // SHA-256 of tier1
    pub tier2_hash: String,  // SHA-256 of tier2
    pub combined: String,    // tier1 + tier2 + tier3 (backward compat)
}
```

## Tasks

### Task 1: Create `tier_context.rs` module with tier builder functions
**Files to create:**
- `yolo-mcp-server/src/commands/tier_context.rs`

**Files to modify:**
- `yolo-mcp-server/src/commands/mod.rs` (add `pub mod tier_context;`)

**What to implement:**
- `pub fn role_family(role: &str) -> &'static str` — maps role to family name
- `pub fn tier1_files() -> Vec<&'static str>` — returns `["CONVENTIONS.md", "STACK.md"]`
- `pub fn tier2_files(family: &str) -> Vec<&'static str>` — returns family-specific file list
- `pub fn build_tier1(planning_dir: &Path) -> String` — reads tier 1 files, produces deterministic content with `--- TIER 1: SHARED BASE ---` header
- `pub fn build_tier2(planning_dir: &Path, family: &str) -> String` — reads tier 2 files, produces content with `--- TIER 2: ROLE FAMILY ({family}) ---` header
- `pub fn build_tier3_volatile(phase: i64, phases_dir: Option<&Path>, plan_path: Option<&Path>) -> String` — reads phase plans and produces volatile tail with `--- TIER 3: VOLATILE TAIL (phase={N}) ---` header. Does NOT include git diff (caller adds that for MCP vs CLI differences)
- `pub fn sha256_of(s: &str) -> String` — SHA-256 hex digest helper
- `pub struct TieredContext` with the fields listed above
- `pub fn build_tiered_context(planning_dir: &Path, role: &str, phase: i64, phases_dir: Option<&Path>, plan_path: Option<&Path>) -> TieredContext` — orchestrates tier1 + tier2 + tier3 + hashes + combined

**Implementation notes:**
- Use `std::fs` (sync) so both MCP (async) and CLI (sync) callers can use it. The MCP tool can call it from `tokio::task::spawn_blocking` or just call synchronously (file reads are fast).
- File reading must be deterministic: always read files in the order returned by `tier1_files()` / `tier2_files()`. No directory enumeration for tiers 1 and 2.
- Tier 3 plan file enumeration: sort entries by filename before reading (deterministic ordering).
- The `combined` field concatenates `tier1 + "\n" + tier2 + "\n" + tier3` with newlines.

### Task 2: Unit tests for tier separation and identity guarantees
**Files to modify:**
- `yolo-mcp-server/src/commands/tier_context.rs` (add `#[cfg(test)] mod tests` section)

**What to implement:**
- Test `role_family` returns correct family for all known roles
- Test `tier1_files` and `tier2_files` return expected file lists
- Test `build_tier1` produces byte-identical output regardless of which role calls it (call for "dev", "architect", "lead" — all must match)
- Test `build_tier2` produces byte-identical output for roles in the same family ("dev" and "qa" produce same tier2; "lead" and "architect" produce same tier2)
- Test `build_tier2` produces DIFFERENT output for roles in different families ("dev" vs "lead")
- Test `build_tiered_context` returns all three tiers and correct hashes
- Test `build_tiered_context` combined field equals tier1 + tier2 + tier3
- Test `sha256_of` is deterministic

**Test expectations:**
- At least 8 unit tests covering the guarantees above
- All tests pass with `cargo test`
