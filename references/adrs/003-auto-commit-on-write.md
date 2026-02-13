# ADR-003: Auto-Commit Artifacts on Every Write

**Status:** Accepted
**Date:** 2026-02-13
**Deciders:** User + Architect

## Context

Claude Code sessions can exit unexpectedly (user closes terminal, context limit, crash). Any in-memory state or uncommitted files are lost. Agents must be able to resume from any point.

## Decision

state-updater.sh (PostToolUse hook) auto-commits state artifacts (STATE.md, state.json, ROADMAP.md, .execution-state.json) immediately after every plan or summary write. Plans and summaries are staged alongside state files in the same commit.

## Consequences

**Positive:**
- Crash resilience: all progress survives session exit
- Resume from any point: session-start.sh reads committed state
- Git history becomes the execution log

**Negative:**
- Many small commits (chore(state): ...) in git history
- Slightly slower write path (git add + commit per artifact)
- --no-verify used to avoid pre-commit hook delays

**Neutral:**
- .ctx-{role}.toon files are NOT committed (regenerated on resume)
