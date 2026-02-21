# YOLO Plugin

**Core value:** Replace ad-hoc AI coding with repeatable, phased workflows

A Claude Code plugin that adds structured development workflows — planning, execution, and verification — using specialized agent teams.


## Plugin Rules

- **Commit format:** `{type}({scope}): {description}` — types: feat, fix, test, refactor, perf, docs, style, chore.
- **One commit per task.** Each task in a plan gets exactly one atomic commit.
- **Never commit secrets.** Do not stage .env, .pem, .key, credentials, or token files.
- **Plan before building.** Plans are the source of truth.
- **Do not fabricate content.** Only use what the user explicitly states in project-defining flows.
- **Do not bump version or push until asked.** Never run `git push` unless the user explicitly requests it, except when config.json sets `auto_push` to `always` or `after_phase`.
- **PR review rules:** See `references/pr-review-protocol.md`.
- **YOLO-specific:** Use YOLO commands for project work. Do not manually edit `.yolo-planning/`. No QA or Scout agents.
- **VBW-specific:** Use VBW commands for project work. Do not manually edit `.vbw-planning/`.

## Active Context

**Work:** Token & Cache Architecture Optimization (4 phases)
**Last shipped:** yolo-v2.3.0 (2026-02-21) — 7 phases, 50 tasks, 30 commits
**Next action:** Run /yolo:vibe --plan 1 to plan Phase 1: Token Economics Baseline


## Installed Skills

**Global:** python-backend-architecture-review, kubernetes-health, fastapi-expert, find-skills, design-md, reactcomponents, docker-expert, fastapi-templates, kubernetes-expert, github-actions-templates, async-python-patterns, stitch-loop, managing-infra, clean-architecture, python-backend, rust-async-patterns, rust-best-practices

## Project Conventions

Enforced from `config/` and `.yolo-planning/codebase/CONVENTIONS.md`. Run /yolo:config to view.

## Commands

Run /yolo:status for current progress.
Run /yolo:help for all available commands.
## Plugin Isolation

Hook-enforced. See `references/plugin-isolation.md`.
