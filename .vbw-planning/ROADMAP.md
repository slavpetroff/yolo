# YOLO — Your Own Local Orchestrator Roadmap

**Goal:** YOLO — Your Own Local Orchestrator

**Scope:** 6 phases

## Progress
| Phase | Status | Plans | Tasks | Commits |
|-------|--------|-------|-------|---------|
| 1 | Complete | 5 | 20 | 22 |
| 2 | Complete | 5 | 19 | 22 |
| 3 | Pending | 0 | 0 | 0 |
| 4 | Pending | 0 | 0 | 0 |
| 5 | Pending | 0 | 0 | 0 |
| 6 | Pending | 0 | 0 | 0 |

---

## Phase List
- [x] [Phase 1: Complexity Routing & Shortcuts](#phase-1-complexity-routing-shortcuts)
- [x] [Phase 2: Product Ownership Layer](#phase-2-product-ownership-layer)
- [ ] [Phase 3: Department Agent Expansion](#phase-3-department-agent-expansion)
- [ ] [Phase 4: Execution & Review Loops](#phase-4-execution-review-loops)
- [ ] [Phase 5: Integration & Delivery Pipeline](#phase-5-integration-delivery-pipeline)
- [ ] [Phase 6: Migration & Token Optimization](#phase-6-migration-token-optimization)

---

## Phase 1: Complexity Routing & Shortcuts

**Goal:** Implement unified Analyze step (Complexity Classifier + Department Router + Intent Detection). Add Trivial shortcut (direct to Dept Senior), Medium path (Lead -> Senior, skip Architect + Critique), and High path (full ceremony). Wire into go.md replacing current phase-detect routing.

**Requirements:** Analyze agent outputs complexity, departments, intent, confidence in single call, Trivial tasks route directly to department Senior(s), Medium tasks route to Lead -> Senior, skipping Architect and Critique, High tasks follow full ceremony through PO -> Tech Lead -> departments, Debug intent routes to Debugger -> Tech Lead, Analyze always runs on strongest model (opus), Backward compatible with existing go.md modes

**Success Criteria:**
- Analyze agent correctly classifies trivial/medium/high with >90% accuracy on test cases
- Trivial path executes with <30% token cost of full path
- Medium path executes with <60% token cost of full path
- All existing go.md modes still work through new routing

**Dependencies:** None

---

## Phase 2: Product Ownership Layer

**Goal:** Replace current Owner agent with Product Owner Agent. Add Questionary Agent with capped PO loop (max 3 rounds). Add Dependency & Roadmap Agent for phase/milestone planning. Wire PO -> Questionary -> Tech Lead flow.

**Requirements:** Product Owner Agent manages vision, requirements, scope decisions, Questionary Agent handles structured scope clarification with PO (capped 3 rounds), Dependency & Roadmap Agent plans phase ordering and cross-phase dependencies, PO -> Questionary loop produces structured scope document, Tech Lead receives enriched scope from PO layer, User presentation via orchestrator delivery mode (not separate agent), user_presentation output type in PO protocol rendered via AskUserQuestion

**Success Criteria:**
- PO -> Questionary loop resolves scope in <=3 rounds for test scenarios
- Roadmap Agent produces valid phase dependency graph
- Orchestrator correctly renders PO questions to user and feeds responses back
- No agent directly contacts user (Owner-first proxy preserved)

**Dependencies:** Phase 1

---

## Phase 3: Department Agent Expansion

**Goal:** Add per-department Security Reviewer, config-gated Documenter, and confidence-gated Critique Loop. Merge Solution Q&A responsibilities into Lead. Update TOON files, context manifests, and compile-context.sh for expanded agent roster.

**Requirements:** Security Reviewer agent per department (BE, FE, UX) with dept-scoped security checks, Documenter agent per department, config-gated (documenter: on_request/always/never), Critique Loop with hard cap (3 rounds) and confidence threshold (85) for early exit, critique.jsonl gets cf (confidence) field, auditable per round, Lead absorbs Solution Q&A responsibilities (no separate Q&A agent), Context manifests (context-manifest.json) per role defining exact files/fields needed, compile-context.sh reads manifests and produces token-budgeted context packages, Agent count goes from 26 to ~35 with new roles

**Success Criteria:**
- Security Reviewer catches dept-specific vulnerabilities in test scenarios
- Documenter only spawns when config enables it
- Critique exits early when confidence >= 85 on first round
- Critique never exceeds 3 rounds regardless of confidence
- Context packages per agent are measurably smaller than current full-context approach

**Dependencies:** Phase 2

---

## Phase 4: Execution & Review Loops

**Goal:** Implement Dev <-> Senior review loop (max 2 rounds). Add Dev suggestions field (sg) to summary.jsonl. Update per-department Tester agents. Formalize Scout as shared on-demand research utility callable by any agent.

**Requirements:** Dev -> Senior review loop with max 2 rounds, Dev populates sg (suggestions) field in summary.jsonl, Senior reviews suggestions during code-review step, can promote to next iteration, Per-department Tester agents produce structured test results, Scout callable via research_request output type from any agent, Blocking research requests pause agent flow until Scout returns, Informational research requests are async, research.jsonl captures all Scout findings with requesting agent attribution, Escalation only when problem is out of agent defined scope, escalation.jsonl logs agent, reason, scope_boundary, target

**Success Criteria:**
- Dev/Senior review resolves issues within 2 rounds for test scenarios
- Scout spawns on-demand when research_request detected, not spawned otherwise
- Escalation logs show agents only escalating out-of-scope problems
- summary.jsonl sg field populated and reviewed by Senior

**Dependencies:** Phase 3

---

## Phase 5: Integration & Delivery Pipeline

**Goal:** Implement Integration Gate Agent as barrier convergence for all department Testers. Add PO Q&A with Patch (fast, dept-specific fix) and Major (re-scope with user) rejection paths. Wire Delivery mode in orchestrator. Feedback loop from user back to PO Agent.

**Requirements:** Integration Gate Agent waits for all department Testers (barrier mode), Configurable timeout on Integration Gate for department completion, Integration Gate checks API contracts, design sync, cross-dept handoffs, PO Q&A after Integration Gate validates against vision and requirements, Patch rejection: routes to specific dept Senior for targeted fix, low-token, Major rejection: loops to Questionary <-> User for re-scoping, then full pipeline, po_default_rejection config (default: patch), Orchestrator delivery mode presents PO output to user via AskUserQuestion, User feedback flows back to PO Agent for new iteration

**Success Criteria:**
- Integration Gate correctly identifies cross-dept contract mismatches in tests
- Patch path executes with <20% token cost of full re-plan
- Major path correctly re-triggers affected departments only
- User sees structured presentation of results and can provide actionable feedback
- End-to-end flow: User request -> Analyze -> Departments -> Integration -> PO -> User

**Dependencies:** Phase 4

---

## Phase 6: Migration & Token Optimization

**Goal:** Migrate all existing configs, TOON files, and hooks to new architecture. Deprecate and remove old agents. Run token audit per-phase comparing old vs new architecture. Update all references, naming conventions, and documentation.

**Requirements:** Migrate existing 26 agent TOON files to new role definitions, Create TOON files for ~9 new agent roles, Update hooks.json for new agent lifecycle events, Update config/defaults.json with new settings (critique thresholds, documenter gate, po config), Deprecate old Owner agent in favor of PO Agent, Update compile-context.sh for context-manifest.json consumption, Update all references/ docs for new architecture, Token audit: measure tokens per phase for trivial/medium/high paths, Verify zero-dependency principle maintained (no new external deps), Update CLAUDE.md with new architecture, agent roster, decision log

**Success Criteria:**
- All 35 agents have valid TOON files with scope boundaries defined
- Hooks correctly trigger for new agent lifecycle
- Token audit shows trivial path <30%, medium <60% of high path cost
- All existing tests pass with new architecture
- New tests cover complexity routing, confidence-gated loops, and integration gate
- CLAUDE.md reflects complete new architecture

**Dependencies:** Phase 5

