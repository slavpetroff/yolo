---
name: yolo:vibe
description: "The one command. Detects state, parses intent, routes to any lifecycle mode -- bootstrap, scope, plan, execute, verify, discuss, archive, and more."
argument-hint: "[intent or flags] [--plan] [--execute] [--verify] [--discuss] [--assumptions] [--scope] [--add] [--insert] [--remove] [--archive] [--yolo] [--effort=level] [--skip-audit] [--plan=NN] [N]"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, WebFetch
disable-model-invocation: true
---

# YOLO Vibe: $ARGUMENTS

## Context

Working directory: `!`pwd``
Plugin root: `!`echo ${CLAUDE_PLUGIN_ROOT:-$(ls -1d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/yolo-marketplace/yolo/* 2>/dev/null | (sort -V 2>/dev/null || sort -t. -k1,1n -k2,2n -k3,3n) | tail -1)}``

Pre-computed state (via phase-detect):
```
!`"$HOME/.cargo/bin/yolo" phase-detect 2>/dev/null || echo "phase_detect_error=true"`
```

Config:
```
!`cat .yolo-planning/config.json 2>/dev/null || echo "No config found"`
```

## Input Parsing

Three paths, evaluated in order. **Flags skip confirmation gate** (explicit intent).

### Path 1: Flags

| Flag | Mode | Flag | Mode |
|------|------|------|------|
| `--plan [N]` | Plan | `--scope` | Scope |
| `--execute [N]` | Execute | `--add "desc"` | Add Phase |
| `--discuss [N]` | Discuss | `--insert N "desc"` | Insert Phase |
| `--assumptions [N]` | Assumptions | `--remove N` | Remove Phase |
| `--verify [N]` | Verify | `--archive` | Archive |

Modifiers: `--effort <level>`, `--skip-audit`, `--yolo` (skip gates + auto-loop), `--plan=NN` (single plan), bare `N` (target phase).

### Path 2: Natural language

No flags? Interpret intent from keywords: discuss/talk -> Discuss, assume/what-if -> Assumptions, plan/scope -> Plan, build/execute/ship -> Execute, verify/test/uat -> Verify, add/insert/remove -> Phase Mutation, done/archive -> Archive. Ambiguous -> AskUserQuestion. ALWAYS confirm via AskUserQuestion.

### Path 3: State detection (no args)

| Condition | Mode |
|---|---|
| `planning_dir_exists=false` | Init redirect (no confirm) |
| `project_exists=false` | Bootstrap |
| `phase_count=0` | Scope |
| `next_phase_state=needs_plan_and_execute` | Plan + Execute |
| `next_phase_state=needs_execute` | Execute |
| `next_phase_state=all_done` | Archive |

**all_done + NL describing new work:** route to Add Phase (not Archive).

### Confirmation Gate

AskUserQuestion before executing (recommended action + alternatives). Exceptions: `--yolo` skips gates, flags skip confirmation.

## Mode Dispatch

### Init Redirect
If `planning_dir_exists=false`: display "Run /yolo:init first to set up your project." STOP.

### Bootstrap
Read `${CLAUDE_PLUGIN_ROOT}/skills/vibe-modes/bootstrap.md` and follow its instructions.

### Scope
Read `${CLAUDE_PLUGIN_ROOT}/skills/vibe-modes/scope.md` and follow its instructions.

### Discuss
Guard: Initialized, phase exists. Auto-detect: first phase without `*-CONTEXT.md`.
For codebase exploration during discussion, use Task tool with Explore subagent.
1. Determine target phase from $ARGUMENTS or auto-detection.
2. Read `${CLAUDE_PLUGIN_ROOT}/skills/discussion-engine/SKILL.md` and follow its protocol.
3. Run `"$HOME/.cargo/bin/yolo" suggest-next vibe`.

### Assumptions
Read `${CLAUDE_PLUGIN_ROOT}/skills/vibe-modes/assumptions.md` and follow its instructions.

### Plan
Read `${CLAUDE_PLUGIN_ROOT}/skills/vibe-modes/plan.md` and follow its instructions.

### Execute
Before delegating: parse phase number, --effort, --plan=NN. Run guards (not initialized -> STOP, no PLAN.md -> STOP, all done -> WARN). If `config_context_compiler=true`, compile dev/qa context.
Then Read `${CLAUDE_PLUGIN_ROOT}/skills/execute-protocol/SKILL.md` and follow its instructions.

### Verify
Guard: Initialized, phase has `*-SUMMARY.md`. Auto-detect: first phase with SUMMARY but no UAT.
Read `${CLAUDE_PLUGIN_ROOT}/commands/verify.md` and follow its instructions.

### Add/Insert/Remove Phase
Read `${CLAUDE_PLUGIN_ROOT}/skills/vibe-modes/phase-mutation.md` and follow its instructions for the specific mutation type.

### Archive
Read `${CLAUDE_PLUGIN_ROOT}/skills/vibe-modes/archive.md` and follow its instructions.

### Pure-Vibe Phase Loop
After Execute (autonomy=pure-vibe only): auto-continue to next phase (Plan + Execute) until `all_done` or error. Other levels: STOP.
**CRITICAL:** Between iterations, shut down ALL agents from previous phase before spawning new ones.

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/yolo-brand-essentials.md for all output.
Symbols: ◆ running, ✓ complete, ✗ failed, ○ skipped. Phase Banner (double-line box), Metrics Block, Next Up Block, no ANSI codes.
Run `"$HOME/.cargo/bin/yolo" suggest-next vibe {result}` for Next Up suggestions.
