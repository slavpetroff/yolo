---
name: help
description: Display all available VBW commands with descriptions and usage examples.
argument-hint: [command-name]
allowed-tools: Read, Glob
---

# VBW Help $ARGUMENTS

## Behavior

### No arguments: Display complete command reference

Show all VBW commands grouped by lifecycle stage. Mark all commands with ✓.

### With argument: Display detailed command help

Read `${CLAUDE_PLUGIN_ROOT}/commands/{name}.md` and display: name, description, usage, arguments, related commands.

## Command Reference

### Lifecycle (init -> implement -> plan -> execute -> archive)

| Status | Command        | Description                                          |
|--------|----------------|------------------------------------------------------|
| ✓      | /vbw:init      | Set up environment and scaffold .vbw-planning directory |
| ✓      | /vbw:implement [phase] | The one command. Smart router through the full lifecycle. |
| ✓      | /vbw:plan [phase]  | Plan a phase via Lead agent (auto-detects phase) |
| ✓      | /vbw:execute [phase] | Execute phase via Agent Teams (auto-detects phase)|
| ✓      | /vbw:archive   | Close out completed work and archive state           |

### Monitoring

| Status | Command        | Description                                          |
|--------|----------------|------------------------------------------------------|
| ✓      | /vbw:status    | Progress dashboard with Agent Teams task view        |
| ✓      | /vbw:qa [phase]    | Deep verification (auto-detects phase)           |

### Quick Actions

| Status | Command        | Description                                          |
|--------|----------------|------------------------------------------------------|
| ✓      | /vbw:fix       | Quick fix with commit discipline (turbo mode)        |
| ✓      | /vbw:debug     | Systematic bug investigation via Debugger agent      |
| ✓      | /vbw:todo      | Add item to persistent backlog                       |

### Session Management

| Status | Command        | Description                                          |
|--------|----------------|------------------------------------------------------|
| ✓      | /vbw:pause     | Save session notes for next time (state auto-persists) |
| ✓      | /vbw:resume    | Restore project context from .vbw-planning/ state    |

### Codebase & Research

| Status | Command        | Description                                          |
|--------|----------------|------------------------------------------------------|
| ✓      | /vbw:map       | Analyze codebase with parallel Scout teammates       |
| ✓      | /vbw:discuss [phase]   | Gather context before planning (auto-detects phase) |
| ✓      | /vbw:assumptions [phase] | Surface Claude's assumptions (auto-detects phase) |
| ✓      | /vbw:research  | Standalone research task                             |

### Phase Management

| Status | Command           | Description                                       |
|--------|-------------------|---------------------------------------------------|
| ✓      | /vbw:audit        | Audit completion readiness before archiving        |
| ✓      | /vbw:add-phase    | Add phase to end of roadmap                        |
| ✓      | /vbw:insert-phase | Insert urgent phase with renumbering               |
| ✓      | /vbw:remove-phase | Remove future phase with renumbering               |

### Configuration & Meta

| Status | Command        | Description                                          |
|--------|----------------|------------------------------------------------------|
| ✓      | /vbw:skills    | Browse and install community skills from skills.sh   |
| ✓      | /vbw:config    | View/modify settings and skill-hook wiring           |
| ✓      | /vbw:help      | This help guide                                      |
| ✓      | /vbw:whats-new | View changelog and recent updates                    |
| ✓      | /vbw:update    | Update VBW to latest version                         |
| ✓      | /vbw:uninstall | Clean removal — statusline, settings, project data   |

## Architecture Notes

**Agent Teams:** /vbw:execute creates a team with Dev teammates for parallel plan execution. /vbw:map creates a team with Scout teammates for parallel codebase analysis. The session IS the team lead.

**Hooks:** Continuous verification runs automatically via PostToolUse, TaskCompleted, and TeammateIdle hooks. /vbw:qa is for deep, on-demand verification only.

**Skill-Hook Wiring:** Use /vbw:config to map skills to hook events (e.g., lint-fix on file writes).

## Getting Started

➜ Quick Start
  /vbw:init -- Set up environment and scaffold .vbw-planning
  /vbw:implement -- Plan and execute (auto-detects everything)
  /vbw:qa -- Deep verify (auto-detects phase)
  /vbw:archive -- Close out completed work

  Or use /vbw:plan + /vbw:execute separately for more control.

Run `/vbw:help <command>` for detailed help on any command.

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md:
- Double-line box for help header
- ✓ for available commands
- ➜ for Getting Started steps
- No ANSI color codes
