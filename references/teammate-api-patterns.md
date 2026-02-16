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

After team creation, Lead registers teammates by role. Phase 1 roles: senior, dev, architect. Phase 2 adds: tester, qa, qa-code, security.

Registration order: architect first (receives design context), then senior (receives specs), then dev (receives implementation tasks). Order matters because earlier teammates may need context before later ones begin.

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

## Task Mode Fallback

When team_mode=task (default), all patterns above are replaced by:
- spawnTeam -> Task tool with agent file reference
- SendMessage -> Task tool result return + file-based artifacts
- shutdown -> Task tool session ends naturally
- cleanup -> No additional cleanup needed (Task tool handles)

The escalation chains, schemas, and artifact formats remain identical between modes. Only the transport mechanism changes.
