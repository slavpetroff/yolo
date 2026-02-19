# Cross-Team Protocol

Cross-department workflow, communication rules, handoff gates, and conflict resolution. Read by all Leads and Owner.

**Spawn mode awareness:** This protocol has two transport modes controlled by `team_mode` from resolve-team-mode.sh. When `team_mode=task` (default): all cross-department coordination uses file-based artifacts and sentinel polling as documented below. When `team_mode=teammate`: intra-department communication shifts to SendMessage (within a team), but cross-department communication REMAINS file-based because Leads are in separate Teammate API teams. SendMessage does not cross team boundaries.

## Department Execution Order

```
Phase Start
    │
    ▼
┌─────────────────────┐
│  Owner Context       │  ← SOLE point of contact with user
│  Gathering           │     Questionnaire → writes CONTEXT.md
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  Owner Critique      │  ← Reviews critique, sets dept priorities
│  Review (optional)   │     (balanced/thorough effort only)
└──────────┬──────────┘
           │
    ┌──────┴──────────┐
    ▼                  │
┌──────────────┐       │
│ UI/UX Dept   │ FIRST │  ← Produces design handoff artifacts
│ (11-step)    │       │
└──────┬───────┘       │
       │ handoff       │
  ┌────┴────┐          │
  ▼         ▼          │
┌────────┐ ┌────────┐  │
│Frontend│ │Backend │  │  ← Run in PARALLEL
│(11-step)│ │(11-step)│  │
└───┬────┘ └───┬────┘  │
    │          │       │
    └────┬─────┘       │
         ▼             │
┌──────────────────┐   │
│ Integration QA   │   │  ← Cross-department verification
│ + Security Audit │   │
└──────────┬───────┘   │
           ▼           │
┌──────────────────┐   │
│ Owner Sign-off   │   │  ← Final company-level sign-off
└──────────────────┘───┘
```

## Workflow Modes

| Config `department_workflow` | Behavior |
|------------------------------|----------|
| `backend_only` | Only backend department runs. Owner optional. Standard 11-step. |
| `sequential` | UX → Frontend → Backend (strict sequential). |
| `parallel` | UX first, then Frontend + Backend in parallel (recommended). |

## Communication Rules (STRICT)

| From | Can communicate with | NEVER communicates with |
|------|---------------------|------------------------|
| Backend agents | Frontend Lead (via api_contract) | UI/UX agents directly |
| Frontend agents | UI/UX Lead (via design handoff), Backend Lead (via api_contract) | — |
| UI/UX agents | Frontend Lead (via design handoff) | Backend agents directly |
| Shared agents | Any department (when dispatched by Lead) | — |
| Owner | All department Leads | Individual devs/seniors/QA |

### Rules
1. **Cross-department communication goes through Leads only.** Individual agents (Dev, Senior, QA) NEVER send messages across department boundaries.
2. **All cross-department data passes through handoff artifacts.** No ad-hoc messaging between departments — all cross-department data passes through handoff artifacts and file-based gates.
3. **Backend-UI/UX isolation is absolute.** Backend agents cannot read UI/UX artifacts directly. Frontend relays relevant information.
4. **Owner communicates only with Leads.** Strategic decisions, not technical details.

### Team Mode Transport Differences

| Communication Path | team_mode=task | team_mode=teammate |
|---|---|---|
| Within department: Dev->Senior | Task tool result return | SendMessage within team |
| Within department: Senior->Lead | Task tool result return | SendMessage within team |
| Within department: Architect->Lead | Task tool result return | SendMessage within team |
| Within department: Tester->Senior | Task tool result return | SendMessage (test_plan_result to Senior, NOT Lead) |
| Within department: QA->Lead | Task tool result return | SendMessage (qa_result to Lead) |
| Within department: QA (code mode)->Lead | Task tool result return | SendMessage (qa_code_result to Lead) |
| Within department: Security->Lead | Task tool result return | SendMessage (security_audit to Lead, backend team ONLY) |
| Within department: Senior->Dev (review changes) | New Task tool spawn | SendMessage (code_review_changes to Dev) |
| Cross department: Lead->Lead | File-based artifacts (api-contracts.jsonl, design-handoff.jsonl) | File-based artifacts (UNCHANGED -- different teams) |
| Lead->Owner | File-based (.dept-status-{dept}.json) | File-based (UNCHANGED -- Owner is not in any department team) |
| Owner->User | go.md proxy (AskUserQuestion) | go.md proxy (UNCHANGED) |

