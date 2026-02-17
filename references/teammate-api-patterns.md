# Teammate API Patterns

This file documents all Teammate API tool patterns used by agents when team_mode=teammate. Referenced by agent prompt files via @references/teammate-api-patterns.md inside conditional blocks. When team_mode=task, these patterns are ignored and agents use the Task tool instead.

## Activation Guard

The conditional: team_mode=teammate is set by resolve-team-mode.sh (reads config, validates agent_teams=true, checks CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS env var). When team_mode=task (default), all patterns in this file are inactive. Agents use Task tool for spawning and file-based communication for coordination.

The relationship: agent_teams=true (feature flag) + team_mode=teammate (spawn strategy) = Teammate API active. resolve-team-mode.sh validates this combination per C2 resolution.

## Team Lifecycle (Lead only)

This section is for Lead agents ONLY (yolo-lead, yolo-fe-lead, yolo-ux-lead in Phase 2).

### Creating a Team (spawnTeam)

Lead calls spawnTeam with team name following convention: `yolo-{dept}` (e.g., yolo-backend, yolo-frontend, yolo-uiux). Description: `{Dept} engineering team for phase {N}: {phase-name}`.

```
spawnTeam:
  name: "yolo-backend"
  description: "Backend engineering team for phase 01: team-abstraction-layer"
```

One team per department. No nested teams (API constraint). Lead is automatically the team lead.

### Registering Teammates

After team creation, Lead registers teammates by role. Full roster: architect, senior, dev, tester, qa, qa-code, security.

Registration is on-demand at workflow step boundaries (not all-at-once at team creation):

| Step | Agent(s) Registered | Rationale |
|------|---------------------|----------|
| 2 | architect | Receives design context, produces architecture.toon |
| 4 | senior | Receives architecture, enriches plan specs |
| 6 | dev | Receives enriched specs, implements tasks |
| 5 | tester | Receives plan ts fields, writes failing tests (TDD RED) |
| 8 | qa, qa-code | Verification after implementation complete |
| 9 | security | Security audit after QA passes |

Registration order within a step: architect before senior before dev (earlier teammates may need context before later ones begin). Phase 2 agents (tester, qa, qa-code, security) are registered only when their workflow step begins, reducing team size during early steps.

### Shutdown Protocol

Two-phase shutdown with timeout handling and verification:

**Phase 1: Request**
1. Lead sends `shutdown_request` message to ALL registered teammates via SendMessage.
2. Include `deadline_seconds` (default: 30) and `reason` (phase_complete, timeout, or error).
3. Start a deadline timer for each teammate.

**Phase 2: Collection**
4. Collect `shutdown_response` from each teammate.
5. For each response, check `status` field:
   - `clean`: Teammate completed work and committed artifacts. Ideal outcome.
   - `in_progress`: Teammate could not finish within deadline. Log pending_work to summary.jsonl `dv` (deviations) field.
   - `error`: Teammate encountered an error during shutdown. Log error details.
6. **Timeout handling:** If a teammate does not respond within `deadline_seconds`:
   - Log: "[SHUTDOWN] Timeout: {agent_id} did not respond within {deadline_seconds}s."
   - Mark teammate as timed_out in shutdown tracking.
   - Do NOT block on the non-responsive teammate -- proceed with other responses.
7. **Verification checklist:** After deadline expires, Lead verifies:
   - All teammates either responded or timed out (no unaccounted agents).
   - All `artifacts_committed: true` responses are verified via `git status` (clean for team files).
   - Any `in_progress` work is logged to summary.jsonl deviations.
8. **Error recovery:** If the shutdown protocol itself fails (e.g., SendMessage unavailable):
   - Lead force-proceeds with artifact verification (git status, summary.jsonl).
   - Lead logs: "[SHUTDOWN] Protocol failed, force-proceeding with cleanup."
   - Any uncommitted work is logged as deviation.

shutdown_request schema:
```json
{
  "type": "shutdown_request",
  "reason": "phase_complete | timeout | error",
  "deadline_seconds": 30
}
```

shutdown_response schema:
```json
{
  "type": "shutdown_response",
  "status": "clean | in_progress | error",
  "pending_work": [],
  "artifacts_committed": true
}
```

### Team Cleanup

After all teammates respond to shutdown OR after timeout:
- Lead verifies all artifacts are committed (git status clean for team files)
- Lead writes final summary artifacts
- Team is automatically cleaned up when Lead's session ends
- If timeout: Lead logs incomplete work in summary.jsonl `dv` (deviations) field

