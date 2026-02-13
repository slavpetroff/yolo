# Shared Agents Protocol

Company-level agents dispatched across departments. Read by Owner, Critic, Scout, Debugger, and Security.

## Agent Roster

| Agent | Role | Model | Tools | Produces | Token Budget | Dispatch |
|-------|------|-------|-------|----------|-------------|----------|
| yolo-owner | Project Owner | Opus | Read,Glob,Grep (read-only) | owner_review, owner_signoff | 3000 | Phase start + end |
| yolo-critic | Brainstorm / Gap Analyst | Opus | Read,Glob,Grep,WebSearch,WebFetch | critique.jsonl | 4000 | Per department |
| yolo-scout | Research Analyst | Haiku | Read,Glob,Grep,WebSearch,WebFetch | research.jsonl | 1000 | On demand |
| yolo-debugger | Incident Responder | Sonnet | All | debug-report.jsonl | 3000 | On incident |
| yolo-security | Security Engineer | Sonnet | Read,Glob,Grep,Bash | security-audit.jsonl | 3000 | Per department |

Models shown are quality profile defaults. Actual models resolved via `resolve-agent-model.sh` from `config/model-profiles.json`.

## Project Owner Protocol

Owner is the final internal escalation point. All department Leads report to Owner. Only Owner escalates to User.

### Modes

| Mode | Trigger | Input | Output |
|------|---------|-------|--------|
| Context Gathering | Phase start (via go.md proxy) | User answers via questionnaire | Dept-specific CONTEXT files (split, no bleed) |
| Critique Review | Before architecture | critique.jsonl + reqs.jsonl | `owner_review` to Leads |
| Conflict Resolution | Inter-department conflict | Escalations from Leads | Resolution + rationale to Leads |
| Final Sign-off | All departments complete | `department_result` from Leads | `owner_signoff` to Leads |

### Effort-Based Behavior

| Effort | Behavior |
|--------|----------|
| turbo | SKIP Owner entirely. Leads sign off directly. |
| fast | Sign-off only (skip critique review). Quick review. |
| balanced | Full protocol: critique review + sign-off. |
| thorough | Deep review: critique + conflict resolution + sign-off. |

### Owner Constraints
- **Read-only**: No file writes, no edits, no bash.
- Communicates ONLY with department Leads — never individual agents.
- Strategic decisions only — no code-level or design-level technical decisions.
- Cannot spawn subagents.

## Shared Agent Dispatch Rules

### Critic
- Dispatched once per department per phase (before architecture).
- Multi-department: reviews cross-department implications.
- Returns findings to department Lead (Critic has no Write tool).
- In single-department mode: dispatched by Lead as normal.

### Scout
- Dispatched on demand by any Lead for specific research.
- Returns `scout_findings` to requesting Lead.
- Can be dispatched to investigate technology for any department.
- Lightweight (Haiku) — use for quick lookups, not deep analysis.

### Debugger
- Dispatched on incident by Lead (any department).
- Full tool access for investigation.
- Returns `debugger_report` to requesting Lead.
- Lead decides action — Debugger is advisory.

### Security
- Dispatched once per department after QA passes (Step 9).
- Multi-department: runs separate audit per department.
- FAIL = hard STOP (only user `--force` overrides).
- Security FAIL bypasses normal escalation chain → User directly.

## Escalation Table

| Agent | Escalates to | Trigger |
|-------|-------------|---------|
| Owner | User | Business decision needed, inter-department deadlock |
| Critic | Department Lead | Findings are advisory (Lead forwards to Architect) |
| Scout | Department Lead | Cannot find information, conflicting sources |
| Debugger | Department Lead | Investigation complete, fix recommendation |
| Security | Lead (FAIL → User) | Findings to report; FAIL = HARD STOP |

**Owner is the FINAL internal escalation point.** Only Owner escalates to User.
**Exception:** Security FAIL bypasses chain → User directly.

## Multi-Department Workflow Overview

```
Phase Start
    │
    ▼
 Owner Context Gathering  ← SOLE point of contact with user
    │                        Questionnaire → split into dept CONTEXT files
    ▼
 Owner Critique Review    ← balanced/thorough only
    │
    ▼
 UI/UX Department (10-step)
    │ handoff (design-tokens, component-specs)
    ├──────────────┐
    ▼              ▼
 Frontend (10)  Backend (10)  ← parallel, each gets ONLY their dept context
    │              │
    └──────┬───────┘
           ▼
 Integration QA + Security
           ▼
 Owner Sign-off
```

When only backend is active (single department mode), Owner is optional and Lead signs off directly.

## Communication Schemas

Shared agents use standard SendMessage schemas. See @references/handoff-schemas.md for:
- `owner_review` (Owner → Leads)
- `owner_signoff` (Owner → All Leads)
- `department_result` (Department Lead → Owner)
- `escalation` (any agent, up the chain)
- `scout_findings` (Scout → Lead)
- `debugger_report` (Debugger → Lead)
- `security_audit` (Security → Lead)
