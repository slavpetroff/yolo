# Roadmap: Teammate API Integration

Milestone: teammate-api-integration
Started: 2026-02-16

## Milestone Description

Replace YOLO's file-based multi-department coordination and Task-tool-only agent spawning with Claude Code's native Teammate API (spawnTeam, SendMessage, TaskCreate/TaskUpdate/TaskList). Target: 3 department teams x N agents for true parallel execution (21+ concurrent agents vs. current ~7 sequential). Must maintain backward compatibility with single-department (backend-only) mode using Task tool.

## Phases

### Phase 1: team-abstraction-layer
**Goal:** Build a spawn abstraction that can route to either Task tool or Teammate API based on configuration, with team lifecycle management (create, track, shutdown, cleanup).
**Status:** [x] Complete
**Requirements:** REQ-03 (foundation)
**Success Criteria:**
- spawn-agent.sh (or equivalent prompt instructions) can resolve whether to use Task tool or Teammate API based on config flag
- Team lifecycle operations (create team, register teammate, shutdown teammate, delete team) are documented as prompt patterns in agent instructions
- Config gains `team_mode: "task"|"teammate"|"auto"` flag with "task" as default (no behavior change until explicitly enabled)
- All 209+ existing tests pass unchanged when team_mode="task"
- Agent prompt templates include conditional Teammate API instructions (spawnTeam, SendMessage) that activate only when team_mode="teammate"
**Dependencies:** None (first phase)

### Phase 2: department-teams
**Goal:** Convert multi-department orchestration from file-based coordination (dept-orchestrate.sh polling + sentinel files) to Teammate API native teams -- one team per department, Lead as team lead, specialists as teammates.
**Status:** [x] Complete
**Requirements:** REQ-03 (core implementation)
**Success Criteria:**
- When team_mode="teammate" and multi_dept=true, go.md spawns one Teammate API team per active department (up to 3 teams: backend, frontend, uiux)
- Department Leads are team leads; Architect, Senior, Dev, Tester, QA are teammates within their department team
- Intra-department communication uses SendMessage instead of file artifacts for coordination signals (handoff readiness, escalation, status updates)
- Inter-department gates remain file-based -- dept-gate.sh and dept-status.sh unchanged (SendMessage is intra-team only, cannot cross team boundaries)
- All 23 agent files (4 Phase 1 + 19 Phase 2) have Teammate API conditional sections with team_mode=teammate guard
- File-based coordination remains as fallback when team_mode="task" -- zero regression
- Escalation chain preserved: Dev -> Senior -> Lead -> Architect -> Owner -> User (via SendMessage within team, then cross-team to Owner)
**Dependencies:** Phase 1

### Phase 3: shared-task-coordination
**Goal:** Replace YOLO's per-plan sequential execution with Teammate API's shared task list for parallel task execution within a department, and cross-department task dependency tracking.
**Status:** [ ] Not started
**Requirements:** REQ-03 (parallel execution target)
**Success Criteria:**
- Within each department team, plan.jsonl tasks are mapped to TaskCreate items on the shared task list with proper dependency chains (from plan `d` field)
- Teammates (Dev agents) self-claim available tasks from shared list instead of sequential assignment by Lead
- Task dependencies from plan.jsonl `d` field map to TaskCreate dependency parameters so blocked tasks auto-unblock on completion
- Cross-phase dependencies (`xd` field) are tracked and validated before task availability
- Measured improvement: 2+ Dev agents executing tasks concurrently within a single department (vs. current sequential 1-at-a-time)
- Summary.jsonl generation aggregates results from multiple parallel Dev completions
- All existing verification gates (entry/exit per step) still enforce artifact presence before step transitions
**Dependencies:** Phase 2

### Phase 4: graceful-degradation
**Goal:** Ensure robust fallback behavior when Teammate API is unavailable, teams fail to spawn, or teammates become unresponsive. Handle the experimental nature of the API with production-grade resilience.
**Status:** [ ] Not started
**Requirements:** REQ-03 (production readiness)
**Success Criteria:**
- If CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS env var is not set, system auto-falls back to team_mode="task" with a logged warning (no crash, no user prompt)
- If spawnTeam fails (API error, timeout, permission issue), the department falls back to Task tool spawning for that department and logs the failure
- If a teammate becomes unresponsive (no SendMessage reply within configurable timeout), Lead reassigns work and spawns replacement via Task tool
- Shutdown protocol implemented: Lead sends shutdown_request to all teammates, waits for shutdown_response, then calls team cleanup
- Session resume (session-start.sh) detects orphaned teams from prior sessions and cleans them up
- team_mode="auto" correctly detects Teammate API availability and selects the optimal mode
- All 209+ existing tests pass in both team_mode="task" and team_mode="teammate" configurations
- Integration tests validate the full fallback cascade: teammate -> task -> error
**Dependencies:** Phase 2, Phase 3

## Progress

| Phase | Name | Plans | Status |
|-------|------|-------|--------|
| 1 | team-abstraction-layer | 4 | Complete |
| 2 | department-teams | 5 | Complete |
| 3 | shared-task-coordination | 5 | Planned |
| 4 | graceful-degradation | 0 | Pending |

## Architecture Notes

### Why 4 Phases (Not 3 or 5)

The decomposition follows the principle of independently testable increments:

1. **Phase 1 (Abstraction)** is pure plumbing -- it adds the routing layer and config without changing any runtime behavior. This is testable in isolation: set team_mode="task" and verify nothing changes.

2. **Phase 2 (Department Teams)** is the core API integration -- converting the file-based coordination to Teammate API messaging. It depends on Phase 1's abstraction layer but can be tested by enabling team_mode="teammate" in a multi-dept project.

3. **Phase 3 (Shared Tasks)** adds the parallel execution capability within teams. This is the highest-value change (21+ concurrent agents) but requires Phase 2's team structure to exist first. It is independently testable: measure concurrent Dev agents per department.

4. **Phase 4 (Degradation)** is separated from the implementation phases because resilience patterns (fallback, retry, cleanup) cut across all the earlier work and are best designed holistically after the happy path works. Combining it with Phase 2 or 3 would bloat those phases and make testing harder.

### Key Architectural Constraints

- **Teammate API is prompt-level, not script-level.** spawnTeam, SendMessage, TaskCreate are Claude Code tools invoked by agents in their prompts, not bash commands. Shell scripts (dept-orchestrate.sh, dept-gate.sh) remain for configuration resolution and state reporting, but coordination signals shift from file sentinels to SendMessage.

- **No nested teams.** Only the session that creates a team can manage it. This means go.md (Owner proxy) creates department teams, and department Leads manage their teams' internal task assignment. Leads cannot create sub-teams for specialists.

- **One team per session limitation.** Since a lead can only manage one team, each department Lead must be a separate session. go.md spawns up to 3 team leads as separate Teammate API instances.

- **Single-department mode unchanged.** When team_mode="task" or only backend is active, the existing Task tool workflow is preserved exactly. The Teammate API is only engaged for multi-department parallel execution.

### Migration Strategy

The migration is additive, not replacement:
- Phase 1 adds the abstraction (no behavior change)
- Phase 2 adds the Teammate API path alongside the existing Task tool path
- Phase 3 enhances the Teammate API path with shared task lists
- Phase 4 ensures the Task tool path is always reachable as fallback

At no point is the Task tool path removed. The system gains a second, more capable coordination mechanism while keeping the proven one as safety net.
