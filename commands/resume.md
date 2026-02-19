---
name: resume
disable-model-invocation: true
description: Restore project context from .yolo-planning/ state.
argument-hint:
allowed-tools: Read, Bash, Glob
---

# YOLO Resume

## Context

Working directory: `!`pwd``
Active milestone: `!`cat .yolo-planning/ACTIVE 2>/dev/null || echo "No active milestone (single-milestone mode)"``

## Guard

1. Guard: no .yolo-planning/ -> STOP "YOLO is not set up yet. Run /yolo:init to get started."
2. **No roadmap:** ROADMAP.md missing → STOP: "No roadmap found. Run /yolo:go."

## Steps

1. **Resolve paths:** ACTIVE → milestone-scoped. Otherwise → .yolo-planning/ defaults.
2. **Read ground truth:** PROJECT.md (name, core value), STATE.md (decisions, todos, blockers), ROADMAP.md (phases), Glob *-PLAN.md + *-SUMMARY.md (plan/completion counts), .execution-state.json (interrupted builds), .escalation-state.json (pending escalations), most recent SUMMARY.md (last work), RESUME.md (session notes). Skip missing files.
3. **Compute progress:** Per phase: count PLANs vs SUMMARYs → not started | planned | in progress | complete. Current phase = first incomplete.
4. **Detect interrupted builds:** If .execution-state.json status="running": all SUMMARYs present = completed since last session; some missing = interrupted.
5. **Check pending escalations:** If `.yolo-planning/.escalation-state.json` exists and has pending entries (`jq '.pending | length' .yolo-planning/.escalation-state.json`), display each pending escalation with agent, reason, severity, and creation timestamp. Format: `⚠ {N} pending escalation(s) requiring resolution`. For each: `  - [{severity}] {agent}: {reason} (since {created_at})`.
6. **Present dashboard:** Phase Banner "Context Restored / {project name}" with: core value, phase/progress, overall progress bar, key decisions, todos, blockers (⚠), pending escalations (⚠), last completed, build status (✓ completed / ⚠ interrupted), session notes. Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/suggest-next.sh resume`.

## Output Format

Per @${CLAUDE_PLUGIN_ROOT}/references/yolo-brand-essentials.toon -- double-line box, ⚠/✓/➜ symbols, no ANSI.