## Intra-Team Communication (SendMessage)

Patterns for communication WITHIN a department team. All use SendMessage tool.

### Dev -> Senior (Progress)

When: After completing each task in a plan.
Schema: Use existing `dev_progress` schema from references/handoff-schemas.md.
Example:
```json
{
  "type": "dev_progress",
  "task": "01-01/T3",
  "plan_id": "01-01",
  "commit": "abc1234",
  "status": "complete",
  "concerns": []
}
```
Note: In task mode, Dev returns this via Task tool result. In teammate mode, Dev sends via SendMessage to Senior's teammate ID.

### Dev -> Senior (Blocker/Escalation)

When: Dev is blocked by spec ambiguity, missing dependency, or architectural issue.
Schema: Use existing `dev_blocker` schema from references/handoff-schemas.md.
Example:
```json
{
  "type": "dev_blocker",
  "task": "01-02/T1",
  "plan_id": "01-02",
  "blocker": "Dependency module from plan 01-01 not yet committed",
  "needs": "01-01 to complete first",
  "attempted": ["Checked git log for 01-01 commits"]
}
```
Critical: Dev sends to Senior ONLY. Never to Lead or Architect (unchanged from task mode).

### Senior -> Lead (Review Result)

When: After completing design review or code review.
Schema: Use existing `senior_spec` (design review) or `code_review_result` (code review) from references/handoff-schemas.md.

### Senior -> Dev (Review Changes)

When: Code review requests changes.
Schema: Use existing `code_review_changes` from references/handoff-schemas.md.
Note: In teammate mode, Senior sends directly to Dev's teammate ID instead of spawning a new Task.

### Architect -> Lead (Design)

When: After completing architecture design.
Schema: Use existing `architecture_design` from references/handoff-schemas.md.

## Cross-Team Communication (Lead-to-Lead)

Patterns for communication BETWEEN department teams. Only Leads communicate cross-team.

### Lead -> Lead (API Contract)

When: Frontend needs to negotiate API contract with Backend.
Schema: Use existing `api_contract` from references/handoff-schemas.md.
Note: In teammate mode, cross-team communication still uses file-based handoff artifacts (api-contracts.jsonl, design-handoff.jsonl) because Leads are in DIFFERENT teams. SendMessage only works within a team. Cross-team coordination remains file-based even in teammate mode.

### Lead -> Owner (Department Result)

When: Department completes its 10-step workflow.
Schema: Use existing `department_result` from references/handoff-schemas.md.
Note: Owner is in the shared department, not in any team. Communication uses file-based handoff (.dept-status-{dept}.json) regardless of team_mode.

## Task-Only Agents

Three shared-department agents are EXCLUDED from team membership and always use the Task tool regardless of team_mode:

| Agent | Reason for Exclusion |
|-------|---------------------|
| critic | Runs before architecture (Step 1) -- team does not exist yet. Cross-cutting: reviews all departments. |
| scout | On-demand research agent. Dispatched ad-hoc by Lead. Ephemeral -- no persistent team membership needed. |
| debugger | On-demand investigation agent. Dispatched ad-hoc by Lead. Ephemeral -- no persistent team membership needed. |

These agents:
- Are NEVER registered as teammates via addTeammate
- Are ALWAYS spawned via Task tool by Lead (same as task mode)
- Do NOT have '## Teammate API' sections in their agent files
- Are NOT counted in the 23-agent Teammate API coverage (4 Phase 1 + 19 Phase 2)

Rationale: Making cross-cutting, ephemeral agents permanent teammates would waste team capacity for rarely-used agents. The Task tool provides adequate spawning for their usage pattern.

## Task Coordination (when team_mode=teammate)

> This section is active ONLY when team_mode=teammate.

Lead manages a shared task list for parallel Dev assignment. See `references/handoff-schemas.md` for `task_claim` and `task_complete` message schemas. See `references/artifact-formats.md` for `td` (task_depends) field definition.

### TaskCreate (Plan-to-Task Mapping)

Lead reads plan.jsonl tasks (lines 2+) and creates a shared task list item for each task. Fields:

| Field | Source | Description |
|-------|--------|-------------|
| `task_id` | task `id` field | e.g., "T1" |
| `plan_id` | header `p`-`n` | e.g., "03-01" |
| `action` | task `a` field | Task description |
| `files` | task `f` field | Files this task modifies |
| `status` | hardcoded | Initial value: `"available"` |
| `assignee` | hardcoded | Initial value: `null` |
| `blocked_by` | task `td` field + plan `d` field | Dependency list (see below) |

