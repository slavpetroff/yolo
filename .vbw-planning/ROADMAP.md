# YOLO Roadmap

**Milestone:** Company-Grade Engineering Workflow
**Scope:** 5 phases

## Progress
| # | Phase | Status | Plans | Tasks | Commits |
|---|-------|--------|-------|-------|---------|
| 1 | Company Hierarchy & Agent Teams | Complete | 0 | 0 | 2 |
| 2 | Token-Optimized Artifacts | Complete | 3 | 5 | 1 |
| 3 | Persistence & Crash Resilience | Complete | 4 | 4 | 1 |
| 4 | Quality Loop & Remediation | Complete | 2 | 2 | 1 |
| 5 | UX, Tooling & Community | Complete | 2 | 2 | 1 |

---

## Phase List
- [x] [Phase 1: Company Hierarchy & Agent Teams](#phase-1-company-hierarchy--agent-teams)
- [x] [Phase 2: Token-Optimized Artifacts](#phase-2-token-optimized-artifacts)
- [x] [Phase 3: Persistence & Crash Resilience](#phase-3-persistence--crash-resilience)
- [x] [Phase 4: Quality Loop & Remediation](#phase-4-quality-loop--remediation)
- [x] [Phase 5: UX, Tooling & Community](#phase-5-ux-tooling--community)

---

## Phase 1: Company Hierarchy & Agent Teams

**Goal:** Establish company-grade agent hierarchy with Senior Engineer, QA Code Engineer, Security Engineer agents. Wire Architect into Scope. Implement 8-step workflow in execute-protocol. Update compile-context.sh for all new roles. Define JSONL handoff schemas.

**Reqs:** REQ-03, REQ-08

**Success Criteria:**
- yolo-senior.md exists with Opus model, code review + spec enrichment role
- yolo-qa-code.md exists with Sonnet model, Bash access for running tests/lint
- yolo-security.md exists with Sonnet model, OWASP/secrets/deps audit
- yolo-architect.md updated: R&D role, produces architecture.toon, wired into Scope mode
- yolo-dev.md updated: Junior role, receives only enriched specs from Senior
- yolo-qa.md updated: QA Lead role, plan-level verification only
- execute-protocol.md implements 8-step company workflow
- compile-context.sh supports all new roles with token budgets
- references/company-hierarchy.md and artifact-formats.md define the system
- handoff-schemas.md includes all new agent communication schemas
- go.md Scope mode delegates to Architect agent

**Dependencies:** None

---

## Phase 2: Token-Optimized Artifacts

**Goal:** Migrate all agent-facing artifacts from Markdown to JSONL with abbreviated keys. Implement TOON compiled context. Create state.json to replace STATE.md for machines. Token budget enforcement in compile-context.sh.

**Reqs:** REQ-08

**Success Criteria:**
- Plan files use {NN-MM}.plan.jsonl format (JSONL, abbreviated keys)
- Summary files use {NN-MM}.summary.jsonl format
- Verification uses verification.jsonl format
- state.json replaces STATE.md for machine consumption
- reqs.jsonl replaces REQUIREMENTS.md for machine consumption
- compile-context.sh outputs .ctx-{role}.toon with enforced token budgets
- state-updater.sh reads/writes JSONL artifacts via jq
- Templates updated for new formats
- All scripts parse new formats without regressions

**Dependencies:** Phase 1

---

## Phase 3: Persistence & Crash Resilience

**Goal:** Commit every artifact immediately after creation. Enhanced session-start.sh recovery. decisions.jsonl for agent decision logging. .execution-state.json committed on transitions. Full resume protocol surviving Claude Code exit.

**Reqs:** REQ-01, REQ-04

**Success Criteria:**
- Every JSONL artifact is git-committed immediately after write
- session-start.sh reconstructs exact state from committed artifacts
- decisions.jsonl captures agent decisions (survives compaction + exit)
- .execution-state.json committed on step transitions
- Research persisted as research.jsonl during planning (Scout writes)
- Resume from any workflow step works after session exit
- No context bleed between teams on resume
- compile-context.sh regenerates .ctx-{role}.toon from committed JSONL

**Dependencies:** Phase 2

---

## Phase 4: Quality Loop & Remediation

**Goal:** Iterative QA-Code verification loop with gap tracking, Senior code review step, remediation cycles, manual approval gates, security audit step, escalation to Architect on design failures.

**Reqs:** REQ-06

**Success Criteria:**
- QA-Code runs tests, lint, coverage analysis, pattern checks
- Senior code review happens BEFORE QA (Step 5 in workflow)
- PARTIAL/FAIL → gaps.jsonl → Dev fixes → re-verify (max 2 cycles)
- Manual approval gates configurable via config.json
- Escalation: 2x QA fail → Senior review, 3x → Architect re-evaluate
- Security audit (Step 7) blocks on FAIL unless user --force
- TDD test generation as pre-implementation step

**Dependencies:** Phase 3

---

## Phase 5: UX, Tooling & Community

**Goal:** Token tooling integration (llm-tldr, RTK hooks), speed/quality presets, output formatting, user documentation, contributor guide, ADRs.

**Reqs:** REQ-07

**Success Criteria:**
- llm-tldr integration for token-efficient codebase mapping
- RTK/TLDR hooks documented and optimized
- Speed/quality presets control full workflow depth
- Output formatting polished per brand essentials
- User documentation enables solo onboarding
- Contributor guide enables adding agents/commands
- Key architectural decisions documented as ADRs

**Dependencies:** Phase 4
