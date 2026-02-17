# Agent Field Map

Documents which JSONL artifact fields each agent role requires. Used by scripts/filter-agent-context.sh to extract only needed fields, reducing token overhead. The 26 agents across 4 departments (backend, frontend, UI/UX, shared) map to 11 base roles via fe-/ux- prefix stripping (e.g., fe-dev -> dev, ux-architect -> architect). This mapping is implemented in compile-context.sh lines 25-29 and filter-agent-context.sh.

Note: Approximation: char/4 for token estimation (D9).

## Prefix Stripping

| Full Role | Prefix | Base Role |
|-----------|--------|-----------|
| architect | (none) | architect |
| lead | (none) | lead |
| senior | (none) | senior |
| dev | (none) | dev |
| tester | (none) | tester |
| qa | (none) | qa |
| qa-code | (none) | qa-code |
| security | (none) | security |
| fe-architect | fe- | architect |
| fe-lead | fe- | lead |
| fe-senior | fe- | senior |
| fe-dev | fe- | dev |
| fe-tester | fe- | tester |
| fe-qa | fe- | qa |
| fe-qa-code | fe- | qa-code |
| ux-architect | ux- | architect |
| ux-lead | ux- | lead |
| ux-senior | ux- | senior |
| ux-dev | ux- | dev |
| ux-tester | ux- | tester |
| ux-qa | ux- | qa |
| ux-qa-code | ux- | qa-code |
| owner | (none) | owner |
| critic | (none) | critic |
| scout | (none) | scout |
| debugger | (none) | debugger |

## Field Mappings by Role

### architect

| Artifact Type | Fields | jq Projection | Notes |
|---------------|--------|---------------|-------|
| plan.jsonl (header) | all | identity (no filter) | Full header for architecture decisions |
| plan.jsonl (tasks) | N/A | - | Architect does not read plan tasks |
| critique.jsonl | id, cat, sev, q, ctx, sug, st | {id,cat,sev,q,ctx,sug,st} | All fields -- Architect addresses each finding |
| research.jsonl | q, finding, conf, rel, brief_for | {q,finding,conf,rel,brief_for} | brief_for links to critique ID (D4) |
| summary.jsonl | N/A | - | |
| code-review.jsonl | N/A | - | |
| verification.jsonl | N/A | - | |
| qa-code.jsonl | N/A | - | |
| security-audit.jsonl | N/A | - | |
| test-plan.jsonl | N/A | - | |
| gaps.jsonl | N/A | - | |

### lead

| Artifact Type | Fields | jq Projection | Notes |
|---------------|--------|---------------|-------|
| plan.jsonl (header) | all | identity (no filter) | Lead writes headers, needs full access |
| plan.jsonl (tasks) | id, a, f, done, v | {id,a,f,done,v} | Action summary for planning |
| summary.jsonl | s, tc, tt, fm, dv | {s,tc,tt,fm,dv} | Progress tracking |
| critique.jsonl | N/A | - | Lead does not directly consume critique |
| research.jsonl | N/A | - | |
| code-review.jsonl | N/A | - | |
| verification.jsonl | N/A | - | |
| qa-code.jsonl | N/A | - | |
| security-audit.jsonl | N/A | - | |
| test-plan.jsonl | N/A | - | |
| gaps.jsonl | N/A | - | |

### senior

Note: Senior has TWO modes. Design review mode (Step 5) and code review mode (Step 8).

| Artifact Type | Fields | jq Projection | Notes |
|---------------|--------|---------------|-------|
| plan.jsonl (header) | N/A | - | |
| plan.jsonl (tasks, design) | id, a, f, done, v | {id,a,f,done,v} | For spec enrichment |
| plan.jsonl (tasks, review) | id, a, f, spec, ts, done | {id,a,f,spec,ts,done} | For code review against spec |
| critique.jsonl | id, desc, rec (where st=open) | select(.st=="open") \| {id,desc,rec} | Only open findings for spec enrichment |
| test-plan.jsonl | id, tf, tc, red | {id,tf,tc,red} | For TDD compliance check |
| summary.jsonl | N/A | - | |
| research.jsonl | N/A | - | |
| code-review.jsonl | N/A | - | |
| verification.jsonl | N/A | - | |
| qa-code.jsonl | N/A | - | |
| security-audit.jsonl | N/A | - | |
| gaps.jsonl | N/A | - | |