**Plan-to-task mapping algorithm:**

1. Read plan header (line 1) to extract `p`, `n`, and `d` (plan-level dependencies).
2. For each task (lines 2+), read `id`, `a`, `f`, `td`.
3. Compute `blocked_by`:
   - If task has `td` field: add each entry as `{plan_id}/{td_entry}` (e.g., `"03-01/T1"`).
   - If plan has `d` field (cross-plan deps): for each referenced plan, add ALL task IDs from that plan as `{dep_plan_id}/{task_id}` entries to `blocked_by`.
4. Create shared task list item with all fields.

```json
{
  "task_id": "T3",
  "plan_id": "03-01",
  "action": "Add ## Task-Level Blocking section",
  "files": ["references/teammate-api-patterns.md"],
  "status": "available",
  "assignee": null,
  "blocked_by": ["03-01/T1", "03-01/T2"]
}
```

### TaskList (Available Task Query)

Dev queries for tasks matching ALL of the following:
- `status` = `"available"`
- `assignee` = `null`
- `blocked_by` is empty (all dependencies resolved)

Lead filters results to EXCLUDE tasks whose `f` field intersects the `claimed_files` set (file-overlap check).

**claimed_files algorithm:**

Lead maintains a `Set<string>` called `claimed_files`.

- **On `task_claim` event:** add all entries from `task.files` to `claimed_files`.
- **On `task_complete` event:** remove all entries from `task.files` from `claimed_files`.
- **Before returning TaskList results:** for each candidate task, check if any entry in `task.files` exists in `claimed_files`. If yes, exclude that task from results.

```
function filterAvailableTasks(candidates, claimed_files):
  result = []
  for task in candidates:
    if task.status != "available": continue
    if task.assignee != null: continue
    if task.blocked_by is not empty: continue
    overlap = intersection(task.files, claimed_files)
    if overlap is not empty: continue
    result.append(task)
  return result
```

### TaskUpdate (Claim and Complete)

Dev calls TaskUpdate with `task_id` and one of two operations:

**Claiming a task:**

```json
{
  "task_id": "T3",
  "status": "claimed",
  "assignee": "dev-1"
}
```

**Completing a task:**

```json
{
  "task_id": "T3",
  "status": "complete",
  "commit": "abc1234"
}
```

## Dynamic Dev Scaling (when team_mode=teammate)

> This section is active ONLY when team_mode=teammate.

**Formula:** `dev_count = min(available_unblocked_tasks, 5)`

The cap of 5 prevents resource exhaustion. When `available_unblocked_tasks` is 0, Lead waits for `task_complete` events before spawning any Devs.

### Lead Algorithm

1. Lead counts `available_unblocked_tasks` from TaskList (status=available, no blocked_by, no file-overlap).
2. Lead calls `scripts/compute-dev-count.sh --available N` to get `dev_count`.
3. Lead registers `dev_count` Dev agents as teammates (if not already registered).
4. Lead dispatches initial task assignments.
5. Lead enters monitoring loop:
   - When a `task_complete` event is received, Lead removes files from `claimed_files`.
   - Lead re-evaluates blocked tasks (some may now be unblocked).
   - Lead recomputes `dev_count`.
   - If newly unblocked tasks exist and idle Devs are available, Lead assigns them.

### Canonical Implementation

The formula is implemented in `scripts/compute-dev-count.sh` (canonical -- prompts reference this script).

```bash
bash scripts/compute-dev-count.sh --available 7
# outputs: 5
```

## Task-Level Blocking (when team_mode=teammate)

> This section is active ONLY when team_mode=teammate.

### Intra-Plan Blocking (td field)

When a task has `td:["T1","T3"]`, it means this task is blocked until tasks T1 AND T3 in the SAME plan are complete. Lead maps `td` entries to TaskCreate `blocked_by` parameter using format `{plan_id}/{td_entry}` (e.g., `03-01/T1`).

When `td` is absent or empty, the task has no intra-plan dependencies (can run immediately if plan-level deps are satisfied).

### Cross-Plan Blocking (d field)

When plan B has `d:["03-01"]`, ALL tasks in plan B are blocked by ALL tasks in plan 03-01. Lead maps this by adding `blocked_by` entries for every task in plan 03-01 to every task in plan B.

This is coarse-grained by design -- plan-level dependency means nothing in B can start until everything in A is done.

### Cross-Phase Blocking (xd field)

When a plan has `xd` entries, Lead verifies the referenced artifact exists (summary.jsonl with `s:complete`) before creating any tasks from that plan. `xd` blocking is resolved at plan load time, not at task level.

