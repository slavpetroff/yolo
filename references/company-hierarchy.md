# YOLO Company Hierarchy

Agent hierarchy, team structure, workflow, and escalation. Referenced by all agents and commands.

## Agent Roster

| Agent | Role | Model | Tools | Produces | Token Budget |
|-------|------|-------|-------|----------|-------------|
| yolo-analyze | Complexity Classifier / Intent Detector | Opus | Read,Glob,Grep | analysis.json | 1000 |
| yolo-po | Product Owner / Vision & Scope | Opus | Read,Glob,Grep,Write | scope-document.json, user_presentation | 3000 |
| yolo-questionary | Scope Clarification / Requirements Analyst | Sonnet | Read,Glob,Grep | scope_clarification JSON | 2000 |
| yolo-roadmap | Dependency & Roadmap Planner | Sonnet | Read,Glob,Grep,Write | roadmap_plan JSON | 2000 |
| yolo-critic | Brainstorm / Gap Analyst | Opus | Read,Glob,Grep,WebSearch,WebFetch | critique.jsonl | 4000 |
| yolo-architect | VP Eng / Solutions Architect | Opus | Read,Glob,Grep,Write,WebSearch,WebFetch | architecture.toon, ROADMAP.md | 5000 |
| yolo-lead | Tech Lead | Sonnet | Read,Glob,Grep,Write,Bash,WebFetch | plan.jsonl, orchestration | 3000 |
| yolo-senior | Senior Engineer | Opus | Read,Glob,Grep,Write,Edit,Bash | enriched plan specs (spec+ts), code-review.jsonl | 4000 |
| yolo-tester | TDD Test Author | Sonnet | Read,Glob,Grep,Write,Bash | test files, test-plan.jsonl | 3000 |
| yolo-dev | Junior Developer | Sonnet | All | source code, summary.jsonl | 2000 |
| yolo-qa | QA Lead | Sonnet | Read,Glob,Grep (read-only) | verification.jsonl | 2000 |
| yolo-qa-code | QA Engineer | Sonnet | Read,Glob,Grep,Bash | qa-code.jsonl | 3000 |
| yolo-security | Backend Security Engineer | Sonnet | Read,Glob,Grep,Bash,SendMessage | security-audit.jsonl | 3000 |
| yolo-fe-security | FE Security Reviewer | Sonnet | Read,Grep,Glob,Bash,SendMessage | security-audit.jsonl | 3000 |
| yolo-ux-security | UX Security Reviewer | Sonnet | Read,Grep,Glob,SendMessage | security-audit.jsonl | 2000 |
| yolo-documenter | Backend Documenter | Haiku | Read,Glob,Grep,Write,Bash | docs.jsonl | 2000 |
| yolo-fe-documenter | FE Documenter | Haiku | Read,Glob,Grep,Write | docs.jsonl | 2000 |
| yolo-ux-documenter | UX Documenter | Haiku | Read,Glob,Grep,Write | docs.jsonl | 2000 |
| yolo-scout | Research Analyst | Haiku | Read,Glob,Grep,WebSearch,WebFetch | research.jsonl | 1000 |
| yolo-debugger | Incident Responder | Sonnet | All | debug-report.jsonl | 3000 |
| yolo-integration-gate | Integration Gate / Cross-Dept Validator | Sonnet | Read,Glob,Grep | integration-gate-result.jsonl | 2000 |

## Team Structure

### Planning Team
Agents: Analyze, PO, Questionary, Roadmap, Critic, Architect, Scout, Lead
Active during: Analysis, Product Ownership, Scope Clarification, Roadmap Planning, Critique, Scope, Research, Plan
Handoff: analysis.json → PO routing, PO → Questionary (scope_clarification, max 3 rounds) → PO → Roadmap (roadmap_plan) → PO (scope-document.json) → Critic, critique.jsonl → Architect, architecture.toon → Lead, research.jsonl → Lead
PO layer optional: when po.enabled=false, Analyze routes directly to Critic → Architect → Lead (backward compatible)

### Execution Team
Agents: Senior, Tester, Dev (x1-3), Debugger (on-call)
Active during: Design Review, Test Authoring (RED), Implementation
Handoff: enriched plan.jsonl (spec+ts) → Tester → Dev, code commits → Senior

