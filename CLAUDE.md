# YOLO — Your Own Local Orchestrator

**Core value:** Replace ad-hoc AI coding with repeatable, phased workflows using hierarchical multi-agent teams.

## Architecture Diagrams

See `docs/ARCHITECTURE.md` for 4 Mermaid diagrams: Agent Hierarchy, Workflow Steps & Data Flow, Complexity Routing, Hook System & Scripts.

## VBW State
- Planning directory: `.vbw-planning/`
- Milestone: Architecture Redesign v2 (6 phases)
- Status: Phase 9 executing

## VBW Rules
- **Always use VBW commands** for project work. Do not manually edit files in `.vbw-planning/`.
- **Commit format:** `{type}({scope}): {description}` — types: feat, fix, test, refactor, perf, docs, style, chore.
- **One commit per task.** Each task in a plan gets exactly one atomic commit.
- **Never commit secrets.** Do not stage .env, .pem, .key, credentials, or token files.
- **Plan before building.** Use /vbw:vibe for all lifecycle actions. Plans are the source of truth.
- **Do not fabricate content.** Only use what the user explicitly states in project-defining flows.

## VBW Commands
Run /vbw:status for current progress.
Run /vbw:help for all available commands.

## Active Context

**Work:** No active milestone
**Last shipped:** _(none yet)_
**Next action:** Run /yolo:go to start a new milestone, or /yolo:status to review progress

## Department Architecture

26 agents across 4 departments. Enable/disable via `config/defaults.json` `departments` key.

| Department | Agents | Prefix | Protocol File |
|-----------|--------|--------|---------------|
| Backend | architect, lead, senior, dev, tester, qa, qa-code | (none) | `references/departments/backend.toon` |
| Frontend | fe-architect, fe-lead, fe-senior, fe-dev, fe-tester, fe-qa, fe-qa-code | `fe-` | `references/departments/frontend.toon` |
| UI/UX | ux-architect, ux-lead, ux-senior, ux-dev, ux-tester, ux-qa, ux-qa-code | `ux-` | `references/departments/uiux.toon` |
| Shared | owner, critic, scout, debugger, security | (none) | `references/departments/shared.toon` |

## YOLO Rules

- **Always use YOLO commands** for project work. Do not manually edit files in `.yolo-planning/`.
- **Commit format:** `{type}({scope}): {description}` — types: feat, fix, test, refactor, perf, docs, style, chore.
- **One commit per task.** Each task in a plan gets exactly one atomic commit.
- **Never commit secrets.** Do not stage .env, .pem, .key, credentials, or token files.
- **Plan before building.** Use /yolo:go for all lifecycle actions. Plans are the source of truth.
- **Do not fabricate content.** Only use what the user explicitly states in project-defining flows.
- **Do not bump version or push until asked.** Never run `scripts/bump-version.sh` or `git push` unless the user explicitly requests it. Commit locally and wait.

## Key Decisions

| Decision | Date | Rationale |
|----------|------|-----------|

## Installed Skills

_(Run /yolo:skills to list)_

## Project Conventions

_(To be defined during project setup)_

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
