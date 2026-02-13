# Architecture

## System Overview

YOLO is a Claude Code plugin that implements a structured development lifecycle: bootstrap -> scope -> plan -> execute -> verify -> archive. The architecture is prompt-driven -- markdown files ARE the application logic, interpreted by Claude Code's LLM at runtime.

## Core Architecture Layers

### Layer 1: Plugin Registration

```
.claude-plugin/plugin.json   -- Plugin identity (name, version, author)
.claude-plugin/marketplace.json -- Distribution metadata
hooks/hooks.json              -- Event hook declarations
```

The plugin is discovered via the Claude Code marketplace system. Hooks are registered for 10 event types (PreToolUse, PostToolUse, SessionStart, SubagentStart, SubagentStop, TeammateIdle, TaskCompleted, PreCompact, Stop, UserPromptSubmit, Notification).

### Layer 2: Command Dispatch

```
commands/*.md  -- 20 slash commands (kebab-case .md files)
```

Each command file contains:
- YAML frontmatter: name, description, argument-hint, allowed-tools, disable-model-invocation
- Template context injection: `!`bash ...`` blocks evaluated at command load time
- Instruction body: markdown interpreted by Claude Code as agent instructions

The primary command is `/yolo:go` which acts as a smart router, detecting project state via `phase-detect.sh` and routing to the appropriate mode (bootstrap, scope, plan, execute, discuss, assumptions, archive, add/insert/remove phase).

### Layer 3: Agent System

```
agents/yolo-*.md  -- 6 agent definitions
```

| Agent | Role | Model | Tools | maxTurns |
|-------|------|-------|-------|----------|
| yolo-lead | Planning, phase decomposition | inherit | Read, Glob, Grep, Write, Bash, WebFetch | 50 |
| yolo-dev | Task execution, commits | inherit | All (default) | 75 |
| yolo-qa | Verification (read-only) | sonnet | Read, Grep, Glob, Bash | 25 |
| yolo-scout | Research (read-only) | haiku | Read, Grep, Glob, WebSearch, WebFetch | 15 |
| yolo-debugger | Bug investigation | inherit | All (default) | 40 |
| yolo-architect | Requirements to roadmap | inherit | Read, Glob, Grep, Write | 30 |

Model resolution: `resolve-agent-model.sh` reads model_profile from config.json, loads preset from model-profiles.json, applies per-agent overrides. Three presets: quality (opus-heavy), balanced (sonnet), budget (haiku for QA/Scout).

### Layer 4: Hook Pipeline

All hooks route through `hook-wrapper.sh` (DXP-01 pattern):
1. Resolve target script from plugin cache via `ls | sort -V | tail -1`
2. Execute script, passing stdin (JSON context)
3. Log failures to `.yolo-planning/.hook-errors.log`
4. Always exit 0 (graceful degradation)

Hook scripts:
- **PreToolUse**: security-filter.sh (block sensitive files), file-guard.sh (block undeclared files), skill-hook-dispatch.sh
- **PostToolUse**: validate-summary.sh, validate-frontmatter.sh, validate-commit.sh, state-updater.sh, skill-hook-dispatch.sh
- **SessionStart**: session-start.sh (state detection, update check, cache cleanup, migration), map-staleness.sh, post-compact.sh
- **SubagentStart/Stop**: agent-start.sh, agent-stop.sh, validate-summary.sh
- **TeammateIdle**: qa-gate.sh (structural completion checks)
- **TaskCompleted**: task-verify.sh
- **PreCompact**: compaction-instructions.sh
- **Stop**: session-stop.sh
- **UserPromptSubmit**: prompt-preflight.sh
- **Notification**: notification-log.sh

### Layer 5: State Management

```
.yolo-planning/
  config.json          -- Runtime configuration
  PROJECT.md           -- Project identity
  REQUIREMENTS.md      -- Requirement catalog with REQ-IDs
  ROADMAP.md           -- Phase list, goals, success criteria, progress table
  STATE.md             -- Current phase position, progress, velocity
  ACTIVE               -- Active milestone slug (if multi-milestone)
  .execution-state.json -- Runtime execution tracking (waves, plan status)
  .cost-ledger.json    -- Per-agent cost attribution
  discovery.json       -- Discovery question/answer history (temporary)
  conventions.json     -- Project conventions (auto-detected + user-defined)
  phases/
    {NN}-{slug}/
      {NN}-{MM}-PLAN.md      -- Plan artifact
      {NN}-{MM}-SUMMARY.md   -- Execution summary
      {NN}-VERIFICATION.md   -- QA verification report
      {NN}-CONTEXT.md        -- Phase discussion context
      .context-{role}.md     -- Compiled context per agent role
  codebase/            -- Codebase mapping documents (9 files + META.md)
  milestones/          -- Archived completed milestones
  gsd-archive/         -- Imported GSD work history (if migrated)
```

### Layer 6: Context Compilation

`compile-context.sh` produces role-specific context files before agent spawning:
- **lead**: Phase goal, success criteria, matching requirements, active decisions
- **dev**: Phase goal, conventions, skill references (bundled from SKILL.md files)
- **qa**: Phase goal, success criteria, requirements to verify, conventions

## Data Flow

```
User Input
    |
    v
/yolo:go (smart router)
    |
    v
phase-detect.sh (state detection)
    |
    v
Mode Selection (bootstrap|scope|plan|execute|discuss|archive|...)
    |
    v
compile-context.sh (role-specific context)
    |
    v
resolve-agent-model.sh (model selection)
    |
    v
Agent Spawn (yolo-lead|yolo-dev|yolo-qa|yolo-scout|yolo-debugger)
    |
    v
Hooks (continuous verification)
    |
    v
State Updates (state-updater.sh -> STATE.md, ROADMAP.md, .execution-state.json)
    |
    v
suggest-next.sh (contextual next action)
```

## Key Design Decisions

1. **Prompt as code**: Commands are markdown files interpreted by the LLM, not compiled code
2. **Zero-dependency**: No npm, no build step, no runtime beyond bash + jq
3. **Graceful degradation**: All hooks exit 0, failures logged but never block sessions
4. **Plugin cache resolution**: `ls | sort -V | tail -1` pattern for version-safe cache access
5. **Fail-closed security**: security-filter.sh exits 2 (block) on parse errors
6. **Fail-open file guard**: file-guard.sh exits 0 on errors, only blocks definitive violations
7. **State on disk**: All state in .yolo-planning/ files, not in memory. Compaction-resilient.
8. **Plugin isolation**: YOLO and GSD have mutual file access blocks when both active