### Concrete Example

Plan 03-02 has `d:["03-01"]`. Plan 03-01 has tasks T1-T7.

This means all tasks in 03-02 have `blocked_by=['03-01/T1','03-01/T2',...,'03-01/T7']`.

Within 03-01, if T3 has `td:['T1']`, then T3 has `blocked_by=['03-01/T1']`.

See `references/artifact-formats.md` ## Plan Task for `td` field definition. See `scripts/resolve-task-deps.sh` for canonical dependency resolution.

## Fallback Cascade

Three-tier graceful degradation when Teammate API is unavailable or fails mid-execution.

### Tier 1: Teammate API (Preferred)

Conditions: team_mode=teammate (explicit or auto-detected), CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS env var set, agent_teams=true in config. All agents spawned via spawnTeam/addTeammate, communication via SendMessage.

### Tier 2: Task Tool Fallback

Triggers:
- **Pre-execution:** resolve-team-mode.sh detects env var missing OR agent_teams=false. Outputs team_mode=task with fallback_notice=true.
- **Runtime:** spawnTeam call fails (API error, timeout, unsupported). Lead catches failure and switches to Task tool for remaining agents.
- **Mid-execution:** Teammate becomes unresponsive (60s timeout, see ## Health Tracking). Lead reassigns work via Task tool.

Behavior: All agent spawning reverts to Task tool. File-based communication replaces SendMessage. Existing escalation chains, schemas, and artifact formats unchanged. Only the transport mechanism changes.

Logging: Lead logs each fallback transition to stderr: "[FALLBACK] {reason}: switching from teammate to task for {agent/department}"

### Tier 3: Error (Terminal)

Triggers:
- Task tool also fails (model unavailable, permissions error).
- No further fallback possible.

Behavior: Lead logs error, commits any partial artifacts, escalates to Architect with escalation schema. Phase execution halts with clear error message.

### Department Isolation

Fallback is per-department. If Backend teammate fails, only Backend falls back to Task tool. Frontend and UI/UX continue in teammate mode unaffected. Each Lead manages its own fallback state independently.

## Health Tracking

> This section is active ONLY when team_mode=teammate.

Lead monitors teammate health via SendMessage response patterns. No custom heartbeat protocol -- health is inferred from existing communication.

### Agent Lifecycle States

| State | Meaning | Trigger |
|-------|---------|--------|
| `start` | Agent registered and receiving first assignment | addTeammate completes |
| `idle` | Agent completed work, waiting for next assignment | task_complete received, no new task assigned |
| `stop` | Agent received shutdown_request and sent shutdown_response | shutdown protocol completes |
| `disappeared` | Agent has not responded within 60s of expected signal | Timeout on SendMessage response |

### Tracking Algorithm

Lead maintains an in-memory map: `agent_health = Map<agent_id, {state, timestamp, prev_state, dept}>`.

1. On addTeammate success: set state=start, timestamp=now.
2. On receiving task_complete: set state=idle, timestamp=now.
3. On sending task assignment: update timestamp (expected response within 60s).
4. On receiving shutdown_response: set state=stop, timestamp=now.
5. On timeout (60s since last expected response): set state=disappeared, trigger recovery.

### Recovery on Disappeared Agent

When an agent enters `disappeared` state:
1. Log: "[HEALTH] Agent {agent_id} disappeared after 60s timeout."
2. Remove agent's files from claimed_files set.
3. Mark agent's in-progress task as available.
4. Trigger Tier 2 fallback (see ## Fallback Cascade) -- reassign work via Task tool.
5. Update circuit breaker state (see agents/yolo-lead.md ## Circuit Breaker).

### agent_health_event Schema

```json
{
  "type": "agent_health_event",
  "agent_id": "dev-1",
  "dept": "backend",
  "state": "start | idle | stop | disappeared",
  "timestamp": "2026-02-17T10:30:00Z",
  "prev_state": "idle",
  "timeout_triggered": false
}
```

This event is logged internally by Lead for debugging. It is NOT sent via SendMessage -- it is a Lead-internal tracking record.

## Task Mode Fallback

When team_mode=task (default), all patterns above are replaced by:
- spawnTeam -> Task tool with agent file reference
- SendMessage -> Task tool result return + file-based artifacts
- shutdown -> Task tool session ends naturally
- cleanup -> No additional cleanup needed (Task tool handles)

The escalation chains, schemas, and artifact formats remain identical between modes. Only the transport mechanism changes.
