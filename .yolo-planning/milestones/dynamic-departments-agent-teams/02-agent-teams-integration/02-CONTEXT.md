# Phase 2 Context: Agent Teams Integration

## Vision
Replace Task-only agent spawning in multi-department mode with Claude Code's Teammate API (spawnTeam, SendMessage, TaskCreate/TaskList). One team per department with Lead + specialists. Per-phase lifecycle (spawn at start, shutdown at end).

## Requirements
- REQ-03: Agent teams via Teammate API for multi-dept mode

## User Decisions
- **Coordination model:** TaskList + SendMessage — departments use shared task list AND direct messages between Leads for handoff coordination
- **Team lifecycle:** Per-phase teams — spawn at phase start, graceful shutdown at phase end. Clean slate each phase.

## Success Criteria (from ROADMAP.md)
- Multi-dept execution uses spawnTeam per department
- Department Leads spawn as team leads with own specialist teammates
- Teams coordinate via shared TaskCreate/TaskList + SendMessage for handoff
- 3 teams can run in parallel (21+ total agent capacity)
- Graceful shutdown via SendMessage shutdown_request

## Technical Context
- Current multi-dept code is in: references/execute-protocol.md, references/multi-dept-protocol.md, references/cross-team-protocol.md
- Current agent spawning: Task tool only (one agent per invocation)
- Teammate API: Teammate tool (spawnTeam, cleanup), SendMessage tool (message, broadcast, shutdown_request/response), Task tools (TaskCreate, TaskList, TaskGet, TaskUpdate)
- Phase 1 delivered: dynamic department personas, project type detection, compile-context integration

## Constraints
- Zero-dependency design: no package.json, npm, or build step
- All scripts target bash
- Existing single-dept mode (Task tool) must remain functional as fallback
- Department workflow order: UX first → FE+BE parallel → Integration QA → Owner Sign-off
