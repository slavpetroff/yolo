# VBW Company Hierarchy

Agent hierarchy, team structure, workflow, and escalation. Referenced by all agents and commands.

## Agent Roster

| Agent | Role | Model | Tools | Produces | Token Budget |
|-------|------|-------|-------|----------|-------------|
| vbw-architect | VP Eng / Solutions Architect | Opus | Read,Glob,Grep,Write,WebSearch,WebFetch | architecture.toon, ROADMAP.md | 5000 |
| vbw-lead | Tech Lead | Sonnet | Read,Glob,Grep,Write,Bash,WebFetch | plan.jsonl, orchestration | 3000 |
| vbw-senior | Senior Engineer | Opus | Read,Glob,Grep,Write,Edit,Bash | enriched plan specs, code-review.jsonl | 4000 |
| vbw-dev | Junior Developer | Sonnet | All | source code, summary.jsonl | 2000 |
| vbw-qa | QA Lead | Sonnet | Read,Glob,Grep (read-only) | verification.jsonl | 2000 |
| vbw-qa-code | QA Engineer | Sonnet | Read,Glob,Grep,Bash | qa-code.jsonl | 3000 |
| vbw-security | Security Engineer | Sonnet | Read,Glob,Grep,Bash | security-audit.jsonl | 3000 |
| vbw-scout | Research Analyst | Haiku | Read,Glob,Grep,WebSearch,WebFetch | research.jsonl | 1000 |
| vbw-debugger | Incident Responder | Sonnet | All | debug-report.jsonl | 3000 |

## Team Structure

### Planning Team
Agents: Architect, Scout, Lead
Active during: Scope, Research, Plan
Handoff: architecture.toon → Lead, research.jsonl → Lead

### Execution Team
Agents: Senior, Dev (x1-3), Debugger (on-call)
Active during: Design Review, Implementation
Handoff: enriched plan.jsonl → Dev, code commits → Senior

### Quality Team
Agents: QA Lead, QA Code, Senior (escalation)
Active during: Code Review, QA, Security
Handoff: code-review.jsonl → Lead, verification.jsonl → Lead

## 8-Step Workflow

Each phase follows this cadence:

### Step 1: Architecture (Architect)
- Input: reqs.jsonl + codebase/ + research.jsonl
- Does: R&D, evaluates approaches, tech decisions, phase decomposition
- Output: architecture.toon (per phase), updates ROADMAP.md
- Commit: `docs({phase}): architecture design`

### Step 2: Planning (Lead)
- Input: architecture.toon + reqs.jsonl
- Does: Feasibility check, risk assessment, plan decomposition
- Output: {NN-MM}.plan.jsonl (high-level tasks, no specs yet)
- Commit: `docs({phase}): plan {NN-MM}`

### Step 3: Design Review (Senior)
- Input: plan.jsonl + architecture.toon + codebase patterns
- Does: Enriches each task with EXACT implementation specs
- Output: plan.jsonl tasks gain `spec` field with file paths, function signatures, imports, error handling, edge cases
- Commit: `docs({phase}): enrich plan {NN-MM} specs`
- KEY: After this step, Dev needs ZERO creative decisions

### Step 4: Implementation (Dev)
- Input: ONLY enriched plan.jsonl (2000 token budget)
- Does: Implements exactly as spec'd. No design calls.
- Rules: Blocked → Senior (not Lead). Spec unclear → Senior clarifies. Architectural issue → STOP + escalate.
- Output: code commits (one per task) + summary.jsonl
- Commit: `{type}({phase}-{plan}): {task}` per task, `docs({phase}): summary {NN-MM}`

### Step 5: Code Review (Senior)
- Input: git diff of plan commits + plan.jsonl
- Does: Reviews adherence to spec, quality, patterns, naming, error handling
- Output: code-review.jsonl (approve | request_changes)
- If changes needed → Dev re-implements per feedback. Max 2 cycles → escalate to Lead.
- Commit: `docs({phase}): code review {NN-MM}`

### Step 6: QA (QA Lead + QA Code)
- QA Lead: Plan verification — must_haves, criteria, requirement traceability
- QA Code: Code verification — tests, lint, coverage, regression, patterns
- Output: verification.jsonl (plan-level) + qa-code.jsonl (code-level)
- PASS → Step 8. PARTIAL → gaps.jsonl → Dev fixes → re-verify (max 2). FAIL → remediation plan → Senior re-specs. 2x FAIL → Architect re-evaluates design.
- Commit: `docs({phase}): verification results`

### Step 7: Security Audit (Security, optional via config)
- Input: all phase commits + dependency manifest
- Does: OWASP top 10, secrets scan, dependency vulnerabilities
- Output: security-audit.jsonl
- FAIL → hard STOP (user --force to override)
- Commit: `docs({phase}): security audit`

### Step 8: Sign-off (Lead)
- Reviews: All artifacts — code-review, verification, security, summary
- Decision: SHIP (next phase) or HOLD (remediation instructions)
- Updates: ROADMAP.md (user-facing) + state.json (machine-readable)
- Commit: `chore(state): phase {N} complete`

## Escalation Chain

```
Dev blocked        → Senior (immediate, same team)
Senior can't fix   → Lead (coordination issue)
Lead can't fix     → Architect (design problem)

QA Code fails      → Dev fixes (Senior re-specs if needed)
2nd QA fail        → Senior reviews approach
3rd QA fail        → Architect re-evaluates design

Security fail      → HARD STOP → User decides
```

No agent skips a level. Dev never contacts Architect. QA findings route through Lead who assigns remediation.

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
| Architecture | Architect | architecture.toon |
| Planning | Lead | {plan}.plan.jsonl |
| Design Review | Senior | enriched plan.jsonl |
| Implementation | Dev | source code per task + summary.jsonl |
| Code Review | Senior | code-review.jsonl |
| QA | QA Lead + QA Code | verification.jsonl + qa-code.jsonl |
| Security | Security | security-audit.jsonl |
| Sign-off | Lead | state.json + ROADMAP.md |

Format: `docs({phase}): {artifact}` except Dev source: `{type}({phase}-{plan}): {task}`

## Resume Protocol

On session re-entry (session-start.sh):
1. Read state.json → exact phase, step, status
2. Read .execution-state.json → which plans done/pending
3. Check git log → correlate commits with tasks
4. Re-compile .ctx-{role}.toon from JSONL artifacts on disk
5. Resume at exact point — everything is committed