### Quality Team
Agents: QA Lead, QA Code, Senior (escalation), Security Reviewers (per-dept: Security, FE Security, UX Security)
Active during: Code Review, QA, Security
Handoff: code-review.jsonl → Lead, verification.jsonl → Lead, security-audit.jsonl → Lead

### R&D Pipeline
Agents: PO, Questionary, Roadmap, Critic, Scout, Architect
Active during: Product Ownership (after Analyze), Scope Clarification, Roadmap Planning, Critique (Step 1), Research (Step 2), Architecture (Step 3)
Handoff: analysis.json -> PO(scope-document.json) -> Critic, critique.jsonl (critical/major) -> Scout research directives -> research.jsonl -> Architect
Stage-gate: Architect->Lead handoff uses Go/Recycle/Kill model. See @references/rnd-handoff-protocol.md.

### Integration Pipeline
Agents: Integration Gate, PO (Mode 4 QA), Owner (Delivery)
Active during: Post-Security (Step 11.5), Final Delivery (Step 12)
Handoff: integration-gate-result.jsonl → Lead/Owner. PO QA verdict (po-qa-verdict.jsonl) → Owner. Owner Delivery mode presents final results to user.
Flow: After Security (Step 10) passes → Integration Gate validates cross-dept convergence (API contracts, design sync, handoffs, test results) → PO QA verifies scope alignment against scope-document.json → Owner Delivery presents to user.
Multi-dept only: Integration Gate is skipped in single-department mode. PO QA requires po.enabled=true.

## 11-Step Workflow

Each phase follows this cadence. Full protocol with entry/exit gates: see @references/execute-protocol.md.

| Step | Agent | Input | Output | Commit | Skip |
|------|-------|-------|--------|--------|------|
| 1 | Critic | reqs + PROJECT + codebase | critique.jsonl | `docs({phase}): critique and gap analysis` | turbo, exists |
| 2 | Scout | critique (critical/major) + reqs + codebase | research.jsonl | `docs({phase}): research findings` | turbo |
| 3 | Architect | reqs + codebase + critique | architecture.toon | `docs({phase}): architecture design` | exists |
| 4 | Lead | architecture.toon + reqs | plan.jsonl | `docs({phase}): plan {NN-MM}` | -- |
| 5 | Senior | plan + architecture + codebase | enriched plan (spec+ts) | `docs({phase}): enrich plan {NN-MM} specs` | -- |
| 6 | Tester | enriched plan (ts fields) | test files + test-plan.jsonl | `test({phase}): RED phase tests` | turbo, no ts |
| 7 | Dev | enriched plan + test files | code + summary.jsonl | `{type}({phase}-{plan}): {task}` | -- |
| 8 | Senior | git diff + plan + tests | code-review.jsonl | `docs({phase}): code review {NN-MM}` | -- |
| 8.5 | Documenter | code + plan + architecture | docs.jsonl | `docs({phase}): documentation` | config-gated |
| 9 | QA Lead + Code | plan + summary + artifacts | verification + qa-code.jsonl | `docs({phase}): verification results` | --skip-qa, turbo |
| 10 | Security | commits + deps | security-audit.jsonl | `docs({phase}): security audit` | --skip-security |
| 11 | Lead | all artifacts | state.json + ROADMAP.md | `chore(state): phase {N} complete` | -- |

## Escalation Chain (STRICT — NO LEVEL SKIPPING)

### Primary Chain

```
Dev → Senior → Lead → Architect → User                  (single-department)
Dept Dev → Dept Senior → Dept Lead → Dept Architect → Owner → User  (multi-department)
```

### Full Escalation Table

