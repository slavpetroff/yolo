# YOLO Company Hierarchy

Agent hierarchy, team structure, workflow, and escalation. Referenced by all agents and commands.

## Agent Roster

| Agent | Role | Model | Tools | Produces | Token Budget |
|-------|------|-------|-------|----------|-------------|
| yolo-critic | Brainstorm / Gap Analyst | Opus | Read,Glob,Grep,WebSearch,WebFetch | critique.jsonl | 4000 |
| yolo-architect | VP Eng / Solutions Architect | Opus | Read,Glob,Grep,Write,WebSearch,WebFetch | architecture.toon, ROADMAP.md | 5000 |
| yolo-lead | Tech Lead | Sonnet | Read,Glob,Grep,Write,Bash,WebFetch | plan.jsonl, orchestration | 3000 |
| yolo-senior | Senior Engineer | Opus | Read,Glob,Grep,Write,Edit,Bash | enriched plan specs (spec+ts), code-review.jsonl | 4000 |
| yolo-tester | TDD Test Author | Sonnet | Read,Glob,Grep,Write,Bash | test files, test-plan.jsonl | 3000 |
| yolo-dev | Junior Developer | Sonnet | All | source code, summary.jsonl | 2000 |
| yolo-qa | QA Lead | Sonnet | Read,Glob,Grep (read-only) | verification.jsonl | 2000 |
| yolo-qa-code | QA Engineer | Sonnet | Read,Glob,Grep,Bash | qa-code.jsonl | 3000 |
| yolo-security | Security Engineer | Sonnet | Read,Glob,Grep,Bash | security-audit.jsonl | 3000 |
| yolo-scout | Research Analyst | Haiku | Read,Glob,Grep,WebSearch,WebFetch | research.jsonl | 1000 |
| yolo-debugger | Incident Responder | Sonnet | All | debug-report.jsonl | 3000 |

## Team Structure

### Planning Team
Agents: Critic, Architect, Scout, Lead
Active during: Critique, Scope, Research, Plan
Handoff: critique.jsonl → Architect, architecture.toon → Lead, research.jsonl → Lead

### Execution Team
Agents: Senior, Tester, Dev (x1-3), Debugger (on-call)
Active during: Design Review, Test Authoring (RED), Implementation
Handoff: enriched plan.jsonl (spec+ts) → Tester → Dev, code commits → Senior

### Quality Team
Agents: QA Lead, QA Code, Senior (escalation)
Active during: Code Review, QA, Security
Handoff: code-review.jsonl → Lead, verification.jsonl → Lead

## 10-Step Workflow

Each phase follows this cadence:

### Step 1: Critique / Brainstorm (Critic)
- Input: reqs.jsonl + PROJECT.md + codebase/ + research.jsonl
- Does: Challenges assumptions, identifies gaps, brainstorms improvements
- Output: critique.jsonl (questions, gaps, risks, alternatives)
- Commit: `docs({phase}): critique and gap analysis`
- SKIP: turbo effort. FAST: critical findings only.

### Step 2: Architecture (Architect)
- Input: reqs.jsonl + codebase/ + research.jsonl + critique.jsonl
- Does: R&D, evaluates approaches, tech decisions, addresses critique findings
- Output: architecture.toon (per phase), updates ROADMAP.md, updates critique.jsonl `st` field
- Commit: `docs({phase}): architecture design`

### Step 3: Planning (Lead)
- Input: architecture.toon + reqs.jsonl
- Does: Feasibility check, risk assessment, plan decomposition
- Output: {NN-MM}.plan.jsonl (high-level tasks, no specs yet)
- Commit: `docs({phase}): plan {NN-MM}`

### Step 4: Design Review (Senior)
- Input: plan.jsonl + architecture.toon + critique.jsonl + codebase patterns
- Does: Enriches each task with EXACT implementation specs AND test specs
- Output: plan.jsonl tasks gain `spec` field (implementation) + `ts` field (test specification)
- Commit: `docs({phase}): enrich plan {NN-MM} specs`
- KEY: After this step, Dev needs ZERO creative decisions, Tester knows exactly what to test

