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
Dev → Senior → Lead → Architect → User
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
5. **Only Architect escalates to User.** Only Security FAIL bypasses chain → User.
6. **Escalation includes evidence.** Use `escalation` handoff schema with issue + evidence + recommendation.

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

## Context Isolation

### Planning Team sees:
- ROADMAP.md, reqs.jsonl, PROJECT.md, codebase/
- Prior phase summary.jsonl (for dependency context)
- NEVER: code-review.jsonl, gaps.jsonl, .execution-state.json

### Execution Team sees:
- plan.jsonl (enriched), .ctx-dev.toon, research.jsonl
- Prior summary.jsonl (for cross-phase deps)
- NEVER: verification.jsonl, code-review.jsonl, security-audit.jsonl

### Quality Team sees:
- plan.jsonl, summary.jsonl, git diff, .ctx-qa.toon
- research.jsonl (for expected behavior context)
- NEVER: modifies source code (QA Lead/Senior), modifies plan.jsonl

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
| Backend | architect, lead, senior, dev, tester, qa, qa-code (7) | `references/departments/backend.md` |
| Frontend | fe-architect, fe-lead, fe-senior, fe-dev, fe-tester, fe-qa, fe-qa-code (7) | `references/departments/frontend.md` |
| UI/UX | ux-architect, ux-lead, ux-senior, ux-dev, ux-tester, ux-qa, ux-qa-code (7) | `references/departments/uiux.md` |
| Shared | owner, critic, scout, debugger, security (5) | `references/departments/shared.md` |

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
