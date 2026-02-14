---
name: fix
description: Apply a quick fix or small change with commit discipline. Turbo mode -- no planning ceremony.
argument-hint: "<description of what to fix or change>"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, WebFetch
disable-model-invocation: true
---

# YOLO Fix: $ARGUMENTS

## Context

Working directory: `!`pwd``
Config: Pre-injected by SessionStart hook.

## Guard

- Not initialized (no .yolo-planning/ dir): STOP "Run /yolo:init first."
- No $ARGUMENTS: STOP "Usage: /yolo:fix \"description of what to fix\""

## Steps

1. **Parse:** Entire $ARGUMENTS (minus flags) = fix description.
2. **Milestone:** If .yolo-planning/ACTIVE exists, use milestone-scoped STATE_PATH. Else .yolo-planning/STATE.md.
3. **Spawn Dev:** Spawn yolo-dev as subagent via Task tool:
```
Quick fix (Turbo mode). Effort: low.
Task: {fix description}.
Implement directly. One atomic commit: fix(quick): {brief description}.
No SUMMARY.md or PLAN.md needed.
If ambiguous or requires architectural decisions, STOP and report back.
```
4. **Verify + present:** Check `git log --oneline -1`.

Committed:
```
✓ Fix applied
  {commit hash} {commit message}
  Files: {changed files}
```
Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/suggest-next.sh fix` and display.

Dev stopped:
```
⚠ Fix could not be applied automatically
  {reason from Dev agent}
```
Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/suggest-next.sh debug` and display.
