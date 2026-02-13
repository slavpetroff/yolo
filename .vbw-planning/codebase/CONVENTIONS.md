# Code Conventions

## File Naming

- **Commands**: kebab-case `.md` files in `commands/` (e.g., `whats-new.md`)
- **Agents**: `yolo-{role}.md` in `agents/` (e.g., `yolo-lead.md`, `yolo-dev.md`)
- **Scripts**: kebab-case `.sh` files in `scripts/` (e.g., `hook-wrapper.sh`, `detect-stack.sh`)
- **Bootstrap scripts**: `bootstrap-{target}.sh` in `scripts/bootstrap/`
- **Phase directories**: `{NN}-{slug}/` pattern (zero-padded number + kebab-case, e.g., `01-context-diet`)
- **Plan files**: `{NN}-{MM}-PLAN.md` (phase-plan)
- **Summary files**: `{NN}-{MM}-SUMMARY.md`
- **Config files**: lowercase `.json` in `config/`

## Shell Script Standards

- All scripts target bash, not POSIX sh (`#!/bin/bash` or `#!/usr/bin/env bash`)
- Minimum: `set -u` (unset variable protection)
- Critical scripts: `set -euo pipefail` (strict mode)
- Variables: UPPER_CASE for script-scoped, lower_case for function-local
- Temporary files use `.tmp.$$` suffix pattern or `mktemp`
- Atomic JSON updates: write to `.tmp`, then `mv` to target

## Commit Format

- Pattern: `{type}({scope}): {description}`
- Types: feat, fix, test, refactor, perf, docs, style, chore
- One commit per task (enforced by validate-commit.sh hook)
- Stage files individually with `git add {file}`, never `git add .` or `git add -A`

## JSON Handling

- Always use `jq` for JSON parsing (never grep/sed on JSON)
- Guard for jq availability before any JSON operation
- Atomic updates: `jq '...' file > file.tmp && mv file.tmp file`

## YAML Frontmatter

- Description must be single-line (multi-line breaks discovery)
- No prettier-ignore comment before frontmatter; use `.prettierignore` instead
- Required fields vary by template (plan: phase, plan, title, wave, depends_on, must_haves)

## Hook Conventions

- All hooks route through `hook-wrapper.sh` for graceful degradation (DXP-01)
- Hook scripts receive JSON context on stdin
- PreToolUse hooks: exit 0 = allow, exit 2 = block
- PostToolUse hooks: always exit 0 (non-blocking feedback)
- Plugin cache resolution: `ls | sort -V | tail -1` (never glob expansion)

## Output Formatting

- Brand vocabulary from `references/yolo-brand-essentials.md`
- No ANSI color codes in model output (not rendered in Claude Code)
- ANSI colors allowed in statusline (terminal rendering)
- Unicode symbols: checkmark, cross, diamond, circle, arrow, warning
- Phase banners use double-line box drawing
- Task-level uses single-line box drawing
- Progress bars: 10-character width using block elements

## Security

- security-filter.sh: fail-closed (exit 2 on parse errors)
- file-guard.sh: fail-open (exit 0 on errors)
- Never commit secrets (.env, .pem, .key, credentials)
- Plugin isolation: YOLO and GSD have mutual file access blocks

## Agent Convention

- Agent memory is project-scoped
- Agents re-read files after compaction (`.compaction-marker`)
- No subagent nesting (agents cannot spawn other agents)
- Communication via SendMessage with typed schemas (dev_progress, dev_blocker, qa_result, scout_findings, debugger_report)

## Version Management

- Single source of truth: `VERSION` file
- `bump-version.sh` syncs to plugin.json, marketplace.json, CHANGELOG.md
- Never bump version or push unless explicitly asked