| Agent | Escalates to | Trigger | Notes |
|-------|-------------|---------|-------|
| Dev | Senior | Blocker, spec unclear, 2 task failures, architectural issue | NEVER contacts Lead or Architect |
| Senior | Lead | Can't resolve Dev blocker, design conflict, code review cycle 2 fail | NEVER contacts Architect directly |
| Lead | Architect | Can't resolve Senior escalation, design problem, cross-phase issue | NEVER contacts User directly |
| Architect | User | Design-level decision needed, scope change required | Final escalation point |
| Tester | Senior | `ts` field unclear, tests pass unexpectedly | Via Senior, NOT Lead |
| QA Lead | Lead | Verification findings, FAIL result | Lead assigns remediation |
| QA Code | Lead | Critical/major findings, FAIL result | Lead routes to Senior → Dev |
| Security | Lead (FAIL → User) | Findings to report | FAIL = HARD STOP → User only (per-dept: Security→Lead, FE Security→FE Lead, UX Security→UX Lead) |
| Documenter | Lead | Findings only | Per-dept: Documenter→Lead, FE Documenter→FE Lead, UX Documenter→UX Lead |
| Scout | Lead | Cannot find information, conflicting sources | Advisory only |
| Debugger | Lead | Investigation complete, fix recommendation | Lead decides action |
| Critic | Lead | Findings are advisory | Lead forwards to Architect |

### Rules

1. **Each agent escalates ONLY to their direct report-to.** No skipping levels.
2. **If report-to cannot resolve → they escalate to THEIR report-to.** Chain propagates upward.
3. **Dev NEVER contacts Lead, Architect, or User.** Senior is Dev's single contact.
4. **QA/Tester NEVER contact Architect.** Findings route through Lead.
5. **Only Owner/go.md talks to the User.** In single-dept mode, Architect escalates to go.md (which acts as Owner proxy) → User. In multi-dept mode, Architect escalates to Owner → User. No other agent communicates with the user directly.
6. **Only Security FAIL bypasses chain** → User (via go.md/Owner).
7. **Escalation includes evidence.** Use `escalation` handoff schema with issue + evidence + recommendation.
8. **Stay in your lane.** Each agent decides ONLY within their Decision Authority (see matrix above). Out-of-scope questions escalate immediately.

### QA Remediation Chain

```
QA Code FAIL      → Lead assigns → Senior re-specs → Dev fixes → QA re-verifies
2nd QA FAIL       → Lead assigns → Senior reviews approach
3rd QA FAIL       → Lead escalates → Architect re-evaluates design
```

### Code Review Chain

```
Senior: changes_requested → classify as Minor or Major
Minor only (nits/style)   → Dev fixes → auto-approve (no cycle 2)
Major findings            → Dev fixes → Senior re-reviews (cycle 2)
Cycle 2 fail              → Senior escalates to Lead
Lead decides              → Accept with known issues OR escalate to Architect
```

**Change classification (per D4):**
- **Minor**: Nits, style, naming, formatting. Auto-approve after cycle 1 fix if only minor findings.
- **Major**: Logic errors, missing error handling, architecture violations. Require cycle 2 re-review.

**Collaborative relationship**: Senior sends suggestions; Dev retains decision power within spec. Dev can document rationale for disagreement on findings.

**Phase 4 hooks**: Metric collection points (cycle_count, finding_severity_distribution, time_per_cycle, escalation_triggered) defined for Phase 4 continuous QA instrumentation.

See @references/execute-protocol.md ## Change Management for full protocol.

### Escalation Round-Trip (Full Bidirectional Flow)

Complete path for a Dev blocker that requires user input and the resolution flowing back down.

**UPWARD PATH (Blocker to User):**

```
Dev          -> Senior       -> Lead         -> Architect/Owner -> go.md -> User
(dev_blocker)  (escalation)   (escalation)    (structured opts)   (AskUserQuestion)
```

| Level | Agent | Transformation | Output |
|-------|-------|---------------|--------|
| 1 | Dev | Reports blocker with evidence of what was tried | `dev_blocker` schema |
| 2 | Senior | Adds spec context, attempts resolution. If cannot: adds assessment | `escalation` schema to Lead |
| 3 | Lead | Checks decision authority. If beyond scope: adds Lead assessment | `escalation` schema to Architect/Owner |
| 4 | Architect | Evaluates design impact, constructs 2-3 concrete options | Structured escalation with options array |
| 4a | Owner (multi-dept) | Checks cross-department implications, routes to go.md | Escalation context to go.md |
| 5 | go.md | Formats for user, presents via AskUserQuestion | User sees blocker + options |

**DOWNWARD PATH (Resolution to Dev):**

```
User -> go.md -> Owner/Architect -> Lead         -> Senior       -> Dev
(choice) (escalation_resolution)   (forward)       (translate)     (resume)
```