**Key insight:** Cross-team communication is ALWAYS file-based regardless of team_mode. The Teammate API SendMessage only works within a single team. Since each department is its own team (yolo-backend, yolo-frontend, yolo-uiux), inter-department coordination cannot use SendMessage. Within each team, all 16 Phase 2 agents (tester x3, qa x3, security x1, plus the 4 Phase 1 agents and 8 FE/UX core agents from plan 02-05) use SendMessage for intra-team coordination when team_mode=teammate. Note: qa-code was merged into qa with --mode plan|code; the QA agent handles both plan-level and code-level verification. This is by design -- it enforces the same strict context isolation that file-based gates provide.

## Context Isolation Rules (STRICT — NO CONTEXT BLEED)

See @references/company-hierarchy.md ## Context Isolation for full rules and per-agent scoping.

## Handoff Gates

### Gate 1: UI/UX → Frontend + Backend

**Trigger:** UI/UX department completes its 11-step workflow.

**Required artifacts (all must exist):**
- `design-handoff.jsonl` with `status: "complete"`
- `design-tokens.jsonl` committed to phase directory
- `component-specs.jsonl` with all specified components having `status: "ready"`

**Validation:**
```bash
# Automated gate check via dept-gate.sh
bash ${CLAUDE_PLUGIN_ROOT}/scripts/dept-gate.sh \
  --gate ux-complete --phase-dir {phase-dir} --no-poll
# Exit 0: gate satisfied (sentinel exists + artifacts valid)
# Exit 1: gate not satisfied
# Exit 2: validation error

# dept-gate.sh internally validates:
# - .handoff-ux-complete sentinel file exists
# - design-handoff.jsonl exists with status: "complete"
# - design-tokens.jsonl exists
# - component-specs.jsonl exists with all status: "ready"
```

**If gate fails:** UX Lead must resolve before Frontend/Backend can proceed. UX Lead may need to scope down (mark non-ready components as deferred).

**Timeout:** 30 minutes (configurable). On timeout: `dept-cleanup.sh --phase-dir {phase-dir} --reason timeout`. UX Lead must resolve.

**Teammate mode:** When `team_mode=teammate`, the UX Lead signals completion via file-based handoff artifacts (same as task mode). The handoff sentinel (.handoff-ux-complete) and artifact validation (design-handoff.jsonl, design-tokens.jsonl, component-specs.jsonl) are identical. The only difference is that WITHIN the UX department, agents communicated via SendMessage instead of Task tool. The handoff gate itself is transport-agnostic.

### Gate 2: Frontend ↔ Backend API Contract

**Trigger:** Either Frontend or Backend needs API integration.

**Workflow:**
1. Frontend Lead proposes `api_contract` with `status: "proposed"`.
2. Backend Lead reviews, negotiates if needed, sets `status: "agreed"`.
3. Backend implements, updates to `status: "implemented"`.
4. Frontend integrates against implemented contract.

**If conflict:** Both Leads escalate to Owner for priority resolution.

**Validation:** `bash dept-gate.sh --gate api-contract --phase-dir {phase-dir} --no-poll`. Checks api-contracts.jsonl has at least one entry with `status: "agreed"`. Non-blocking gate — FE and BE proceed in parallel and negotiate async. Both use flock locking via dept-status.sh for atomic writes to api-contracts.jsonl.

### Gate 3: Integration QA

**Trigger:** All active departments complete their 11-step workflows.

**Gate check:**
```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/dept-gate.sh \
  --gate all-depts --phase-dir {phase-dir} --no-poll
# Validates:
# - Every active department has .dept-status-{dept}.json with status: "complete"
# - Every department has at least one summary.jsonl
```

**Required after gate passes:**
- Cross-department integration points tested:
  - Frontend consumes Backend API correctly
  - Frontend renders UI/UX design tokens correctly
  - Backend validates data shapes Frontend sends

