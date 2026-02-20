---
phase: 1
plan: 03
title: "Migrate 4 bootstrap scripts to Rust CLI subcommands"
status: complete
---

## What Was Built

Four Rust CLI subcommands replacing the bash bootstrap scripts:

- `yolo bootstrap project <output> <name> <description> [core_value]` -- generates PROJECT.md with requirements sections, constraints, and key decisions table
- `yolo bootstrap requirements <output> <discovery_json> [research_file]` -- generates REQUIREMENTS.md from discovery.json inferred array, updates discovery with research metadata
- `yolo bootstrap roadmap <output> <project_name> <phases_json>` -- generates ROADMAP.md with progress table, phase list, detail sections, and creates phase directories with slugified names
- `yolo bootstrap state <output> <project_name> <milestone_name> <phase_count>` -- generates STATE.md preserving existing Todos and Key Decisions from prior milestones

The existing `yolo bootstrap` (CLAUDE.md) continues to work via fall-through dispatch.

## Tasks

| # | Title | Commit |
|---|-------|--------|
| 1 | Implement bootstrap project subcommand | 557e733 |
| 2 | Implement bootstrap requirements subcommand | db7749d |
| 3 | Implement bootstrap roadmap subcommand | 629adbe |
| 4 | Implement bootstrap state subcommand | a1ac5d4 |
| 5 | Wire bootstrap subcommands into CLI router | fb57ec5 |

## Files Modified

- `yolo-mcp-server/src/commands/bootstrap_project.rs` (new, 116 lines)
- `yolo-mcp-server/src/commands/bootstrap_requirements.rs` (new, 235 lines)
- `yolo-mcp-server/src/commands/bootstrap_roadmap.rs` (new, 262 lines)
- `yolo-mcp-server/src/commands/bootstrap_state.rs` (new, 202 lines)
- `yolo-mcp-server/src/commands/mod.rs` (added 4 module declarations)
- `yolo-mcp-server/src/cli/router.rs` (added 4 imports + subcommand dispatch in bootstrap arm)

## Test Results

- 32 bootstrap tests total (4 project + 7 requirements + 6 roadmap + 6 state + 9 existing bootstrap_claude)
- 0 failures across both binary targets

## Deviations

None.