| Level | Agent | Transformation | Output |
|-------|-------|---------------|--------|
| 1 | go.md | Packages user choice as escalation_resolution | `escalation_resolution` schema |
| 2 | Owner (multi-dept) | Adds strategic context, identifies target dept Lead | Enriched resolution |
| 2a | Architect (single-dept) | Updates architecture.toon if decision affects design | Resolution + architecture update |
| 3 | Lead | Routes to originating Senior, updates .execution-state.json | Forward resolution to Senior |
| 4 | Senior | Translates resolution to Dev instructions: spec update or code_review_changes | `code_review_changes` schema |
| 5 | Dev | Applies resolution, resumes blocked task | Commit with escalation reference |

**Verification at each level:** Each agent confirms the resolution was received and acted on by the next level down before marking its part complete. Senior waits for Dev's dev_progress. Lead waits for Senior's confirmation. The escalation entry in .execution-state.json is only marked "resolved" after Dev resumes.

**Timeout protection:** If any level does not respond within `escalation.timeout_seconds`, auto-escalation fires to the next level up. Max `escalation.max_round_trips` cycles per escalation id.

## Decision Authority Matrix (STRICT — STAY IN YOUR LANE)

Each agent has a defined area of capability. Questions or decisions outside that area MUST escalate up the chain. The receiving agent either handles it (if in their area) or escalates further. Escalation carries context from the lower agent upward.

| Agent | CAN Decide (Area of Authority) | MUST Escalate (Out of Scope) |
|-------|-------------------------------|------------------------------|
| Analyze | Complexity classification (trivial/medium/high), department detection, intent classification, suggested routing path | Ambiguous intent (confidence < 0.6), scope changes, architecture decisions |
| PO | Scope boundaries (in/out), acceptance criteria, milestone decomposition, user presentation formatting, scope-document.json content | Architecture decisions, technology choices, implementation details, budget/timeline constraints (→ User) |
| Questionary | Question selection strategy, clarification round structure, when requirements are sufficient, scope_clarification content | Scope expansion beyond original intent (→ PO), architecture questions (→ Architect via PO) |
| Roadmap | Phase ordering, dependency graph construction, milestone grouping, roadmap_plan content | Scope changes (→ PO), architecture decisions (→ Architect), priority changes (→ PO → User) |
| Dev | Implementation details within spec (variable names, loop structure, error messages), which library API to call per spec, test fixes within spec boundaries | Spec ambiguity, missing requirements, architectural choices, new file/module creation not in spec, performance tradeoffs, API design |
| Tester | Test structure, mock strategy, assertion approach, test naming | Test scope beyond `ts` field, testing infrastructure changes, whether a feature needs tests |
| Senior | Spec enrichment details, code review decisions (approve/request changes), implementation patterns within architecture, test spec design | Architecture changes, new dependencies, scope changes, cross-phase impacts, design pattern choices that affect architecture |
| Lead | Plan decomposition, task ordering, wave grouping, resource allocation, which tasks to parallelize, remediation assignment routing | Architecture decisions, technology choices, scope changes, cross-department coordination, user-facing decisions |
| Architect | Technology choices, design patterns, system architecture, dependency decisions, performance strategy, addressing critique findings | Scope changes (add/remove features), budget/timeline decisions, user preference questions, business priority changes |
| QA Lead | Pass/fail determination, finding severity classification, whether gaps need remediation | Whether to ship with known issues (→ Lead), scope reduction to pass QA (→ Lead) |
| QA Code | Test execution, lint/coverage assessment, pattern compliance | Changing test expectations, modifying source code, architectural feedback (→ Lead) |
| Security | Vulnerability severity, compliance assessment, audit pass/fail | FAIL = hard STOP → User. Remediation approach (→ Lead → Senior) |
| Critic | Gap identification, risk assessment, alternative suggestions | All findings are advisory — Lead decides what to act on |
| Scout | Research methodology, source selection, information synthesis | All findings are advisory — Lead decides relevance |
| Debugger | Investigation methodology, evidence gathering, root cause diagnosis, fix recommendation | Whether to apply fix (→ Lead decides), scope of fix (→ Senior if architectural) |
| Documenter | Doc structure, content selection, formatting, inline doc generation | Scope changes, architecture docs, API contract docs (→ Lead) |
| Owner | Cross-department priority, conflict resolution, ship/hold decisions, department dispatch order | Scope changes, new features, budget decisions (→ User) |

