---
phase: 2
plan: 2
title: "Update agent injection points for 3-tier context structure"
wave: 1
depends_on: []
must_haves:
  - "compile_context returns tier1_prefix, tier2_prefix, volatile_tail as separate fields"
  - "Tier 1 is byte-identical across all agent roles for the same project"
---

# Plan 2: Update Agent Injection Points for 3-Tier Context

## Goal
Update the markdown command files (`vibe.md`, `execute-protocol.md`) that reference `compile-context` and `compile_context` to document and consume the new 3-tier structure. This ensures the orchestrator correctly passes tier-separated context to Dev/QA agents for maximum cache hit rates.

## Design

### Key Principle: Prefix-First Injection
The current codebase already documents "prefix-first injection" in `execute-protocol.md`. The 3-tier structure makes this explicit:
1. **All agents** receive identical Tier 1 at position 0 in their task description
2. **Same-family agents** (e.g., all Dev agents) receive identical Tier 2 immediately after Tier 1
3. **Per-agent volatile content** (Tier 3) comes last

This layout maximizes the Anthropic API's prompt prefix caching: the API caches the longest common prefix across concurrent requests. With 3 tiers, the cache covers Tier 1 + Tier 2 for same-family agents.

## Tasks

### Task 1: Update `execute-protocol.md` context compilation section
**Files to modify:**
- `references/execute-protocol.md`

**What to change:**
1. In the "Context compilation (REQ-11)" section, update the compile-context invocation documentation to mention the 3-tier output:
   - After running `yolo compile-context {phase} dev {phases_dir} {plan_path}`, the output file `.context-dev.md` now contains three clearly marked sections:
     - `--- TIER 1: SHARED BASE ---` (byte-identical for all roles)
     - `--- TIER 2: ROLE FAMILY (execution) ---` (byte-identical for dev/qa/senior)
     - `--- TIER 3: VOLATILE TAIL (phase={N}) ---` (phase-specific)
2. In the "Prefix-first injection" section, update the explanation to reference tiers:
   - "All sibling Dev agents MUST receive byte-identical Tier 1 + Tier 2 content for cache hits."
   - "When the MCP `compile_context` tool is used instead of CLI, the response contains `tier1_prefix`, `tier2_prefix`, and `volatile_tail` as separate fields. Callers should concatenate them in order."
3. In the "Control Plane Coordination" section where `compile-context` is referenced, no changes needed (it just calls the CLI).

### Task 2: Update `vibe.md` context compilation reference
**Files to modify:**
- `commands/vibe.md`

**What to change:**
1. In step 4 (Context compilation), update the format description:
   - Old: "The compiled context format uses `--- COMPILED CONTEXT (role={role}) ---` as the stable prefix header"
   - New: "The compiled context format uses 3 tiers: `--- TIER 1: SHARED BASE ---` (project-wide, byte-identical across all roles), `--- TIER 2: ROLE FAMILY ({family}) ---` (byte-identical within planning or execution families), and `--- TIER 3: VOLATILE TAIL (phase={N}) ---` for phase-specific content."
2. Update any reference to `stable_prefix` to mention the tier structure. The compile-context CLI still produces a single `.context-{role}.md` file, but the internal structure has 3 sections instead of 2.

### Task 3: Update `token-budgets.json` with role family metadata
**Files to modify:**
- `config/token-budgets.json`

**What to change:**
- Add a new `"role_families"` section to token-budgets.json that documents the family mapping for downstream consumers:
```json
"role_families": {
  "planning": ["lead", "architect"],
  "execution": ["dev", "senior", "qa", "security", "debugger"],
  "default": ["docs", "reviewer"]
}
```
- This is informational metadata — the source of truth for family mapping is in the Rust `tier_context.rs` module. But having it in config allows shell scripts and bats tests to verify family membership without calling Rust code.

**Test expectations:**
- No code tests for this plan (markdown documentation changes)
- Manual verification: the tier header strings in documentation match what `tier_context.rs` (Plan 01) produces
