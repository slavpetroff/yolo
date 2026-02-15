---
name: debug
description: Investigate a bug using the Lead-dispatched Debugger agent hierarchy.
argument-hint: "<bug description or error message>"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, WebFetch
disable-model-invocation: true
---

# YOLO Debug: $ARGUMENTS

## Context

Working directory: `!`pwd``

Recent commits:
```
!`git log --oneline -10 2>/dev/null || echo "No git history"`
```

## Guard

- Not initialized (no .yolo-planning/ dir): STOP "Run /yolo:init first."
- No $ARGUMENTS: STOP "Usage: /yolo:debug \"description of the bug or error message\""

## Steps

1. **Parse + effort:** Entire $ARGUMENTS = bug description. Map effort: thorough=high, balanced/fast=medium, turbo=low. Read `${CLAUDE_PLUGIN_ROOT}/references/effort-profile-{profile}.md`.

2. **Classify ambiguity:** 2+ signals = ambiguous: "intermittent/sometimes/random/unclear/inconsistent/flaky/sporadic/nondeterministic" keywords, multiple root cause areas, generic/missing error, previous reverted fixes in git log. Overrides: `--competing`/`--parallel` = always ambiguous; `--serial` = never.

3. **Spawn Lead:**
- Resolve Lead model:
  ```bash
  LEAD_MODEL=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-model.sh lead .yolo-planning/config.json ${CLAUDE_PLUGIN_ROOT}/config/model-profiles.json)
  if [ $? -ne 0 ]; then echo "$LEAD_MODEL" >&2; exit 1; fi
  ```
- Resolve Debugger model:
  ```bash
  DEBUGGER_MODEL=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-model.sh debugger .yolo-planning/config.json ${CLAUDE_PLUGIN_ROOT}/config/model-profiles.json)
  if [ $? -ne 0 ]; then echo "$DEBUGGER_MODEL" >&2; exit 1; fi
  ```
- Display: `◆ Spawning Lead (${LEAD_MODEL}) for bug investigation...`
- Spawn yolo-lead as subagent via Task tool. **Add `model: "${LEAD_MODEL}"` parameter.**
```
Bug investigation dispatch. Effort: {effort}. Ambiguity: {ambiguous|clear}.
Bug report: {description}. Working dir: {pwd}. Debugger model: ${DEBUGGER_MODEL}.
You are the Lead dispatcher for a debug investigation.
(1) Scope the bug: identify affected codebase area, read relevant files, formulate hypothesis structure.
(2) Choose dispatch mode: if effort=high AND ambiguous, use Path A (competing hypotheses); else Path B (standard).
PATH A: Generate 3 hypotheses (cause, area, confirming evidence). Spawn 3 yolo-debugger subagents via Task tool (model: ${DEBUGGER_MODEL} each). Each gets bug report + ONE hypothesis only. Wait for debugger_report from each. Synthesize: strongest evidence + highest confidence wins.
PATH B: Spawn 1 yolo-debugger subagent (model: ${DEBUGGER_MODEL}). Give full bug report. Wait for debugger_report.
(3) After Debugger(s) complete: if fix was applied by Debugger, verify commit exists. If fix needed but not applied: trivial fix -> spawn yolo-dev directly with inline spec; complex fix -> report back with recommendation.
(4) Report results back: root cause, fix status, files modified.
```

4. **Present:** Per @${CLAUDE_PLUGIN_ROOT}/references/yolo-brand-essentials.toon:
```
┌──────────────────────────────────────────┐
│  Bug Investigation Complete              │
└──────────────────────────────────────────┘

  Mode:       {Lead-dispatched: "Competing Hypotheses (3 parallel)" | "Standard (single debugger)"}
  Issue:      {one-line summary}
  Root Cause: {from report}
  Fix:        {commit hash + message, or "No fix applied"}

  Files Modified: {list}

➜ Next: /yolo:status -- View project status
```
Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/suggest-next.sh debug` and display.

## Escalation

- Debugger -> Lead: Debugger reports findings via debugger_report schema. Debugger NEVER presents results to user.
- Lead -> go.md: Lead synthesizes Debugger findings, presents results to go.md (Owner proxy).
- Architectural fix: If Debugger recommends fix that touches >3 files or changes interfaces, Lead escalates to Architect via escalation schema before applying.
- Trivial fix (1-2 lines, obvious): Debugger applies directly.
- Standard fix: Lead spawns Dev with inline spec.
- Complex fix: Lead escalates to Senior for spec, Dev implements.