**Rule: If a question doesn't fit your "CAN Decide" column, escalate immediately. Include the question, your context, and a recommendation. Never guess or make out-of-scope decisions.**

**Escalation carries context upward:** When escalating, the lower agent provides: (1) the question/blocker, (2) relevant context from their work, (3) their recommendation if they have one. The receiving agent uses this context plus their own broader context to make the decision, then pushes the answer back down.

## Context Isolation

### Per-Agent Context Scoping (within a department)

Each agent level receives progressively LESS context. This prevents noise and enforces clean delegation:

| Agent | Receives | NEVER receives |
|-------|----------|----------------|
| Lead | Dept CONTEXT + ROADMAP + REQUIREMENTS + architecture.toon + prior summaries + codebase mapping | Other dept contexts, code-review.jsonl, gaps.jsonl, security-audit.jsonl |
| Architect | Dept CONTEXT + REQUIREMENTS + critique.jsonl + codebase mapping + research.jsonl | Other dept contexts, implementation code, QA artifacts |
| Senior (Design Review) | architecture.toon + plan.jsonl tasks + codebase patterns + critique.jsonl | Full CONTEXT file directly (only via architecture.toon), other dept artifacts |
| Senior (Code Review) | plan.jsonl + git diff + test-plan.jsonl | CONTEXT files, ROADMAP directly |
| Tester | Enriched plan.jsonl (tasks with `ts` field) + codebase patterns | CONTEXT files, architecture.toon, critique.jsonl |
| Dev | Enriched plan.jsonl (`spec` field ONLY) + test files (RED targets) | architecture.toon, CONTEXT files, critique.jsonl, ROADMAP, REQUIREMENTS |
| QA Lead | plan.jsonl + summary.jsonl + .ctx-qa.toon | Source code modifications, CONTEXT files |
| QA Code | summary.jsonl (file list) + test-plan.jsonl + .ctx-qa-code.toon | CONTEXT files, architecture.toon |

**Key principle:** Dev receives ZERO creative context. The `spec` field IS the complete instruction set.

### Cross-Department Context Isolation (multi-department mode)

When multiple departments are active, context is split at the Owner level:

| Department | Receives | NEVER receives |
|------------|----------|----------------|
| Backend | `{phase}-CONTEXT-backend.md` | UX context, FE context, design tokens, component specs |
| UI/UX | `{phase}-CONTEXT-uiux.md` | BE context, FE context, API contracts |
| Frontend | `{phase}-CONTEXT-frontend.md` + UX handoff artifacts | BE context, UX internal plans/architecture |

Backend agents NEVER read UI/UX artifacts directly. Frontend relays relevant information via handoff artifacts only.

### Escalation Restores Context

When escalation reaches Owner, Owner clarifies with user and pushes corrected context back DOWN through the same chain (Owner→Architect→Lead→Senior→Dev). Resolution comes as updated artifacts, never as raw context dumps. No level is ever skipped.

## Commit-Every-Artifact Protocol

Every persistent artifact gets committed immediately after creation:

| Step | Agent | Commits |
|------|-------|---------|
| Critique | Critic (via Lead) | critique.jsonl |
| Architecture | Architect | architecture.toon |
| Planning | Lead | {plan}.plan.jsonl |
| Design Review | Senior | enriched plan.jsonl (spec + ts) |
| Test Authoring | Tester | test files + test-plan.jsonl |
| Implementation | Dev | source code per task + summary.jsonl |
| Code Review | Senior | code-review.jsonl |
| Documentation | Documenter (config-gated) | docs.jsonl |
| QA | QA Lead + QA Code | verification.jsonl + qa-code.jsonl |
| Security | Security | security-audit.jsonl |
| Sign-off | Lead | state.json + ROADMAP.md |

Format: `docs({phase}): {artifact}` except Dev source: `{type}({phase}-{plan}): {task}`

## Multi-Department Structure

When `departments.frontend` or `departments.uiux` is true in config, YOLO operates as a multi-department company:

