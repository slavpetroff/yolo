# YOLO System Architecture

## System Overview

YOLO (Your Own Local Orchestrator) is a Claude Code plugin that replaces ad-hoc AI coding with repeatable, phased workflows. It implements a company-grade engineering hierarchy where specialized agents execute structured 11-step workflows across multiple phases. Version 0.2.2 adds QA gate hardening, Teammate API protocol refinement, and enhanced review ownership patterns.

**Core Philosophy:**
- Workflows are source-of-truth; planning artifacts (JSONL) guide execution
- Agents receive scoped context (progressive narrowing down hierarchy)
- Verification gates and artifact commits enable resumption at any step
- Zero dependencies; all scripts are bash + jq
- Dynamic personas adapt agent behavior to project type
- Dual spawn strategy: Task tool (default) or Teammate API (parallel)
- QA gates run script-only validation BEFORE expensive agent spawns

## Hierarchical Agent Architecture

### Organizational Structure

```
                        User
                         |
                    go.md (Owner proxy)
                         |
    +--------------------+--------------------+
    |                    |                     |
Backend Lead       Frontend Lead         UX/Design Lead
    |                    |                     |
Backend Agents    Frontend Agents       UX Agents
```

**Single Department (Default: Backend Only)**
- Critic -> Scout -> Architect -> Lead -> Senior (Design Review) -> Tester -> Dev -> Senior (Code Review) -> QA -> Security -> Sign-off
- Debugger (on-call)

**Multi-Department (Optional)**
- UI/UX executes first -> Frontend + Backend in parallel -> Integration QA -> Owner sign-off
- Separate agent rosters per department (fe-*, ux-* prefixes)
- Shared agents: Owner, Scout, Security, Critic, Debugger
- Department leads never communicate directly; all cross-dept through Owner or file-based handoff

### Agent Role Matrix (26 Agents)

| Agent | Role | Input | Output |
|-------|------|-------|--------|
| yolo-critic | Gap Analyst | reqs, codebase, research | critique.jsonl |
| yolo-scout | Research Analyst | critique (critical/major), reqs, codebase | research.jsonl |
| yolo-architect | Solutions Architect | critique, research, codebase, reqs | architecture.toon, ROADMAP |
| yolo-lead | Tech Lead | architecture, reqs | plan.jsonl, task coordination |
| yolo-senior | Senior Engineer | plan.jsonl | enriched specs, code-review.jsonl |
| yolo-tester | TDD Test Author | enriched plan (ts field) | test files, test-plan.jsonl |
| yolo-dev | Junior Developer | enriched plan (spec field) | code commits, summary.jsonl |
| yolo-qa | QA Lead | summary, plan | verification.jsonl |
| yolo-qa-code | QA Engineer | code commits, tests | qa-code.jsonl |
| yolo-security | Security Engineer | all commits, deps | security-audit.jsonl |
| yolo-owner | Multi-Dept Lead | critique, all depts | owner_review, sign-off |
| yolo-debugger | Incident Responder | error report | debug-report.jsonl |

**+14 FE/UX equivalents** with department-specific context isolation.

### Escalation Paths

**Single Department:** Dev -> Senior -> Lead -> Architect -> (User, via go.md)
**Multi-Department:** Dev -> Senior -> Lead -> Owner -> (User, via go.md)

No agent talks to the user directly. All escalations flow UP the chain.

### Escalation Round-Trip (NEW in Phase 5)

Complete bidirectional escalation path:
- **Upward:** Dev -> Senior -> Lead -> Architect/Owner -> go.md -> User (via AskUserQuestion)
- **Downward:** User -> go.md -> Owner/Architect -> Lead -> Senior -> Dev (via code_review_changes)

Key mechanisms:
- Timeout-based auto-escalation: `escalation.timeout_seconds` (default 300s) per config/defaults.json
- Level tracking per escalation (id, level, last_escalated_at) prevents duplicate escalations
- Max round-trips (default 2) caps blocker bounce
- Escalation state tracked in .execution-state.json `escalations` array, committed immediately on receipt
- `scripts/check-escalation-timeout.sh` detects stale escalations for auto-escalation
- Two new schemas: `escalation_resolution` (downward) and `escalation_timeout_warning` (timeout trigger)

Teammate mode: intra-team via SendMessage, cross-team/Owner via file-based artifacts.

## 11-Step Workflow

Each phase follows this deterministic, gated workflow:

1. **Critique/Brainstorm** (Critic) -> critique.jsonl
2. **Research** (Scout) -> research.jsonl (append-mode, post-critic entries)
3. **Architecture** (Architect) -> architecture.toon, ROADMAP updates
4. **Planning / Load Plans** (Lead) -> plan.jsonl files, .execution-state.json
5. **Design Review** (Senior) -> enriches plan.jsonl with spec + ts fields
6. **Test Authoring RED** (Tester) -> failing test files, test-plan.jsonl
7. **Implementation** (Dev) -> code commits (one per task), summary.jsonl
8. **Code Review** (Senior) -> code-review.jsonl (approve | request_changes)
9. **QA** (QA Lead + QA Code) -> verification.jsonl, qa-code.jsonl
10. **Security Audit** (Security, optional) -> security-audit.jsonl
11. **Sign-off** (Lead / Owner) -> phase marked complete

## Spawn Strategy: Task Tool vs Teammate API

### team_mode Resolution
`scripts/resolve-team-mode.sh` determines the spawn strategy:
- `team_mode=task` (default): All agents spawned via Task tool, file-based communication
- `team_mode=teammate`: Agents spawned via Teammate API, SendMessage for intra-team communication
- `team_mode=auto`: Auto-detect based on `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` env var

### Task Mode (Default)
- Sequential agent spawning via Task tool
- File-based artifact handoff
- Dev executes plans serially, writes summary.jsonl directly
- Proven, stable architecture

### Teammate Mode (Parallel, 0.2.2 Refinements)
- One team per department: yolo-backend, yolo-frontend, yolo-uiux
- Lead creates team via spawnTeam, registers specialists on-demand
- Dynamic Dev scaling: `min(available_unblocked_tasks, 5)` parallel Devs
- Task self-claiming: Devs query TaskList, claim unblocked tasks without file overlap
- Serialized commits via flock-based locking (git-commit-serialized.sh)
- Lead aggregates summary.jsonl from task_complete messages (Dev skips summary write)
- NEW: Shutdown protocol with 30s deadline timeout + verification checklist
- NEW: SendMessage for intra-team communication; file-based for cross-team handoff

### Cross-Team Communication
- Intra-team: SendMessage (teammate mode) or Task tool result (task mode)
- Cross-department: ALWAYS file-based (different teams cannot SendMessage)
- Handoff artifacts: api-contracts.jsonl, design-handoff.jsonl, .dept-status-{dept}.json

## QA Gate System (NEW in 0.2.2)

### Three-Level Continuous Validation

Script-only gates run BEFORE agents spawn, catching obvious failures early:

| Level | Trigger | Script | Scope | Timeout |
|-------|---------|--------|-------|---------|
| post-task | After each Dev commit | `qa-gate-post-task.sh` | Modified files only | 30s |
| post-plan | After summary.jsonl | `qa-gate-post-plan.sh` | Full test suite | 300s |
| post-phase | Before QA agent spawn | `qa-gate-post-phase.sh` | Full suite + gates | 300s |

### Failure Handling

**Post-task failure:** Dev pauses, Senior reviews, re-specs fix. Max 2 remediation cycles.
**Post-plan failure:** Block progression to next plan. Max 1 remediation cycle.
**Post-phase failure:** Block QA agent spawn (cost optimization). Read gate JSON for remediation targets.

See `references/qa-gate-integration.md` for complete protocol.

### Skip Conditions

- `--skip-qa` flag: Skips all gates + Step 9 QA agents
- `--effort=turbo`: Skips all gates (no tests run)
- `qa_gates.post_task=false`: Skips post-task gate only
- `qa_gates.post_plan=false`: Skips post-plan gate only
- `qa_gates.post_phase=false`: Skips post-phase gate only

## Verification Gate Protocol

### Entry Gate
Before each step: verify prerequisite artifacts exist. If missing and non-skippable: STOP.

### Exit Gate
After step completes: update .execution-state.json, commit state.

### Skip Gate
When guard conditions met: record skip reason, advance to next step.

Entry/exit gates are mandatory on EVERY step (no exceptions for fast/turbo).

## Context Scoping & Delegation

**Progressive Narrowing Rule:** Lower agents see less context, not more.