**Timeout:** 60 minutes (configurable). On timeout: display per-department status report from .dept-status-{dept}.json files.

**Teammate mode:** When `team_mode=teammate`, each department Lead signals completion by writing .dept-status-{dept}.json (same as task mode) AND by sending department_result via SendMessage to go.md. The integration gate check via dept-gate.sh is identical in both modes. Within each department, agents used SendMessage for coordination (Tester->Senior, QA->Lead, Security->Lead for backend), but the cross-department gate remains file-based. dept-gate.sh does not need modification for teammate mode.

### Gate 4: Owner Sign-off

**Trigger:** Integration QA complete.

**Owner reviews:**
- All `department_result` schemas (PASS/PARTIAL/FAIL per dept)
- Integration QA results
- Security audit results (shared Security runs per department)
- Cross-department consistency

**Decision:** SHIP (all departments approved) or HOLD (remediation needed).

**Teammate mode:** When `team_mode=teammate`, Owner receives department_result reports via file-based .dept-status-{dept}.json (same as task mode). Owner is not a member of any department team, so SendMessage cannot be used for Owner communication. The sign-off process, decision matrix, and owner_signoff schema are identical regardless of team_mode. The only difference is that within each department, the 11-step workflow used SendMessage for specialist coordination instead of Task tool spawning.

## Conflict Resolution

### Priority Order
When departments conflict:
1. **Data integrity** (Backend) > **User experience** (Frontend/UX)
2. **Security** (any dept) > **Feature completeness** (any dept)
3. **Accessibility** (UX/Frontend) > **Visual polish** (UX)

### Resolution Process
1. Both department Leads document their position with evidence.
2. Leads escalate to Owner (or User if no Owner).
3. Owner decides based on business priority, timeline, technical debt tradeoff.
4. Owner's decision is final. Losing department adjusts their plan.

## Handoff Artifact Schemas

Handoff artifact schemas (design_handoff, api_contract, department_result, owner_signoff): see @references/handoff-schemas.md ## Cross-Department Schemas for full definitions.

## Cross-Team Status Reporting

Defines how departments report progress during multi-department execution. Single-department mode uses execution-state.json directly and does not need this section.

### Reporting Cadence

| Level | Reporter | Frequency | Artifact | Reader |
|-------|----------|-----------|----------|--------|
| Task | Dev | Per task completion | `dev_progress` schema (to Senior) | Senior |
| Plan | Lead | Per plan completion | `summary.jsonl` | Owner (at gates) |
| Step | Lead | Per workflow step | `.dept-status-{dept}.json` | go.md (polling), Owner |
| Phase | Lead | On department completion | `department_result` schema | Owner |

### Status Schema (.dept-status-{dept}.json)

Written by dept-status.sh (called by department Lead). Updated at each workflow step transition:

```json
{
  "dept": "backend",
  "status": "running | complete | failed",
  "step": "implementation",
  "percent_complete": 60,
  "plans_complete": 2,
  "plans_total": 3,
  "blockers": [],
  "eta": "ISO 8601 or empty",
  "started_at": "ISO 8601",
  "updated_at": "ISO 8601",
  "error": ""
}
```

### Aggregation

Owner reads all department status files at gate boundaries:
1. **UX-complete gate**: Read `.dept-status-uiux.json` for UX completion
2. **All-depts gate**: Read all `.dept-status-{dept}.json` for completion
3. **Sign-off**: Read `department_result` from each Lead

go.md polls `.dept-status-{dept}.json` via dept-gate.sh for gate satisfaction (see ## Handoff Gates above).

### Intra-Phase Progress (phase_progress schema)

Leads report intra-phase progress to orchestrator via the `phase_progress` schema (see @references/handoff-schemas.md ## phase_progress). Used by go.md to display progress during long-running phases.

### Teammate Mode

When `team_mode=teammate`: Intra-department status reporting uses SendMessage (Dev->Senior via dev_progress, Dev->Lead via task_complete). Cross-department status reporting remains file-based (.dept-status-{dept}.json) because Leads are in separate teams.