### Step 5: Test Authoring — RED Phase (Tester)
- Input: enriched plan.jsonl (tasks with `ts` field)
- Does: Writes failing test files per `ts` spec. Confirms ALL tests FAIL.
- Output: test files + test-plan.jsonl
- Commit: `test({phase}): RED phase tests for plan {NN-MM}`
- SKIP: turbo effort, or no `ts` fields in plan.

### Step 6: Implementation (Dev)
- Input: enriched plan.jsonl + test files (RED targets)
- Does: Verifies RED → implements per spec → verifies GREEN. No design calls.
- Rules: Blocked → Senior (not Lead). Tests pass before implementing → STOP + escalate. 3 GREEN failures → escalate.
- Output: code commits (one per task) + summary.jsonl (with `tst` field)
- Commit: `{type}({phase}-{plan}): {task}` per task, `docs({phase}): summary {NN-MM}`

### Step 7: Code Review (Senior)
- Input: git diff of plan commits + plan.jsonl + test-plan.jsonl
- Does: Reviews adherence to spec, quality, patterns, TDD compliance
- Output: code-review.jsonl (approve | request_changes, with `tdd` field)
- If changes needed → Dev re-implements per feedback. Max 2 cycles → escalate to Lead.
- Commit: `docs({phase}): code review {NN-MM}`

### Step 8: QA (QA Lead + QA Code)
- QA Lead: Plan verification — must_haves, criteria, requirement traceability
- QA Code: TDD compliance (Phase 0) + tests, lint, coverage, regression, patterns
- Output: verification.jsonl (plan-level) + qa-code.jsonl (code-level, with `tdd` coverage)
- PASS → Step 9. PARTIAL → gaps.jsonl → Dev fixes → re-verify (max 2). FAIL → remediation plan → Senior re-specs. 2x FAIL → Architect re-evaluates design.
- Commit: `docs({phase}): verification results`

### Step 9: Security Audit (Security, optional via config)
- Input: all phase commits + dependency manifest
- Does: OWASP top 10, secrets scan, dependency vulnerabilities
- Output: security-audit.jsonl
- FAIL → hard STOP (user --force to override)
- Commit: `docs({phase}): security audit`

### Step 10: Sign-off (Lead)
- Reviews: All artifacts — critique, code-review, verification, qa-code, security, summary
- Decision: SHIP (next phase) or HOLD (remediation instructions)
- Updates: ROADMAP.md (user-facing) + state.json (machine-readable)
- Commit: `chore(state): phase {N} complete`

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
| Security | Lead (FAIL → User) | Findings to report | FAIL = HARD STOP → User only |
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
Senior: changes_requested → Dev fixes per exact instructions
Cycle 2 fail              → Senior escalates to Lead
Lead decides              → Accept with known issues OR escalate to Architect
```

## Decision Authority Matrix (STRICT — STAY IN YOUR LANE)

Each agent has a defined area of capability. Questions or decisions outside that area MUST escalate up the chain. The receiving agent either handles it (if in their area) or escalates further. Escalation carries context from the lower agent upward.

| Agent | CAN Decide (Area of Authority) | MUST Escalate (Out of Scope) |
|-------|-------------------------------|------------------------------|
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
| QA | QA Lead + QA Code | verification.jsonl + qa-code.jsonl |
| Security | Security | security-audit.jsonl |
| Sign-off | Lead | state.json + ROADMAP.md |

Format: `docs({phase}): {artifact}` except Dev source: `{type}({phase}-{plan}): {task}`

## Multi-Department Structure

When `departments.frontend` or `departments.uiux` is true in config, YOLO operates as a multi-department company:

| Department | Agents | Protocol File |
|------------|--------|---------------|
| Backend | architect, lead, senior, dev, tester, qa, qa-code (7) | `references/departments/backend.toon` |
| Frontend | fe-architect, fe-lead, fe-senior, fe-dev, fe-tester, fe-qa, fe-qa-code (7) | `references/departments/frontend.toon` |
| UI/UX | ux-architect, ux-lead, ux-senior, ux-dev, ux-tester, ux-qa, ux-qa-code (7) | `references/departments/uiux.toon` |
| Shared | owner, critic, scout, debugger, security (5) | `references/departments/shared.toon` |

**Total: 26 agents across 4 groups.**

Each department runs the same 10-step workflow independently. Cross-department coordination follows `references/cross-team-protocol.md`. Full multi-department orchestration: `references/multi-dept-protocol.md`.

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
