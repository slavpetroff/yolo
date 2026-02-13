# Cross-Team Protocol

Cross-department workflow, communication rules, handoff gates, and conflict resolution. Read by all Leads and Owner.

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
│ (10-step)    │       │
└──────┬───────┘       │
       │ handoff       │
  ┌────┴────┐          │
  ▼         ▼          │
┌────────┐ ┌────────┐  │
│Frontend│ │Backend │  │  ← Run in PARALLEL
│(10-step)│ │(10-step)│  │
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
| `backend_only` | Only backend department runs. Owner optional. Standard 10-step. |
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
2. **All cross-department data passes through handoff artifacts.** No ad-hoc SendMessage between departments — use defined schemas.
3. **Backend-UI/UX isolation is absolute.** Backend agents cannot read UI/UX artifacts directly. Frontend relays relevant information.
4. **Owner communicates only with Leads.** Strategic decisions, not technical details.

## Handoff Gates

### Gate 1: UI/UX → Frontend + Backend

**Trigger:** UI/UX department completes its 10-step workflow.

**Required artifacts (all must exist):**
- `design-handoff.jsonl` with `status: "complete"`
- `design-tokens.jsonl` committed to phase directory
- `component-specs.jsonl` with all specified components having `status: "ready"`

**Validation:**
```bash
# All must pass before Frontend/Backend can start
jq -e '.status == "complete"' design-handoff.jsonl
jq -e 'all(.status == "ready")' component-specs.jsonl
test -f design-tokens.jsonl
```

**If gate fails:** UX Lead must resolve before Frontend/Backend can proceed. UX Lead may need to scope down (mark non-ready components as deferred).

### Gate 2: Frontend ↔ Backend API Contract

**Trigger:** Either Frontend or Backend needs API integration.

**Workflow:**
1. Frontend Lead proposes `api_contract` with `status: "proposed"`.
2. Backend Lead reviews, negotiates if needed, sets `status: "agreed"`.
3. Backend implements, updates to `status: "implemented"`.
4. Frontend integrates against implemented contract.

**If conflict:** Both Leads escalate to Owner for priority resolution.

### Gate 3: Integration QA

**Trigger:** All active departments complete their 10-step workflows.

**Required:**
- Each department's `department_result` sent to Owner
- Cross-department integration points tested:
  - Frontend consumes Backend API correctly
  - Frontend renders UI/UX design tokens correctly
  - Backend validates data shapes Frontend sends

### Gate 4: Owner Sign-off

**Trigger:** Integration QA complete.

**Owner reviews:**
- All `department_result` schemas (PASS/PARTIAL/FAIL per dept)
- Integration QA results
- Security audit results (shared Security runs per department)
- Cross-department consistency

**Decision:** SHIP (all departments approved) or HOLD (remediation needed).

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

### `design_handoff` (UX Lead → Frontend Lead + Backend Lead)

```jsonl
{"type":"design_handoff","phase":"01","dept":"uiux","artifacts":{"tokens":"phases/01/design-tokens.jsonl","specs":"phases/01/component-specs.jsonl","flows":"phases/01/user-flows.jsonl"},"ready":["LoginForm","AuthProvider"],"deferred":["PasswordReset"],"ac":["All components pass A11y audit","Design tokens cover all states"],"status":"complete"}
```

### `api_contract` (Frontend Lead ↔ Backend Lead)

```jsonl
{"type":"api_contract","dir":"fe_to_be|be_to_fe","endpoints":[{"m":"POST","p":"/auth/login","req":{"email":"string","password":"string"},"res":{"token":"string","user":"object"}}],"status":"proposed|agreed|implemented"}
```

### `department_result` (Department Lead → Owner)

```jsonl
{"type":"department_result","dept":"backend|frontend|uiux","phase":"01","r":"PASS|PARTIAL|FAIL","pc":3,"pt":3,"qa":"PASS","sec":"PASS","tdd":"red_green"}
```

### `owner_signoff` (Owner → All Leads)

```jsonl
{"type":"owner_signoff","phase":"01","dec":"SHIP|HOLD","depts":["backend","frontend","uiux"],"iq":"PASS","notes":""}
```
