# YOLO — Your Own Local Orchestrator Roadmap

**Goal:** YOLO — Your Own Local Orchestrator

**Scope:** 10 phases

## Progress
| Phase | Status | Plans | Tasks | Commits |
|-------|--------|-------|-------|---------|
| 1 | Complete | 5 | 20 | 22 |
| 2 | Complete | 5 | 19 | 22 |
| 3 | Complete | 7 | 29 | 37 |
| 4 | Complete | 7 | 34 | 37 |
| 5 | Complete | 6 | 23 | 24 |
| 6 | Complete | 6 | 26 | 22 |
| 7 | Complete | 6 | 28 | 28 |
| 8 | Complete | 7 | 33 | 39 |
| 9 | Complete | 10 | 50 | 50 |
| 10 | Complete | 12 | 60 | 55 |

---

## Phase List
- [x] [Phase 1: Complexity Routing & Shortcuts](#phase-1-complexity-routing-shortcuts)
- [x] [Phase 2: Product Ownership Layer](#phase-2-product-ownership-layer)
- [x] [Phase 3: Department Agent Expansion](#phase-3-department-agent-expansion)
- [x] [Phase 4: Execution & Review Loops](#phase-4-execution-review-loops)
- [x] [Phase 5: Integration & Delivery Pipeline](#phase-5-integration-delivery-pipeline)
- [x] [Phase 6: Migration & Token Optimization](#phase-6-migration-token-optimization)
- [x] [Phase 7: Architecture Audit & Optimization](#phase-7-architecture-audit-optimization)
- [x] [Phase 8: Full Template System Migration](#phase-8-full-template-system-migration)
- [x] [Phase 9: Workflow Redundancy Audit & Token Optimization](#phase-9-workflow-redundancy-audit-token-optimization)
- [x] [Phase 10: SQLite-Backed Artifact Store & Context Engine](#phase-10-sqlite-backed-artifact-store-context-engine)

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

---

## Phase 7: Architecture Audit & Optimization

**Goal:** Comprehensive architecture audit addressing redundancy, token waste, context gaps, and communication issues identified by Scout research. Consolidate duplicate agent files via template pattern, optimize context compilation with rolling summaries and mode filtering, fix classification redundancy, improve cross-department communication, and remove dead config flags.

**Requirements:** Consolidate ~85% duplicate content across 27 department agent files into template + overlay pattern (R-1), Implement mode-filtered agent prompts to eliminate unused sections per invocation (T-2), Resolve dual classification redundancy between complexity-classify.sh and Analyze agent (CI-1), Add pre-integration check at department Lead level to catch showstoppers before full Integration Gate (CH-4), Skip PO-Questionary loop for medium-path tasks (T-6), Add lightweight lint/type-check for trivial-path tasks (QR-4), Remove dead v2/v3 feature flags from config (CS-1), Implement rolling summary approach for compile-context.sh to cap context growth (T-1), Ensure all 36 agents have context-manifest.json entries (CG-3), Add structured error recovery context for task retries (CG-4)

**Success Criteria:**
- Agent file count reduced from 27 dept-specific to 9 templates + 3 dept overlays
- Per-invocation agent prompt tokens reduced 30-50% via mode filtering
- Single classification path (no dual classify.sh + Analyze)
- Medium-path tasks skip PO loop, saving ~2000 tokens each
- All context-manifest entries present for 36 agents
- Dead feature flags removed, config simplified
- Token audit shows 25-35% reduction per full-ceremony phase vs current baseline

**Dependencies:** Phase 6

---

## Phase 8: Full Template System Migration

**Goal:** Complete the template system migration that Phase 7 started but left disconnected. Back-port all hand-authored FE/UX agent content into overlay JSON files to achieve parity. Wire generate-agent.sh into the live workflow so go.md spawns template-generated agents instead of static hand-authored files. Create a regeneration pipeline with staleness detection, add a GENERATED marker to prevent accidental edits, integrate mode filtering into go.md for per-workflow-step token savings, and add comprehensive tests and documentation.

**Requirements:** Diff all 27 hand-authored dept agents against template+overlay dry-run output and catalog differences, Back-port all FE/UX department-specific content (vocabulary, a11y rules, decision frameworks) from hand-authored agents into overlay JSON files, Back-port recent feature additions (sg field, test-results.jsonl stage, research.jsonl attribution) to templates and all 3 overlays, Create scripts/regenerate-agents.sh wrapper (all 27 combos + --check mode for CI), Add staleness detection via .agent-generation-hash compared on SessionStart, Wire generate-agent.sh into go.md or SubagentStart hook so dept agents are generated before spawn, Add <!-- GENERATED by generate-agent.sh --> marker to all generated files, Wire --mode flag into go.md (plan/implement/review/qa/test modes per workflow stage), Integrate mode-profiles.json into resolve-agent-model.sh or go.md routing, Add BATS tests: all 27 combos produce valid output (no unreplaced placeholders, valid structure, expected sections), Add BATS tests: generated output matches regenerated output (no stale drift), Document template+overlay system in agents/templates/README and CLAUDE.md, Remove old hand-authored dept agent files after generated replacements are verified

**Success Criteria:**
- All 27 department agents are generated from templates+overlays (zero hand-authored dept agents remain)
- generate-agent.sh --dry-run output for each dept agent matches content of the live agents/yolo-*.md files
- FE/UX overlay JSON files contain ALL department-specific content from former hand-authored agents (diff = 0)
- regenerate-agents.sh --check passes in CI (no stale agents)
- go.md uses --mode flag when spawning agents, reducing per-invocation tokens 30-50%
- All generated files contain GENERATED marker comment
- Staleness detection warns on SessionStart when templates/overlays change
- BATS test suite covers all 27 agent combinations + mode filtering
- Existing tests pass with generated agents (no behavioral regression)

**Dependencies:** Phase 7

---

## Phase 9: Workflow Redundancy Audit & Token Optimization

**Goal:** Comprehensive audit and optimization of the YOLO engine for token efficiency, workflow redundancy elimination, and architecture clarity. Identify and remove redundant agents/flows, ensure every agent persona serves a distinct quality role, optimize script utilization for minimal context propagation via files (resumable on failure), cascade effort levels to all downstream agents, and create Mermaid architecture diagrams documenting the full design and flow for ongoing audit capability.

**Requirements:**
- Audit all ~38 agents for overlapping responsibilities and eliminate redundancy (QA/QA-Code secret scanning overlap, Critic/Scout role bleed, Architect/Lead authority overlap)
- Audit all ~80 scripts for duplicated logic and consolidate (validate-*.sh → single validator, dept-*.sh → single dept-state, route-*.sh → single router, qa-gate-*.sh → single gate)
- Enforce context budgets in compile-context.sh (invoke --measure from go.md, trim when over budget)
- Implement YOLO_AGENT_MODE in go.md (set env var before agent spawn for per-step template filtering)
- Cascade effort level to all downstream agents (not just Lead)
- Fix Documenter spawning to respect config enum (on_request/always/never), ensure output is consumed
- Consolidate config sources (defaults.json + mode-profiles.json) and fix inconsistencies
- Add cross-phase research persistence (research-archive.jsonl) to avoid re-research
- Add explicit multi-department handoff artifacts
- Persist escalation state for pause/resume
- Create comprehensive Mermaid architecture diagram (docs/ARCHITECTURE.md) documenting full agent hierarchy, workflow steps, data flow, department interactions, and decision points
- Audit all references/ docs for accuracy and remove outdated content
- Verify context-manifest.json completeness and add validation

**Success Criteria:**
- Agent redundancy eliminated: clear non-overlap matrix for all agent pairs (QA vs QA-Code, Critic vs Scout, etc.)
- Script count reduced by 30%+ through consolidation
- Context budgets enforced and measurable (--measure invoked per agent spawn)
- YOLO_AGENT_MODE functional (templates filtered per workflow step, 30% context reduction)
- Effort level cascades to all agents (turbo → turbo for Lead, Senior, Dev, QA)
- Mermaid architecture diagram exists with full workflow, agent hierarchy, and data flow
- All config sources consolidated with documented precedence
- Cross-phase research persistence eliminates redundant Scout invocations
- All reference docs accurate and non-redundant

**Dependencies:** Phase 8

---

## Phase 10: SQLite-Backed Artifact Store & Context Engine

**Goal:** Replace the file-based artifact system with a SQLite-backed store that eliminates redundant file reads, provides targeted context retrieval via bash scripts, and adds task queue semantics for agent coordination. Transform compile-context.sh from a file-scanning token-heavy operation into SQL-powered targeted queries. Agents call lightweight bash scripts instead of reading entire JSONL files, reducing per-agent context overhead by 80-95%.

**Requirements:**
- Design SQLite schema covering all 40+ artifact types (plans, summaries, decisions, research, gaps, critique, code-review, test-plan, test-results, escalation, handoffs)
- Build query scripts: get-task.sh, get-context.sh, get-phase.sh, get-summaries.sh, search-research.sh, check-phase-status.sh
- Build write scripts: insert-task.sh, complete-task.sh, append-finding.sh, update-status.sh
- Implement task queue semantics: next-task.sh (picks next unblocked task), next-review.sh (picks completed tasks for QA)
- Migrate compile-context.sh from file-scanning to SQLite queries (populate DB on artifact creation, query for context compilation)
- Update all agent prompts to call bash scripts instead of Read for artifact access
- Wire SQLite task queue into go.md and execute-protocol.md for agent coordination
- Add TOON output format for remaining eligible references/*.md files
- Implement WAL mode with proper locking for parallel agent access (15+ concurrent agents)
- Add FTS5 full-text search for research findings, decisions, and cross-phase knowledge retrieval
- Add token measurement: before/after per agent per phase for validated savings
- Eliminate ROADMAP.md triplication (parse once into DB, serve structured data to each role)
- Fix Architect budget overflow (targeted queries return only phase goals, not full roadmap)

**Success Criteria:**
- All artifact read/write operations go through SQLite scripts (zero direct JSONL file reads by agents)
- Per-agent context overhead reduced 80-95% (measured: Dev from 1,064 to ~75 tokens per plan read)
- ROADMAP.md read once per phase, not 3x (11,811 tokens → 1,200 tokens)
- Task queue functional: agents self-coordinate via next-task.sh/complete-task.sh
- Architect receives full context within budget (no lossy truncation)
- WAL mode handles 15+ concurrent agent reads/writes without contention
- FTS5 search replaces file-based grep for cross-phase research lookup
- Token measurement shows 50%+ reduction in total per-phase overhead vs Phase 9 baseline
- All existing workflow functionality preserved (plan, execute, verify, archive)

**Dependencies:** Phase 9