| Step | Agent | Receives | NEVER passes |
|------|-------|----------|-------------|
| 1 | Critic | reqs, PROJECT, codebase, research | plans, code-review, QA |
| 2 | Scout | critique (critical/major), reqs, codebase | plans, architecture, implementation code |
| 3 | Architect | reqs, codebase, research, critique | implementation code |
| 4 | Lead | architecture, reqs, ROADMAP | full CONTEXT, critique |
| 5 | Senior | plan, architecture, codebase patterns | CONTEXT, full ROADMAP |
| 7 | Dev | enriched plan (spec+ts), tests | CONTEXT, ROADMAP, critique |

### Per-Agent Field Filtering (0.2.2 Refinement)
`scripts/filter-agent-context.sh` provides per-agent JSONL field filtering:
- 11 base roles x 10 artifact types
- Graceful degradation to inline jq if script unavailable
- Rules defined in `references/agent-field-map.md`

Dev spec field is the COMPLETE instruction set. If spec is unclear, Dev escalates to Senior.

## Review Ownership Patterns (NEW in 0.2.2)

16 reviewing agents adopt personal ownership language for subordinate output:

> "This is my [subordinate role]'s [artifact]. I take ownership of its quality. I will review thoroughly, document reasoning for every finding, and escalate conflicts I cannot resolve."

Reviewers:
- Senior (Dev implementation, Dev spec compliance) -- Step 8
- Lead (Senior enrichment, plan execution) -- Steps 5, 11
- Architect (critique disposition, architecture quality) -- Step 3
- Owner (department output) -- Step 11 (multi-dept)
- QA Lead (team artifacts) -- Step 9
- QA Code (code quality) -- Step 9
- +10 dept equivalents (fe-*, ux-*)

See `references/review-ownership-patterns.md` for full matrix.

## Dynamic Persona System

### Project Type Detection
`detect-stack.sh` classifies the project using weighted signal matching against `config/project-types.json`:
- 7 types: web-app, api-service, cli-tool, library, mobile-app, monorepo, generic
- Each type defines department conventions (language, testing, tooling per dept)
- UX focus adapts: CLI -> help/error output, web -> UI components, API -> docs/specs

### Dynamic Department Protocols
`generate-department-toons.sh` uses templates from `config/department-templates/` to produce project-type-specific department TOON files.

### Tool Permission Overrides
`resolve-tool-permissions.sh` merges `config/tool-permissions.json` with agent YAML base tools per project type.

## Multi-Department Orchestration (Optional)

### Workflow Modes

**Parallel (Recommended):**
```
UI/UX Phase N         (Steps 1-11, produces design handoff)
  | (handoff gate)
Frontend Phase N  +  Backend Phase N  (parallel)
  |
Integration QA (cross-dept) -> Security -> Owner Sign-off
```

### Department Context Isolation (Mandatory)
Each department receives ONLY its context file. Enforced by department-guard.sh.

### Team Mode in Multi-Department
- **task mode:** Department Leads spawned as background Task subagents, file-based coordination
- **teammate mode:** Each department gets its own Teammate API team, intra-dept via SendMessage, cross-dept via file-based handoff artifacts

## State Management

### Execution State (.execution-state.json)
Tracks phase, step, timestamps, artifact paths. Updated atomically via jq. Generated by `generate-execution-state.sh`. 11 step statuses tracked: critique, research, architecture, planning, design_review, test_authoring, implementation, code_review, qa, security, signoff.

### Configuration State (.yolo-planning/config.json)
Persists effort, autonomy, models, verification tier, department flags, team_mode, qa_gates settings. Updated via `/yolo:config`.

## Hook System Architecture (19+ Quality Gates)

All hooks route through `hook-wrapper.sh` (DXP-01):
- Exit 0 -> allow
- Exit 2 -> intentional block (JSON deny decision)
- Other non-zero -> log, exit 0 (graceful degradation)

## Artifact Format Strategy

| Category | Format | Committed | Regenerated |
|----------|--------|-----------|-------------|
| User-facing | Markdown | Yes | User edits |
| Agent-facing | JSONL | Yes | Agent output |
| Compiled context | TOON | No | Per session |
| Reference packages | TOON | Yes | Manual rebuild |
| Runtime state | JSON | Yes | Hooks update |
| QA gate results | JSONL | Yes | Gate scripts |

JSONL key abbreviation: 85-93% token savings vs Markdown.

## Version Management

3 files must stay in sync: VERSION (now 0.2.2), plugin.json, marketplace.json.
Tool: `bump-version.sh`. Enforced by pre-push hook.

---
