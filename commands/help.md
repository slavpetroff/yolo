---
name: help
disable-model-invocation: true
description: Display all available YOLO commands with descriptions and usage examples.
argument-hint: [command-name]
allowed-tools: Read, Glob
---

# YOLO Help $ARGUMENTS

## Behavior

**No args:** Show all commands grouped by stage (mark all ✓).
**With arg:** Read `${CLAUDE_PLUGIN_ROOT}/commands/{name}.md`, display: name, description, usage, args, related.

## Commands

**Lifecycle:** ✓ /yolo:init (scaffold), ✓ /yolo:go (smart router -- plan, execute, discuss, archive, and more)
**Monitoring:** ✓ /yolo:status (dashboard), ✓ /yolo:qa (deep verify)
**Quick Actions:** ✓ /yolo:fix (quick fix), ✓ /yolo:debug (investigation), ✓ /yolo:todo (backlog)
**Session:** ✓ /yolo:pause (save notes), ✓ /yolo:resume (restore context)
**Codebase:** ✓ /yolo:map (Scout analysis), ✓ /yolo:research (standalone)
**Config:** ✓ /yolo:skills (community skills), ✓ /yolo:config (settings, model profiles), ✓ /yolo:help (this), ✓ /yolo:whats-new (changelog), ✓ /yolo:update (version), ✓ /yolo:uninstall (removal)

## Architecture

Dev teams (execute) + Scout teams (map). Continuous verification via hooks; /yolo:qa on-demand. Skill-hook wiring via /yolo:config.

## Model Profiles

| Profile | Leads | Cost/phase |
|---------|-------|-----------|
| quality | Opus leads | ~$2.80 |
| balanced | Sonnet leads | ~$1.40 |
| budget | Haiku QA | ~$0.70 |

`/yolo:config model_profile <name>` or `/yolo:config model_override <agent> <model>`. Interactive: per-agent config with asterisk (*) for overrides. See: @references/model-profiles.md.

## Getting Started

➜ /yolo:init -> /yolo:go -> /yolo:go --archive
Optional: /yolo:config model_profile <quality|balanced|budget> to optimize cost
`/yolo:help <command>` for details.

## GSD Import

Migrating from GSD? Run /yolo:init in your GSD project. YOLO detects `.planning/` and offers to import work history to `.yolo-planning/gsd-archive/` (original preserved). Generates INDEX.json for agent reference. GSD isolation prevents cross-contamination.

See: `docs/migration-gsd-to-yolo.md` for detailed migration guide.

## Output Format

Per @${CLAUDE_PLUGIN_ROOT}/references/yolo-brand-essentials.toon -- double-line box, ✓/➜ symbols, no ANSI.
