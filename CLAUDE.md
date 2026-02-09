# VBW — Vibe Better with Claude Code

A Claude Code plugin that adds structured development workflows — planning, execution, and verification — using specialized agent teams.

**Core value:** Replace ad-hoc AI coding with repeatable, phased workflows.

## Active Context

**Work:** No active work — all milestones complete
**Last completed:** v2 Command Redesign (archived 2026-02-09, tag: milestone/v2-command-redesign)
**Next action:** /vbw:implement to start new work

## VBW Rules

- **Always use VBW commands** for project work. Do not manually edit files in `.vbw-planning/`.
- **Commit format:** `{type}({scope}): {description}` — types: feat, fix, test, refactor, perf, docs, style, chore.
- **One commit per task.** Each task in a plan gets exactly one atomic commit.
- **Never commit secrets.** Do not stage .env, .pem, .key, credentials, or token files.
- **Plan before building.** Use /vbw:plan before /vbw:execute. Plans are the source of truth.
- **Do not fabricate content.** Only use what the user explicitly states in project-defining flows.
- **Do not bump version or push until asked.** Never run `scripts/bump-version.sh` or `git push` unless the user explicitly requests it. Commit locally and wait.

## Key Decisions

| Decision | Date | Rationale |
|----------|------|-----------|
| Ship current feature set as v1 | 2026-02-09 | All core workflows functional |
| Target solo developers | 2026-02-09 | Primary Claude Code user base |
| 3-phase roadmap: failures → polish → docs | 2026-02-09 | Risk-ordered, concerns-first |
| `/vbw:implement` as single primary command | 2026-02-09 | Users confused by command overlap |
| Milestones become internal concept | 2026-02-09 | Solo devs don't need the abstraction |
| `/vbw:ship` → `/vbw:archive` | 2026-02-09 | Clearer verb for wrapping up work |
| Remove `/vbw:new`, `/vbw:milestone`, `/vbw:switch` | 2026-02-09 | Absorbed into implement/plan |

## Installed Skills

- audit-website (global)
- bash-pro (global)
- find-skills (global)
- frontend-design (global)
- plugin-settings (global)
- plugin-structure (global)
- posix-shell-pro (global)
- remotion-best-practices (global)
- seo-audit (global)
- skill-development (global)
- vercel-react-best-practices (global)
- web-design-guidelines (global)
- agent-sdk-development (global)

## Learned Patterns

- Plan 03-03 (validation) found zero discrepancies — Plans 01+02 across all phases were implemented accurately
- Hook count grew from 17 to 18 during Phase 1 (frontmatter validation added)
- Version sync enforcement at push time prevents mismatched releases

## State

- Planning directory: `.vbw-planning/`
- Codebase map: `.vbw-planning/codebase/` (9 documents)

## Commands

Run /vbw:status for current progress.
Run /vbw:help for all available commands.
