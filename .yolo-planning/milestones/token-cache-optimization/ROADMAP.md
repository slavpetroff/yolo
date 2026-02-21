# Token & Cache Architecture Optimization Roadmap

**Goal:** Token & Cache Architecture Optimization

**Scope:** 4 phases

## Progress
| Phase | Status | Plans | Tasks | Commits |
|-------|--------|-------|-------|----------|
| 1 | Complete | 3 | 10 | 9 |
| 2 | Complete | 4 | 11 | 10 |
| 3 | Complete | 4 | 16 | 12 |
| 4 | Complete | 6 | 24 | 24 |

---

## Phase List
- [x] [Phase 1: Token Economics Baseline](#phase-1-token-economics-baseline)
- [x] [Phase 2: Hybrid Cache Prefix Architecture](#phase-2-hybrid-cache-prefix-architecture)
- [x] [Phase 3: Context Pruning & Skills Migration](#phase-3-context-pruning-skills-migration)
- [x] [Phase 4: Automation Hooks & Subagent Patterns](#phase-4-automation-hooks-subagent-patterns)

---

## Phase 1: Token Economics Baseline

**Goal:** Instrument telemetry to measure current token spend per agent, cache hit/miss rates, and waste patterns. Build the dashboard (CLI report command) that surfaces per-agent cost breakdown, waste identification, and ROI per phase. This is measurement-first: no optimization changes, just visibility.

**Requirements:** REQ-02

**Success Criteria:**
- yolo report shows per-agent token spend (input/output/cache_read/cache_write) per phase
- Cache hit rate percentage calculated from telemetry data
- Waste metric: tokens loaded but never referenced in output (heuristic)
- ROI metric: tokens spent per commit/task delivered
- Dashboard renders in terminal with YOLO brand formatting

**Dependencies:** None

---

## Phase 2: Hybrid Cache Prefix Architecture

**Goal:** Restructure compile_context to produce a 3-tier prefix: Tier 1 (shared base: tools, project meta, stack — identical for all agents), Tier 2 (role-family: planning roles vs execution roles get different reference sets), Tier 3 (volatile tail: phase-specific plans, task context). Update the MCP tool, CLI command, and all agent injection points (vibe.md, execute-protocol) to use the new structure.

**Requirements:** REQ-01

**Success Criteria:**
- compile_context returns tier1_prefix, tier2_prefix, volatile_tail as separate fields
- Tier 1 is byte-identical across all agent roles for the same project
- Tier 2 is byte-identical within role families (lead+architect share, dev+qa share)
- Existing tests pass + new tests for tier separation and cross-agent prefix identity
- Measured cache hit rate improvement vs baseline (Phase 1 dashboard)

**Dependencies:** Phase 1

---

## Phase 3: Context Pruning & Skills Migration

**Goal:** Prune CLAUDE.md to ~40 lines by moving verbose sections (plugin isolation, context isolation, detailed conventions) into on-demand skills. Selectively migrate the largest protocol references (execute-protocol, discussion-engine, verification-protocol) to skills that load only when their command is invoked. Keep frequently-used references (brand essentials, effort profiles) always-loaded.

**Requirements:** REQ-03, REQ-04

**Success Criteria:**
- CLAUDE.md under 45 lines with no loss of critical rules
- At least 3 protocol references converted to skills with SKILL.md + frontmatter
- Skills load correctly when their parent command is invoked
- No behavioral regression: agents still follow conventions and isolation rules
- Measured context window savings from CLAUDE.md reduction

**Dependencies:** Phase 2

---

## Phase 4: Automation Hooks & Subagent Patterns

**Goal:** Add hooks for automated quality gates (lint after edit, test validation, cache warming on session start) and establish subagent isolation patterns so research and verification run in separate contexts. Document patterns for when to use subagents vs inline processing.

**Requirements:** REQ-05, REQ-06

**Success Criteria:**
- At least 2 new automation hooks implemented and registered in hooks.json
- Subagent usage documented in agent definitions with context isolation guidelines
- Research operations (map, discuss, research) use subagents to protect main context
- Hook-based test validation runs after Dev agent edits (configurable)
- All existing tests pass + new tests for hook behavior

**Dependencies:** Phase 3