### dev

| Artifact Type | Fields | jq Projection | Notes |
|---------------|--------|---------------|-------|
| plan.jsonl (header) | N/A | - | |
| plan.jsonl (tasks) | id, a, f, spec, ts, done | {id,a,f,spec,ts,done} | Primary work input |
| gaps.jsonl | id, sev, desc, exp, act, st | {id,sev,desc,exp,act,st} | Fix gaps from QA |
| summary.jsonl | N/A | - | |
| critique.jsonl | N/A | - | |
| research.jsonl | N/A | - | |
| code-review.jsonl | N/A | - | |
| verification.jsonl | N/A | - | |
| qa-code.jsonl | N/A | - | |
| security-audit.jsonl | N/A | - | |
| test-plan.jsonl | N/A | - | |

### tester

| Artifact Type | Fields | jq Projection | Notes |
|---------------|--------|---------------|-------|
| plan.jsonl (header) | N/A | - | |
| plan.jsonl (tasks) | id, a, f, ts, spec | {id,a,f,ts,spec} | Test spec is primary input |
| summary.jsonl | N/A | - | |
| critique.jsonl | N/A | - | |
| research.jsonl | N/A | - | |
| code-review.jsonl | N/A | - | |
| verification.jsonl | N/A | - | |
| qa-code.jsonl | N/A | - | |
| security-audit.jsonl | N/A | - | |
| test-plan.jsonl | N/A | - | |
| gaps.jsonl | N/A | - | |

### qa

| Artifact Type | Fields | jq Projection | Notes |
|---------------|--------|---------------|-------|
| plan.jsonl (header) | mh, obj | {mh,obj} | Must-haves and objective for verification |
| plan.jsonl (tasks) | N/A | - | |
| summary.jsonl | s, tc, tt, fm, dv, tst | {s,tc,tt,fm,dv,tst} | Completion status for QA |
| critique.jsonl | N/A | - | |
| research.jsonl | N/A | - | |
| code-review.jsonl | N/A | - | |
| verification.jsonl | N/A | - | |
| qa-code.jsonl | N/A | - | |
| security-audit.jsonl | N/A | - | |
| test-plan.jsonl | N/A | - | |
| gaps.jsonl | N/A | - | |

### qa-code

| Artifact Type | Fields | jq Projection | Notes |
|---------------|--------|---------------|-------|
| summary.jsonl | fm | {fm} | Files to check |
| test-plan.jsonl | id, tf, tc, red | {id,tf,tc,red} | Tests to verify |
| plan.jsonl (header) | N/A | - | |
| plan.jsonl (tasks) | N/A | - | |
| critique.jsonl | N/A | - | |
| research.jsonl | N/A | - | |
| code-review.jsonl | N/A | - | |
| verification.jsonl | N/A | - | |
| qa-code.jsonl | N/A | - | |
| security-audit.jsonl | N/A | - | |
| gaps.jsonl | N/A | - | |

### security

| Artifact Type | Fields | jq Projection | Notes |
|---------------|--------|---------------|-------|
| summary.jsonl | fm | {fm} | Files to audit |
| plan.jsonl (header) | N/A | - | |
| plan.jsonl (tasks) | N/A | - | |
| critique.jsonl | N/A | - | |
| research.jsonl | N/A | - | |
| code-review.jsonl | N/A | - | |
| verification.jsonl | N/A | - | |
| qa-code.jsonl | N/A | - | |
| security-audit.jsonl | N/A | - | |
| test-plan.jsonl | N/A | - | |
| gaps.jsonl | N/A | - | |

### scout

