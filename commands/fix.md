---
name: fix
description: Apply a quick fix via Lead-triaged hierarchy. Turbo mode -- minimal ceremony.
argument-hint: "<description of what to fix or change>"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, WebFetch
disable-model-invocation: true
---

# YOLO Fix: $ARGUMENTS

## Context

Working directory: `!`pwd``
Config: Pre-injected by SessionStart hook.

## Guard

- Guard: no .yolo-planning/ -> STOP "YOLO is not set up yet. Run /yolo:init to get started."
- No $ARGUMENTS: STOP "Missing required input. Usage: /yolo:fix \"description of what to fix\""

## Steps

1. **Parse:** Entire $ARGUMENTS (minus flags) = fix description.
2. **Milestone:** If .yolo-planning/ACTIVE exists, use milestone-scoped STATE_PATH. Else .yolo-planning/STATE.md.
3. **Spawn Lead:**
- Resolve models (lead, dev, senior) via `resolve-agent-model.sh` with config.json + model-profiles.json. Abort on failure.
- Display: `◆ Spawning Lead (${LEAD_MODEL}) for fix triage...`
- Spawn yolo-lead as subagent via Task tool. **Add `model: "${LEAD_MODEL}"` parameter.**
```
Quick fix triage. Fix request: {fix description}. Working dir: {pwd}.
Dev model: ${DEV_MODEL}. Senior model: ${SENIOR_MODEL}.
(1) Triage scope: read relevant files, classify as trivial (single-file, <10 lines changed, obvious fix) or needs-spec (multi-file, risky, or unclear boundaries).
(2) TRIVIAL path: Spawn yolo-dev subagent (model: DEV_MODEL) with inline spec: task, file(s), change. Dev commits: fix(quick): {brief}.
(3) NEEDS-SPEC path: Spawn yolo-senior subagent (model: SENIOR_MODEL) to write brief spec. Senior spawns yolo-dev (model: DEV_MODEL) with spec. Senior reviews Dev output. Dev commits: fix({scope}): {brief}.
(4) If Dev or Senior reports ambiguity or scope too large, report back: fix cannot be applied, recommend /yolo:go --execute.
(5) Report back: commit hash, files changed, path used (trivial/needs-spec).
```
4. **Verify + present:** Check `git log --oneline -1`.

Committed:
```
✓ Fix applied
  {commit hash} {commit message}
  Files: {changed files}
  Path: {Trivial | Lead->Senior->Dev}
```
Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/suggest-next.sh fix` and display.

Lead reported cannot-apply:
```
⚠ Fix could not be applied automatically
  {reason from Lead}
```
Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/suggest-next.sh debug` and display.

## Escalation

- Dev -> Senior: Dev reports ambiguity or blocker. Senior resolves within spec authority.
- Senior -> Lead: Senior cannot resolve (scope unclear, multi-system impact). Lead decides: adjust scope or escalate.
- Lead -> go.md: If fix scope exceeds quick-fix boundary (>3 files, needs architecture review, or risk is high), Lead reports back "scope too large" and recommends /yolo:go --execute.
- No agent contacts user directly. go.md (Owner proxy) handles all user communication.

## Output Format

Per @${CLAUDE_PLUGIN_ROOT}/references/yolo-brand-essentials.toon -- single-line box, ✓/⚠ symbols, Next Up, no ANSI.