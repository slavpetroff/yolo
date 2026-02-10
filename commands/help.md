---
name: help
disable-model-invocation: true
description: Display all available VBW commands with descriptions and usage examples.
argument-hint: [command-name]
allowed-tools: Read, Glob
---

# VBW Help $ARGUMENTS

## Behavior

**No args:** Show all commands grouped by stage (mark all ✓).
**With arg:** Read `${CLAUDE_PLUGIN_ROOT}/commands/{name}.md`, display: name, description, usage, args, related.

## Commands

**Lifecycle:** ✓ init (scaffold) · ✓ implement (smart router) · ✓ plan (Lead agent) · ✓ execute (Agent Teams) · ✓ archive (close out)
**Monitoring:** ✓ status (dashboard) · ✓ qa (deep verify)
**Quick Actions:** ✓ fix (quick fix) · ✓ debug (investigation) · ✓ todo (backlog)
**Session:** ✓ pause (save notes) · ✓ resume (restore context)
**Codebase:** ✓ map (Scout analysis) · ✓ discuss (pre-plan context) · ✓ assumptions (surface assumptions) · ✓ research (standalone)
**Phases:** ✓ audit (readiness) · ✓ add-phase (append) · ✓ insert-phase (renumber) · ✓ remove-phase (renumber)
**Config:** ✓ skills (community skills) · ✓ config (settings) · ✓ help (this) · ✓ whats-new (changelog) · ✓ update (version) · ✓ uninstall (removal)

## Architecture

- /vbw:execute creates Dev team for parallel plans. /vbw:map creates Scout team. Session IS the lead.
- Continuous verification via PostToolUse, TaskCompleted, TeammateIdle hooks. /vbw:qa is on-demand.
- /vbw:config maps skills to hook events (skill-hook wiring).

## Getting Started

➜ /vbw:init -> /vbw:implement -> /vbw:qa -> /vbw:archive
Or /vbw:plan + /vbw:execute for control. `/vbw:help <command>` for details.

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md — double-line box, ✓ available, ➜ Getting Started, no ANSI.
