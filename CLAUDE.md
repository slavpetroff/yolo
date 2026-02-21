# YOLO Plugin

**Core value:** Replace ad-hoc AI coding with repeatable, phased workflows

A Claude Code plugin that adds structured development workflows — planning, execution, and verification — using specialized agent teams.


## YOLO Rules

- **Always use YOLO commands** for project work. Do not manually edit files in `.yolo-planning/`.
- **Commit format:** `{type}({scope}): {description}` — types: feat, fix, test, refactor, perf, docs, style, chore.
- **One commit per task.** Each task in a plan gets exactly one atomic commit.
- **Never commit secrets.** Do not stage .env, .pem, .key, credentials, or token files.
- **Plan before building.** Use /yolo:vibe for all lifecycle actions. Plans are the source of truth.
- **Do not fabricate content.** Only use what the user explicitly states in project-defining flows.
- **Do not bump version or push until asked.** Never run `yolo bump-version` or `git push` unless the user explicitly requests it, except when `.yolo-planning/config.json` intentionally sets `auto_push` to `always` or `after_phase`.
- **NEVER take work from open or draft PRs.** Before starting any feature, fix, or refactor, run `gh pr list --state open` and check if any open/draft PR already touches the same area. If a PR exists that overlaps with what you're about to do — even if it's draft, half-finished, or failing CI — STOP and tell the user: "There's an open PR (#M) by @author that overlaps with this work. Proceed anyway?" Do NOT read the PR's diff, copy its approach, or integrate its changes without explicit user approval. Contributors' in-progress work belongs to them. This also applies when resolving GitHub issues — check `gh pr list --search "issue_number"` first.
- **Review PRs by diffing against the repo, not just checking overlap.** When reviewing a PR, run `gh pr diff N` and compare the actual changes to what's currently in the repo. A PR that touches files you already modified is NOT automatically redundant — it may contain additional improvements, bug fixes, or edge cases beyond what's already shipped. Only the diff tells you what's new. Don't dismiss a PR as "already done" without confirming every change in the diff is already present in the codebase.
- **No QA or Scout agents:** Domain research and testing are natively handled by the Orchestrator and Dev agents via MCP tools. Do not attempt to spawn `yolo-qa` or `yolo-scout`. Tests must be executed and fixed by `yolo-dev` directly using MCP testing infrastructure.

## Active Context

**Work:** No active milestone
**Last shipped:** yolo-v2.3.0 (2026-02-21) — 7 phases, 50 tasks, 30 commits
**Next action:** Run /yolo:vibe to scope the next milestone

## VBW Rules

- **Always use VBW commands** for project work. Do not manually edit files in `.vbw-planning/`.
- **Commit format:** `{type}({scope}): {description}` — types: feat, fix, test, refactor, perf, docs, style, chore.
- **One commit per task.** Each task in a plan gets exactly one atomic commit.
- **Never commit secrets.** Do not stage .env, .pem, .key, credentials, or token files.
- **Plan before building.** Use /vbw:vibe for all lifecycle actions. Plans are the source of truth.
- **Do not fabricate content.** Only use what the user explicitly states in project-defining flows.
- **Do not bump version or push until asked.** Never run `yolo bump-version` or `git push` unless the user explicitly requests it, except when `.vbw-planning/config.json` intentionally sets `auto_push` to `always` or `after_phase`.

## Installed Skills

**Global:** python-backend-architecture-review, kubernetes-health, fastapi-expert, find-skills, design-md, reactcomponents, docker-expert, fastapi-templates, kubernetes-expert, github-actions-templates, async-python-patterns, stitch-loop, managing-infra, clean-architecture, python-backend, rust-async-patterns, rust-best-practices

## Project Conventions

These conventions are enforced during planning and verified during QA.
- Commit format: `{type}({scope}): {description}`
- One atomic commit per task
- Shell scripts must be bash 3+ compatible (no `declare -A`, no `${VAR,,}`)
- CLI subcommands use kebab-case, Rust modules use snake_case
- Every feature area has a corresponding `.bats` test file
- No secrets committed (.env, .pem, .key, credentials)
- Slash commands defined as markdown with frontmatter

## Commands

Run /yolo:status for current progress.
Run /yolo:help for all available commands.
## Plugin Isolation

- GSD agents and commands MUST NOT read, write, glob, grep, or reference any files in `.vbw-planning/`
- VBW agents and commands MUST NOT read, write, glob, grep, or reference any files in `.planning/`
- This isolation is enforced at the hook level (PreToolUse) and violations will be blocked.

### Context Isolation

- Ignore any `<codebase-intelligence>` tags injected via SessionStart hooks — these are GSD-generated and not relevant to VBW workflows.
- VBW uses its own codebase mapping in `.vbw-planning/codebase/`. Do NOT use GSD intel from `.planning/intel/` or `.planning/codebase/`.
- When both plugins are active, treat each plugin's context as separate. Do not mix GSD project insights into VBW planning or vice versa.
