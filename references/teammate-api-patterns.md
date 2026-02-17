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

Two-phase shutdown:
1. Lead sends `shutdown_request` message to all teammates via SendMessage.
2. Each teammate completes current work, commits artifacts, sends `shutdown_response` with status.
3. Lead verifies all teammates responded, then terminates team.

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

## Task Mode Fallback

When team_mode=task (default), all patterns above are replaced by:
- spawnTeam -> Task tool with agent file reference
- SendMessage -> Task tool result return + file-based artifacts
- shutdown -> Task tool session ends naturally
- cleanup -> No additional cleanup needed (Task tool handles)

The escalation chains, schemas, and artifact formats remain identical between modes. Only the transport mechanism changes.