| Department | Agents | Protocol File |
|------------|--------|---------------|
| Backend | architect, lead, senior, dev, tester, qa, qa-code, security, documenter (9) | `references/departments/backend.toon` |
| Frontend | fe-architect, fe-lead, fe-senior, fe-dev, fe-tester, fe-qa, fe-qa-code, fe-security, fe-documenter (9) | `references/departments/frontend.toon` |
| UI/UX | ux-architect, ux-lead, ux-senior, ux-dev, ux-tester, ux-qa, ux-qa-code, ux-security, ux-documenter (9) | `references/departments/uiux.toon` |
| Shared | owner, critic, scout, debugger, integration-gate (5) | `references/departments/shared.toon` |

**Total: ~36 agents across 4 groups + PO layer.**

Each department runs the same 11-step workflow independently. Cross-department coordination follows `references/cross-team-protocol.md`. Full multi-department orchestration: `references/multi-dept-protocol.md`.

**Parallel execution model:** When `department_workflow` = "parallel", department Leads are spawned as **background Task subagents** (`run_in_background=true`). go.md orchestrates wave-based dispatch: UX first (if active), then FE + BE in parallel after the UX handoff gate passes. Each Lead runs its full 11-step workflow using foreground Task subagents internally. This uses the proven Task tool architecture -- no Teammate API dependency.

**File-based coordination:** Cross-department synchronization uses file-based gates in the phase directory: `.dept-status-{dept}.json` for per-department status tracking, `.handoff-*` sentinel files for handoff gates, and `.phase-orchestration.json` for master orchestration state. All writes are atomic via flock locking in `scripts/dept-status.sh`. See `references/multi-dept-protocol.md` for coordination file schemas and `references/cross-team-protocol.md` for gate validation commands.

### Department Escalation (STRICT)

```
Dept Dev → Dept Senior → Dept Lead → Dept Architect → Owner → User
```

Cross-department communication goes through department Leads only. Individual agents NEVER message across department boundaries.

## Resume Protocol

On session re-entry (session-start.sh):
1. Read state.json → exact phase, step, status
2. Read .execution-state.json → which plans done/pending
3. Check git log → correlate commits with tasks
4. Re-compile .ctx-{role}.toon from JSONL artifacts on disk
5. Resume at exact point — everything is committed

## Command Routing Table

Every command enters through go.md (Owner proxy) and dispatches through the company hierarchy. No command spawns specialist agents directly.

| Command | Entry Point | Primary Spawn | Hierarchy Chain | Escalation Path |
|---------|-------------|---------------|-----------------|------------------|
| /yolo:go (analyze) | go.md | Analyze | go.md -> Analyze -> routing decision (trivial/medium/high) | Ambiguous intent (confidence < 0.6) → go.md prompts user |
| /yolo:go (execute) | go.md | PO, Critic, Architect, Lead | go.md -> Analyze -> PO -> Questionary -> Roadmap -> Critic -> Architect -> Lead -> Senior -> Tester -> Dev -> QA -> Security -> Sign-off | Per-step escalation (see 11-Step Workflow above) |
| /yolo:debug | go.md | Lead | go.md -> Lead -> Debugger(s) | Debugger -> Lead -> Architect (if >3 files or interface change) |
| /yolo:fix | go.md | Lead | go.md -> Lead -> {trivial: Dev, needs-spec: Senior -> Dev} | Dev -> Senior -> Lead -> go.md (scope too large -> /yolo:go) |
| /yolo:research | go.md | Lead | go.md -> Lead -> Scout(s) | Scout -> Lead -> go.md (contradictions or architecture impact) |
| /yolo:qa | go.md | Lead | go.md -> Lead -> QA Lead + QA Code | QA -> Lead -> Senior -> Architect (after 3rd failure) |

**Rules:**
1. go.md is always the entry point. It acts as the Owner proxy for user communication.
2. Lead is the primary dispatcher for all specialist commands (debug, fix, research, qa).
3. Specialists (Debugger, Scout, QA, Dev) are spawned BY Lead, never directly by go.md.
4. Escalation follows the chain strictly -- no level skipping.
5. Only go.md talks to the user. No spawned agent communicates with the user directly.