| Artifact Type | Fields | jq Projection | Notes |
|---------------|--------|---------------|-------|
| critique.jsonl | id, sev, q | select(.sev=="critical" or .sev=="major") \| {id,sev,q} | Only critical/major per D7; minor excluded for 1000-token budget |
| plan.jsonl (header) | N/A | - | |
| plan.jsonl (tasks) | N/A | - | |
| summary.jsonl | N/A | - | |
| research.jsonl | N/A | - | Scout produces research, does not consume it |
| code-review.jsonl | N/A | - | |
| verification.jsonl | N/A | - | |
| qa-code.jsonl | N/A | - | |
| security-audit.jsonl | N/A | - | |
| test-plan.jsonl | N/A | - | |
| gaps.jsonl | N/A | - | |

### critic

| Artifact Type | Fields | jq Projection | Notes |
|---------------|--------|---------------|-------|
| research.jsonl | q, finding, conf | {q,finding,conf} | Prior research for gap analysis |
| plan.jsonl (header) | N/A | - | |
| plan.jsonl (tasks) | N/A | - | |
| summary.jsonl | N/A | - | |
| critique.jsonl | N/A | - | Critic produces critique, does not consume it |
| code-review.jsonl | N/A | - | |
| verification.jsonl | N/A | - | |
| qa-code.jsonl | N/A | - | |
| security-audit.jsonl | N/A | - | |
| test-plan.jsonl | N/A | - | |
| gaps.jsonl | N/A | - | |

### debugger

| Artifact Type | Fields | jq Projection | Notes |
|---------------|--------|---------------|-------|
| research.jsonl | q, finding | {q,finding} | Relevant findings for debug context |
| gaps.jsonl | all | identity (no filter) | Full gap details for root cause analysis |
| summary.jsonl | fm, ch, dv | {fm,ch,dv} | Changed files and deviations |
| plan.jsonl (header) | N/A | - | |
| plan.jsonl (tasks) | N/A | - | |
| critique.jsonl | N/A | - | |
| code-review.jsonl | N/A | - | |
| verification.jsonl | N/A | - | |
| qa-code.jsonl | N/A | - | |
| security-audit.jsonl | N/A | - | |
| test-plan.jsonl | N/A | - | |

### owner

| Artifact Type | Fields | jq Projection | Notes |
|---------------|--------|---------------|-------|
| plan.jsonl (header) | all | identity (no filter) | Full header for sign-off |
| plan.jsonl (tasks) | N/A | - | |
| summary.jsonl | s, fm, dv | {s,fm,dv} | Status overview |
| critique.jsonl | N/A | - | |
| research.jsonl | N/A | - | |
| code-review.jsonl | N/A | - | |
| verification.jsonl | N/A | - | |
| qa-code.jsonl | N/A | - | |
| security-audit.jsonl | N/A | - | |
| test-plan.jsonl | N/A | - | |
| gaps.jsonl | N/A | - | |

## Excluded Artifact Types

Per D12, 7 artifact types are excluded from field-level filtering.

| Artifact Type | Exclusion Reason | Consumer(s) |
|---------------|------------------|-------------|
| decisions.jsonl | Append-only log, Architect reads all fields | Architect |
| manual-qa.jsonl | Single consumer, no filtering benefit | Lead |
| design-tokens.jsonl | Cross-dept handoff, read as-is by FE | fe-senior, fe-dev |
| component-specs.jsonl | Cross-dept handoff, read as-is by FE | fe-senior, fe-qa |
| user-flows.jsonl | Cross-dept handoff artifact | fe-lead |
| design-handoff.jsonl | Cross-dept handoff, read as-is by consuming dept Lead | fe-lead, fe-architect |
| api-contracts.jsonl | Cross-dept negotiation, read as-is by both FE and BE Leads | lead, fe-lead |

Note: Runtime state files (state.json, .execution-state.json) are excluded because they are read by the go.md orchestrator only, not by agent context compilation.

## Senior Mode Disambiguation

Senior operates in two modes depending on workflow step: Design Review (Step 5) enriches plan tasks with specs, reading tasks(id,a,f,done,v) and critique(id,desc,rec where st=open). Code Review (Step 8) reviews implementation against specs, reading tasks(id,a,f,spec,ts,done) and test-plan(id,tf,tc,red). filter-agent-context.sh accepts an optional --mode=design|review flag for Senior. Default is design. When --mode=review, plan task projection uses the review field set.
