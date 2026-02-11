---
name: vibe
description: "The one command. Detects state, parses intent, routes to any lifecycle mode -- bootstrap, scope, plan, execute, discuss, archive, and more."
argument-hint: "[intent or flags] [--plan] [--execute] [--discuss] [--assumptions] [--scope] [--add] [--insert] [--remove] [--archive] [--yolo] [--effort=level] [--skip-qa] [--skip-audit] [--plan=NN] [N]"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, WebFetch
disable-model-invocation: true
---

# VBW Vibe: $ARGUMENTS

## Context

Working directory: `!`pwd``

Pre-computed state (via phase-detect.sh):
```
!`bash ${CLAUDE_PLUGIN_ROOT}/scripts/phase-detect.sh 2>/dev/null || echo "phase_detect_error=true"`
```

Config:
```
!`cat .vbw-planning/config.json 2>/dev/null || echo "No config found"`
```

## Input Parsing

Three input paths, evaluated in order:

### Path 1: Flag detection

Check $ARGUMENTS for flags. If any mode flag is present, go directly to that mode:
- `--plan [N]` -> Plan mode
- `--execute [N]` -> Execute mode
- `--discuss [N]` -> Discuss mode
- `--assumptions [N]` -> Assumptions mode
- `--scope` -> Scope mode
- `--add "desc"` -> Add Phase mode
- `--insert N "desc"` -> Insert Phase mode
- `--remove N` -> Remove Phase mode
- `--archive` -> Archive mode

Behavior modifiers (combinable with mode flags):
- `--effort <level>`: thorough|balanced|fast|turbo (overrides config)
- `--skip-qa`: skip post-build QA
- `--skip-audit`: skip pre-archive audit
- `--yolo`: skip all confirmation gates, auto-loop remaining phases
- `--plan=NN`: execute single plan (bypasses wave grouping)
- Bare integer `N`: targets phase N (works with any mode flag)

If flags present: skip confirmation gate (flags express explicit intent).

### Path 2: Natural language intent

If $ARGUMENTS present but no flags detected, interpret user intent:
- Discussion keywords (talk, discuss, explore, think about, what about) -> Discuss mode
- Assumption keywords (assume, assuming, what if, what are you assuming) -> Assumptions mode
- Planning keywords (plan, scope, break down, decompose, structure) -> Plan mode
- Execution keywords (build, execute, run, do it, go, make it, ship it) -> Execute mode
- Phase mutation keywords (add, insert, remove, skip, drop, new phase) -> relevant Phase Mutation mode
- Completion keywords (done, ship, archive, wrap up, finish, complete) -> Archive mode
- Ambiguous -> AskUserQuestion with 2-3 contextual options

ALWAYS confirm interpreted intent via AskUserQuestion before executing.

### Path 3: State detection (no args)

If no $ARGUMENTS, evaluate phase-detect.sh output. First match determines mode:

| Priority | Condition | Mode | Confirmation |
|---|---|---|---|
| 1 | `planning_dir_exists=false` | Init redirect | (redirect, no confirmation) |
| 2 | `project_exists=false` | Bootstrap | "No project defined. Set one up?" |
| 3 | `phase_count=0` | Scope | "Project defined but no phases. Scope the work?" |
| 4 | `next_phase_state=needs_plan_and_execute` | Plan + Execute | "Phase {N} needs planning and execution. Start?" |
| 5 | `next_phase_state=needs_execute` | Execute | "Phase {N} is planned. Execute it?" |
| 6 | `next_phase_state=all_done` | Archive | "All phases complete. Run audit and archive?" |

### Confirmation Gate

Every mode triggers confirmation via AskUserQuestion before executing, with contextual options (recommended action + alternatives).
- **Exception:** `--yolo` skips all confirmation gates. Error guards (missing roadmap, uninitialized project) still halt.
- **Exception:** Flags skip confirmation (explicit intent).
