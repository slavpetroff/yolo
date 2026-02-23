---
description: Apply a quick fix or small change with commit discipline. Turbo mode -- no planning ceremony.
argument-hint: "<description of what to fix or change>"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, WebFetch
---

# YOLO Fix: $ARGUMENTS

## Context
Working directory: `!`pwd``
Plugin root: `!`echo ${CLAUDE_PLUGIN_ROOT:-$(ls -1d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/yolo-marketplace/yolo/* 2>/dev/null | (sort -V 2>/dev/null || sort -t. -k1,1n -k2,2n -k3,3n) | tail -1)}``
Config: Pre-injected by SessionStart hook.

## Guard
- Not initialized (no .yolo-planning/ dir): STOP "Run /yolo:init first."
- No $ARGUMENTS: STOP "Usage: /yolo:fix \"description of what to fix\""

## Steps
1. **Parse:** Entire $ARGUMENTS (minus flags) = fix description.

2. **Milestone:** If `.yolo-planning/ACTIVE` exists, use milestone-scoped
   `STATE_PATH`. Else `.yolo-planning/STATE.md`.

3. **Spawn Dev:** Resolve model first:
    ```bash
    DEV_MODEL=$("$HOME/.cargo/bin/yolo" resolve-model dev .yolo-planning/config.json ${CLAUDE_PLUGIN_ROOT}/config/model-profiles.json)
    DEV_MAX_TURNS=$("$HOME/.cargo/bin/yolo" resolve-turns dev .yolo-planning/config.json turbo)
    ```

    Spawn yolo-dev as subagent via Task tool with `model: "${DEV_MODEL}"` and
    `maxTurns: ${DEV_MAX_TURNS}`:

    ```text
    Quick fix (Turbo mode). Effort: low.
    Task: {fix description}.
    If `.yolo-planning/codebase/META.md` exists, read CONVENTIONS.md, PATTERNS.md, STRUCTURE.md, and DEPENDENCIES.md (whichever exist) from `.yolo-planning/codebase/` to bootstrap codebase understanding before implementing.
    Implement directly. One atomic commit: fix(quick): {brief description}.
    No SUMMARY.md or PLAN.md needed.
    If tests reveal pre-existing failures unrelated to this fix, list them in your response under a "Pre-existing Issues" heading with test name, file, and failure message.
    If ambiguous or requires architectural decisions, STOP and report back.
    ```

4. **Verify + present:** Check `git log --oneline -1`. Check Dev response for pre-existing issues.
    Committed, no discovered issues:

    ```text
    ✓ Fix applied
      {commit hash} {commit message}
      Files: {changed files}
    ```

    Run `"$HOME/.cargo/bin/yolo" suggest-next fix` and display.

    Committed, with discovered issues (Dev reported pre-existing failures):

    Follow discovered issues display protocol: @references/discovered-issues-protocol.md

    ```text
    ✓ Fix applied
      {commit hash} {commit message}
      Files: {changed files}
    ```

    If discovered issues exist, append them after the result box per the protocol above.
    Run `"$HOME/.cargo/bin/yolo" suggest-next fix` and display.

    Dev stopped:

    ```text
    ⚠ Fix could not be applied automatically
      {reason from Dev agent}
    ```

    Run `"$HOME/.cargo/bin/yolo" suggest-next debug` and display.