# CLI Intelligence & Token Optimization Roadmap

**Goal:** Fix incomplete CLI commands, add structured JSON returns to all state-changing operations, reduce token overhead by 10-15%, split vibe.md for on-demand mode loading, and audit/fix codebase quality issues

**Scope:** 9 phases

## Progress
| Phase | Status | Plans | Tasks | Commits |
|-------|--------|-------|-------|----------|
| 1 | Complete | 5 | 18 | 14 |
| 2 | Complete | 4 | 20 | 17 |
| 3 | Complete | 4 | 14 | 9 |
| 4 | Complete | 4 | 15 | 9 |
| 5 | Complete | 5 | 15 | 5 |
| 6 | Pending | 0 | 0 | 0 |
| 7 | Pending | 0 | 0 | 0 |
| 8 | Pending | 0 | 0 | 0 |
| 9 | Pending | 0 | 0 | 0 |

---

## Phase List
- [x] [Phase 1: Incomplete CLI & MCP Command Fixes](#phase-1-incomplete-cli--mcp-command-fixes)
- [x] [Phase 2: Rust CLI Structured Returns](#phase-2-rust-cli-structured-returns)
- [x] [Phase 3: Token Reduction Sweep](#phase-3-token-reduction-sweep)
- [x] [Phase 4: Hot Path & vibe.md Mode Splitting](#phase-4-hot-path--vibemd-mode-splitting)
- [x] [Phase 5: Release Prep & README Rewrite](#phase-5-release-prep--readme-rewrite)
- [ ] [Phase 6: Critical Protocol & Documentation Fixes](#phase-6-critical-protocol--documentation-fixes)
- [ ] [Phase 7: Dead Code & Agent Cleanup](#phase-7-dead-code--agent-cleanup)
- [ ] [Phase 8: Token & Context Optimization](#phase-8-token--context-optimization)
- [ ] [Phase 9: Validation & Robustness](#phase-9-validation--robustness)

---

## Phase 1: Incomplete CLI & MCP Command Fixes

**Goal:** Fix broken and incomplete Rust CLI commands so every path produces correct, complete output. This is foundational — structured returns and token optimizations depend on commands actually working.

**Requirements:** REQ-01 (CLI completeness)

**Success Criteria:**
- `yolo infer` correctly detects tech stack (languages, frameworks, tools) from pyproject.toml, Cargo.toml, package.json, go.mod, etc.
- `yolo infer` extracts project purpose from README.md, PROJECT.md, or package description
- `yolo detect-stack` returns complete JSON with all detected signals
- `yolo delta-files` returns distinguishable empty vs no-strategy-worked responses
- `yolo hard-gate` exits 2 on conflict (not 0)
- `yolo lock` exits 2 on conflict (not 0)
- All 56 CLI commands audited for stubs, silent failures, and unrouted modules
- End-to-end test: `yolo infer` on alpine-notetaker correctly detects FastAPI + Redis + Python

**Dependencies:** None

---

## Phase 2: Rust CLI Structured Returns

**Goal:** Make all state-changing CLI commands return structured JSON with operation deltas, eliminating 50-150 wasted LLM tool calls per phase execution.

**Requirements:** REQ-02 (LLM efficiency)

**Success Criteria:**
- 12 fire-and-forget commands return structured JSON: `{"ok": bool, "cmd": "...", "changed": [...], "delta": {...}, "elapsed_ms": N}`
- Exit code standardization: 0=success, 1=error, 2=partial/conflict, 3=skipped
- LLM caller never needs to re-read a file just to understand what a command did
- `update-state` returns delta showing before/after state
- `compile-context` returns tier sizes, cache hit info, output path
- `planning-git commit-boundary` returns commit hash or "skipped" with reason
- `bootstrap *` returns content summary of generated file
- `suggest-next` returns reasoning along with suggestion
- All existing tests pass with JSON output parsing

**Dependencies:** Phase 1

---

## Phase 3: Token Reduction Sweep

**Goal:** Reduce static token overhead by 10-15% per workflow cycle through deduplication, conditional loading, and reference consolidation.

**Requirements:** REQ-03 (token efficiency)

**Success Criteria:**
- V3 experimental features extracted from execute-protocol.md to optional file (loaded only when enabled)
- Shared "Agent Base Patterns" reference created, deduplicating Circuit Breaker/Context Injection/Shutdown across 5 agents
- 4 effort profile MDs consolidated into 1 JSON + summary doc
- 3 dead redirect references removed (execute-protocol.md, discussion-engine.md, verify-protocol.md in references/)
- Handoff-schemas.md reduced via schema-driven approach (JSON examples → config reference)
- Measured token reduction via `yolo report-tokens` shows 10%+ improvement
- No behavioral regression (all tests pass, agents follow conventions)

**Dependencies:** Phase 2

---

## Phase 4: Hot Path & vibe.md Mode Splitting

**Goal:** Optimize highest-frequency code paths. Split vibe.md monolith into mode-specific files for on-demand loading, reducing per-invocation token cost from 7,220 to ~1,500.

**Requirements:** REQ-04 (hot path optimization)

**Success Criteria:**
- vibe.md split into mode-specific files (plan.md content, execute.md content, etc.) loaded on demand
- Each /yolo:vibe invocation loads only the active mode (~1,500 tokens) instead of all 11 (~7,220 tokens)
- Tier 1 mtime caching in compile-context (skip recompilation when architecture unchanged)
- `v2_token_budgets=true` enabled by default with safe defaults
- `session-start` reports step-level success/failure for all 15 init steps
- Measured tokens-per-phase improvement via `yolo report-tokens`
- No behavioral regression across all workflow paths (plan, execute, verify, discuss, archive)

**Dependencies:** Phase 3

---

## Phase 5: Release Prep & README Rewrite

**Goal:** Clean VBW remnants, rewrite README to be concise and performance-focused with actual before/after comparisons vs plain agent usage, bump version, and release.

**Requirements:** REQ-05 (release readiness)

**Success Criteria:**
- All VBW references removed from active code (CLAUDE.md, plugin-isolation.md)
- README rewritten: concise guide with architecture, lifecycle flows, and design idioms explaining how the plugin works
- Stale metrics updated (test count, version references, analysis report links)
- Version bumped (patch) across all 4 version files
- CHANGELOG updated with [Unreleased] → versioned
- Git tag created, pushed, GitHub release created

**Dependencies:** Phase 4

---

## Phase 6: Critical Protocol & Documentation Fixes

**Goal:** Fix bugs that silently break the execution pipeline: token-budget stdout corruption, missing SUMMARY.md ownership spec, and stale README claims that mislead users.

**Requirements:** REQ-06 (protocol correctness)

**Success Criteria:**
- Token-budget pipeline in execute-protocol SKILL.md fixed: context file never overwritten with JSON metadata (C1)
- Step 3c in execute-protocol SKILL.md filled with explicit SUMMARY.md writing spec for Dev agent (C2)
- yolo-dev.md updated with explicit "write SUMMARY.md after plan completion" instruction (C2)
- README agent table updated: 6 agents, Scout and QA rows removed (C3)
- README hook count corrected: "11 hook entries routing to ~19 internal handlers" (C4)
- README test count updated to actual (1,594) (V2)
- STACK.md version updated to 2.5.0 (T2)
- All existing tests pass

**Dependencies:** Phase 5

---

## Phase 7: Dead Code & Agent Cleanup

**Goal:** Remove dead code paths, unwired agents, and disconnected feature flags. Every file in the repo should be reachable from a live code path.

**Requirements:** REQ-07 (code hygiene)

**Success Criteria:**
- yolo-reviewer: either wired into architect/roadmap workflow OR removed from agents/ (decision during planning) (D1)
- yolo-docs: either wired into /yolo:release or /yolo:vibe --archive workflow OR documented as manual-only in README (D2)
- handle_stub removed from dispatcher.rs (D3)
- v3_lease_locks: either wired into Rust lease-lock command OR removed from session-start export (D4)
- Codebase map refreshed: ARCHITECTURE.md, CONCERNS.md updated with accurate counts and no stale claims (CONCERNS says "No Rust unit tests" — 923 exist)
- hooks.json SubagentStart matcher updated to match actual agent roster
- All existing tests pass

**Dependencies:** Phase 6

---

## Phase 8: Token & Context Optimization

**Goal:** Reduce per-agent token waste by filtering stale context, fixing output paths for concurrency safety, and eliminating unnecessary team overhead.

**Requirements:** REQ-08 (token efficiency)

**Success Criteria:**
- tier_context.rs filters completed phases from ROADMAP.md before including in Tier 2 — only current + future phases included (T1)
- compile-context output written to phase subdirectory (`phases/05-slug/.context-dev.md`) not phases root — safe for concurrent phase execution (T3)
- execute-protocol SKILL.md updated to reference new output path
- prefer_teams optimization: skip TeamCreate/TeamDelete when exactly 1 uncompleted plan in phase (T4)
- Measured token reduction on Tier 2 context via `yolo report-tokens` shows improvement
- All existing tests pass, compile-context bats tests updated for new output path

**Dependencies:** Phase 7

---

## Phase 9: Validation & Robustness

**Goal:** Add missing validation gates and integration tests for feature-flag-gated code paths. Close the gap between declared protocol and enforced protocol.

**Requirements:** REQ-09 (validation completeness)

**Success Criteria:**
- depends_on validation added to Rust: `yolo validate-plan` cross-references plan IDs against existing plan files in phase directory (V1)
- validate_summary.rs upgraded: checks YAML frontmatter fields (phase, plan, status, tasks_completed) not just section headers
- v2/v3 feature flag integration tests added to bats: at least 1 test per flag exercising the actual gated code path (v2_hard_gates, v3_lease_locks, v3_schema_validation, v3_lock_lite)
- execute-protocol cross-phase deps check moved from LLM instruction to Rust validation command
- All existing tests pass + new validation tests pass

**Dependencies:** Phase 8
