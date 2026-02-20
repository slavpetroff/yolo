---
name: yolo:resume
category: supporting
disable-model-invocation: true
description: Restore project context from .yolo-planning/ state.
argument-hint:
allowed-tools: Read, Bash, Glob
---

# YOLO Resume

## Context

Working directory: `!`pwd``
Plugin root: `!`echo ${CLAUDE_PLUGIN_ROOT:-$(ls -1d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/yolo-marketplace/yolo/* 2>/dev/null | (sort -V 2>/dev/null || sort -t. -k1,1n -k2,2n -k3,3n) | tail -1)}``
Active milestone: `!`cat .yolo-planning/ACTIVE 2>/dev/null || echo "No active milestone (single-milestone mode)"``

## Guard

1. **Not initialized** (no .yolo-planning/ dir): STOP "Run /yolo:init first."
2. **No roadmap:** ROADMAP.md missing → STOP: "No roadmap found. Run /yolo:vibe."

## Steps

1. **Resolve paths:** ACTIVE → milestone-scoped. Otherwise → .yolo-planning/ defaults.
2. **Read ground truth:** PROJECT.md (name, core value), STATE.md (decisions, todos, blockers), ROADMAP.md (phases), Glob *-PLAN.md + *-SUMMARY.md (plan/completion counts), .execution-state.json (interrupted builds), most recent SUMMARY.md (last work), RESUME.md (session notes). Skip missing files.
3. **Compute progress:** Per phase: count PLANs vs SUMMARYs → not started | planned | in progress | complete. Current phase = first incomplete.
4. **Detect interrupted builds:** If .execution-state.json status="running": all SUMMARYs present = completed since last session; some missing = interrupted.
5. **Present dashboard:** Phase Banner "Context Restored / {project name}" with: core value, phase/progress, overall progress bar, key decisions, todos, blockers (⚠), last completed, build status (✓ completed / ⚠ interrupted), session notes. Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/suggest-next.sh resume`.

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/yolo-brand-essentials.md — double-line box, Metrics Block, ⚠ warnings, ✓ completions, ➜ Next Up, no ANSI.
