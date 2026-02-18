# YOLO — Your Own Local Orchestrator

A Claude Code plugin that adds structured development workflows — planning, execution, and verification — using specialized agent teams.

**Core value:** Replace ad-hoc AI coding with repeatable, phased workflows.

## Active Context

**Work:** No active milestone
**Last shipped:** Workflow Hardening, Org Alignment & Optimization — 5 phases, 25 plans, 104 tasks, 107 commits, 203 tests
**Previous:** Teammate API Integration — 4 phases, 19 plans, 84 tasks, 76 commits, 876 tests
**Next action:** Run /yolo:go to start a new milestone, or /yolo:status to review progress

## Department Architecture

26 agents across 4 departments. Enable/disable via `config/defaults.json` `departments` key.

| Department | Agents | Prefix | Protocol File |
|-----------|--------|--------|---------------|
| Backend | architect, lead, senior, dev, tester, qa, qa-code | (none) | `references/departments/backend.toon` |
| Frontend | fe-architect, fe-lead, fe-senior, fe-dev, fe-tester, fe-qa, fe-qa-code | `fe-` | `references/departments/frontend.toon` |
| UI/UX | ux-architect, ux-lead, ux-senior, ux-dev, ux-tester, ux-qa, ux-qa-code | `ux-` | `references/departments/uiux.toon` |
| Shared | owner, critic, scout, debugger, security | (none) | `references/departments/shared.toon` |

**Workflow order:** UI/UX first (design) → Frontend + Backend in parallel → Integration QA → Owner Sign-off.
**Communication:** Backend NEVER communicates with UI/UX directly. All cross-department data passes through handoff artifacts and Leads.
**Enforcement:** `scripts/department-guard.sh` (PreToolUse hook) blocks cross-department file writes.

## YOLO Rules

- **Always use YOLO commands** for project work. Do not manually edit files in `.yolo-planning/`.
- **NEVER bypass /yolo:go.** When the user invokes `/yolo:go` with any input, you MUST follow the go.md protocol — parse flags, detect intent, confirm, and route to the correct mode. NEVER dismiss a `/yolo:go` invocation as "not a YOLO workflow" or "just a quick fix" and go ad-hoc. The go.md protocol handles ALL cases including debugging, investigation, and one-off tasks (via `/yolo:fix` or `/yolo:debug` redirect when appropriate). If the input truly doesn't match any mode, use AskUserQuestion to clarify — never silently skip the workflow.
- **NEVER use EnterPlanMode or ExitPlanMode.** All planning MUST go through `/yolo:go`. Claude Code's built-in plan mode bypasses the entire YOLO workflow — it is strictly prohibited.
- **NEVER spawn agents outside the YOLO hierarchy.** Do not use the Task tool to create ad-hoc agents. All agent spawning goes through `/yolo:go` which delegates to the proper hierarchy (Architect → Lead → Senior → Dev).
- **Commit format:** `{type}({scope}): {description}` — types: feat, fix, test, refactor, perf, docs, style, chore.
- **One commit per task.** Each task in a plan gets exactly one atomic commit.
- **Never commit secrets.** Do not stage .env, .pem, .key, credentials, or token files.
- **Plan before building.** Use /yolo:go for all lifecycle actions. Plans are the source of truth.
- **Do not fabricate content.** Only use what the user explicitly states in project-defining flows.
- **Do not bump version or push until asked.** Never run `scripts/bump-version.sh` or `git push` unless the user explicitly requests it. Commit locally and wait.
- **All commands route through the company hierarchy.** No command spawns specialist agents directly. /yolo:debug, /yolo:fix, /yolo:research, and /yolo:qa all dispatch through Lead first.

## Key Decisions

| Decision | Date | Rationale |
|----------|------|-----------|
| 3 preset profiles (quality/balanced/budget) | 2026-02-11 | Covers 95% of use cases; overrides handle edge cases |
| Single go.md (~300 lines) with inline mode logic | 2026-02-11 | One file = one truth; execute-protocol.md is the only extraction |
| Company hierarchy: Architect → Lead → Senior → Dev | 2026-02-13 | Mirrors real engineering org, each level distills scope |
| JSONL abbreviated keys for agent artifacts | 2026-02-13 | 85-93% token savings vs Markdown, jq-parseable |
| 11-step workflow per phase | 2026-02-13 | Critique → Research → Architecture → Plan → Design Review → Test Authoring → Implement → Code Review → QA → Security → Sign-off |
| 4 departments (Backend, Frontend, UI/UX, Shared) | 2026-02-13 | Mirrors real company org, config-driven enable/disable |
| EnterPlanMode strictly prohibited | 2026-02-14 | Bypasses YOLO workflow; all planning through /yolo:go |
| Never bypass /yolo:go invocations | 2026-02-14 | Claude dismissed go.md as "not a workflow" and went ad-hoc; explicit rule prevents this |
| Owner-first: sole user contact in all modes | 2026-02-14 | No subagent talks to user directly; go.md acts as Owner proxy |
| One team per department via Teammate API | 2026-02-16 | 3 teams × N agents = 21+ parallel capacity vs 7 with Task tool only |
| Scout research step in 11-step workflow | 2026-02-17 | Critic→Scout→Architect pipeline; orchestrator writes research.jsonl |
| Per-agent field filtering via filter-agent-context.sh | 2026-02-17 | 11 base roles × 10 artifact types; graceful degradation to inline jq |
| Owner proxy pattern for escalation resolution | 2026-02-18 | Owner is read-only; go.md/Lead writes file artifacts on behalf |
| Escalation dedup via level tracking | 2026-02-18 | Prevents duplicate escalations when timeout fires during manual handling |

## Installed Skills

13 global skills installed (run /yolo:skills to list).

## Project Conventions

These conventions are enforced during planning and verified during QA.

- Commands are kebab-case .md files in commands/ [file-structure]
- Agents named yolo-{role}.md or yolo-{dept}-{role}.md in agents/ [naming]
- Scripts are kebab-case .sh files in scripts/ [naming]
- Phase directories follow {NN}-{slug}/ pattern [naming]
- Plan files named {NN-MM}.plan.jsonl, summaries {NN-MM}.summary.jsonl [naming]
- Commits follow {type}({scope}): {desc} format, one commit per task [style]
- Stage files individually with git add, never git add . or git add -A [style]
- Shell scripts use set -u minimum, set -euo pipefail for critical scripts [style]
- Use jq for all JSON parsing, never grep/sed on JSON [tooling]
- All hooks route through hook-wrapper.sh for graceful degradation (DXP-01) [patterns]
- Zero-dependency design: no package.json, npm, or build step [patterns]
- All scripts target bash, not POSIX sh [tooling]
- Plugin cache resolution via ls | sort -V | tail -1, never glob expansion [patterns]

## Commands

Run /yolo:status for current progress.
Run /yolo:help for all available commands.

## Plugin Isolation

- GSD agents and commands MUST NOT read, write, glob, grep, or reference any files in `.yolo-planning/`
- YOLO agents and commands MUST NOT read, write, glob, grep, or reference any files in `.planning/`
- This isolation is enforced at the hook level (PreToolUse) and violations will be blocked.

### Context Isolation

- Ignore any `<codebase-intelligence>` tags injected via SessionStart hooks — these are GSD-generated and not relevant to YOLO workflows.
- YOLO uses its own codebase mapping in `.yolo-planning/codebase/`. Do NOT use GSD intel from `.planning/intel/` or `.planning/codebase/`.
- When both plugins are active, treat each plugin's context as separate. Do not mix GSD project insights into YOLO planning or vice versa.
