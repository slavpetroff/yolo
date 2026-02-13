# Multi-Department Execution Protocol

Extends `references/execute-protocol.md` for multi-department orchestration. Loaded when `departments.frontend` or `departments.uiux` is true in config.

## Pre-Execution Extensions

After standard pre-execution:

1. **Detect active departments** from config:
   ```bash
   BACKEND=$(jq -r '.departments.backend' config.json)   # always true
   FRONTEND=$(jq -r '.departments.frontend' config.json)
   UIUX=$(jq -r '.departments.uiux' config.json)
   WORKFLOW=$(jq -r '.department_workflow' config.json)
   ```

2. **Resolve models for all active department agents:**
   ```bash
   # Backend agents (always)
   LEAD_MODEL=$(bash resolve-agent-model.sh lead ...)
   # Frontend agents (if enabled)
   if [ "$FRONTEND" = "true" ]; then
     FE_LEAD_MODEL=$(bash resolve-agent-model.sh fe-lead ...)
     FE_ARCHITECT_MODEL=$(bash resolve-agent-model.sh fe-architect ...)
     # ... all 7 fe-* agents
   fi
   # UI/UX agents (if enabled)
   if [ "$UIUX" = "true" ]; then
     UX_LEAD_MODEL=$(bash resolve-agent-model.sh ux-lead ...)
     UX_ARCHITECT_MODEL=$(bash resolve-agent-model.sh ux-architect ...)
     # ... all 7 ux-* agents
   fi
   # Owner (if multiple departments)
   if [ "$FRONTEND" = "true" ] || [ "$UIUX" = "true" ]; then
     OWNER_MODEL=$(bash resolve-agent-model.sh owner ...)
   fi
   ```

3. **Validate department readiness:**
   - If `departments.frontend` true: verify all 7 `yolo-fe-*.md` agent files exist
   - If `departments.uiux` true: verify all 7 `yolo-ux-*.md` agent files exist
   - Verify `references/departments/{dept}.md` exists for each active department
   - Verify `references/cross-team-protocol.md` exists if multiple departments active

## Phase Execution: Multi-Department Flow

### Step 0: Owner Context Gathering + Critique Review

**Step 0a: Owner Context Gathering (FIRST — before ANY department work):**

The Owner is the SOLE point of contact with the user. No department lead or agent talks to the user directly.

If department context files do NOT exist (e.g. `{phase}-CONTEXT-backend.md`):
1. go.md acts as Owner proxy — runs questionnaire via AskUserQuestion (2-3 rounds: vision, dept-specific, gaps/features/constraints). Keeps asking until ZERO ambiguity remains.
2. Splits gathered context into department-specific files (NO context bleed):
   - `{phase-dir}/{phase}-CONTEXT-backend.md` — Backend concerns ONLY
   - `{phase-dir}/{phase}-CONTEXT-uiux.md` — UX concerns ONLY
   - `{phase-dir}/{phase}-CONTEXT-frontend.md` — Frontend concerns ONLY
3. Each department lead receives ONLY their department's context file.

If department context files already exist (from Plan Mode): skip to Step 0b.

**Step 0b: Owner Critique Review (balanced/thorough effort only):**

If Owner is active (multiple departments):
1. Run shared Critic as normal (Step 1 from execute-protocol.md).
2. Spawn yolo-owner with `owner_review` mode:
   - model: "${OWNER_MODEL}"
   - Input: critique.jsonl, reqs.jsonl, department config, CONTEXT.md
3. Owner determines department priorities and dispatch order.
4. Owner sends `owner_review` to all department Leads.

### Context Delegation Protocol (MANDATORY — NO CONTEXT BLEED)

Context flows DOWN the hierarchy with progressive scoping. Each level receives ONLY what it needs.

**Owner → Department Leads (cross-department boundary):**

Owner splits gathered context into department-specific files:
- Backend Lead receives: `{phase}-CONTEXT-backend.md` (data models, APIs, auth, infrastructure)
- UX Lead receives: `{phase}-CONTEXT-uiux.md` (design preferences, users, accessibility, flows)
- Frontend Lead receives: `{phase}-CONTEXT-frontend.md` + UX handoff artifacts (after UX completes)

Each Lead NEVER sees another department's context file. This prevents context bleed.

**Within each department (Lead → Architect → Senior → Dev):**

| Agent | Receives | NEVER receives |
|-------|----------|----------------|
| Lead | Dept CONTEXT + ROADMAP + REQUIREMENTS + prior summaries | Other dept contexts, other dept plans |
| Architect | Lead's plan structure + dept CONTEXT + critique findings | Other dept contexts, implementation code |
| Senior | architecture.toon + plan.jsonl tasks + codebase patterns | Full CONTEXT file, critique.jsonl directly, other dept artifacts |
| Dev | Senior's enriched `spec` field ONLY + test files from Tester | architecture.toon, CONTEXT files, critique.jsonl, ROADMAP, REQUIREMENTS |

**Dev receives ZERO creative context.** The spec field IS the complete instruction set. If spec is unclear → escalate to Senior (not read more context).

**Escalation reverses the flow:**
```
Dev → Senior → Lead → Architect → Owner → User
```
At each level, the escalating agent provides evidence. At Owner level, Owner clarifies with user. Owner then pushes corrected context back DOWN through the SAME chain (never skipping levels). Corrected context is written to a new version of the relevant artifact (plan.jsonl spec update, architecture.toon amendment, or CONTEXT addendum).

**UX → Frontend handoff (cross-department):**
UX department produces design-handoff.jsonl, design-tokens.jsonl, component-specs.jsonl. These are the ONLY UX artifacts Frontend receives. Frontend Lead does NOT read UX's internal plans, architecture, or critique.

### Step 1-10: Department Dispatch

**If `department_workflow` = "parallel" (recommended):**

```
1. UI/UX Department: Run full 10-step workflow
   ├── Steps 1-10: Critique → ... → Sign-off
   └── Produce: design-handoff.jsonl, design-tokens.jsonl, component-specs.jsonl

2. HANDOFF GATE: Validate UI/UX artifacts ready

3. Frontend + Backend Departments: Run in PARALLEL
   ├── Frontend: Steps 1-10 (reads UI/UX handoff)
   └── Backend: Steps 1-10 (independent)

4. API CONTRACT GATE: Frontend ↔ Backend negotiate contracts

5. Integration QA: Cross-department verification

6. Security: Shared Security audits all departments

7. Owner Sign-off: Final review
```

**If `department_workflow` = "sequential":**
```
UI/UX → Frontend → Backend → Integration QA → Security → Owner Sign-off
```

**If `department_workflow` = "backend_only":**
```
Standard 10-step (no cross-department orchestration)
```

### Per-Department 10-Step Execution

Each department runs the same 10-step workflow from `execute-protocol.md` with:
- Department-specific agents (fe-*, ux-*, or backend originals)
- Department-specific compiled context (from `references/departments/{dept}.md`)
- Department-specific architecture file (fe-architecture.toon, ux-architecture.toon, or architecture.toon)
- Same artifact schemas (plan.jsonl, summary.jsonl, etc.)

### Cross-Department Artifact Exchange

| Step | Source Dept | Artifact | Target Dept | When |
|------|------------|----------|-------------|------|
| After UX Step 10 | UI/UX | design-handoff.jsonl | Frontend | Before FE Step 1 |
| After UX Step 10 | UI/UX | design-tokens.jsonl | Frontend | Before FE Step 1 |
| After UX Step 10 | UI/UX | component-specs.jsonl | Frontend | Before FE Step 1 |
| During FE Step 3 | Frontend | api_contract (proposed) | Backend | Anytime |
| During BE Step 6 | Backend | api_contract (implemented) | Frontend | After BE implementation |

## Integration QA

After all departments complete their individual 10-step workflows:

1. **Cross-department compatibility:**
   - Frontend consumes Backend API correctly (contract adherence)
   - Frontend renders design tokens from UI/UX correctly
   - Backend validates data shapes from Frontend

2. **Unified test suite:**
   - Run all department test suites together
   - Verify no conflicts or regressions

3. **Shared Security audit:**
   - Security agent runs separate audit per department
   - Cross-department security (CORS, auth flow end-to-end)

## Owner Sign-off Process

1. Collect `department_result` from each active department Lead.
2. Review Integration QA results.
3. Review Security audit results (all departments).
4. Decision matrix:

| Condition | Decision |
|-----------|----------|
| All departments PASS + Integration QA PASS + Security PASS | SHIP |
| Any department PARTIAL, integration OK | Review gaps, decide SHIP or HOLD |
| Any department FAIL | HOLD + remediation instructions |
| Security FAIL (any dept) | HARD STOP → User |

5. Send `owner_signoff` to all department Leads.

## Execution State Extensions

`.execution-state.json` gains department tracking:

```json
{
  "phase": 1,
  "departments": {
    "uiux": {"status": "complete", "step": "signoff", "result": "PASS"},
    "frontend": {"status": "running", "step": "implementation"},
    "backend": {"status": "running", "step": "code_review"}
  },
  "integration_qa": "pending",
  "owner_signoff": "pending"
}
```

## Display Format

Multi-department phase banner:
```
╔═══════════════════════════════════════════════╗
║  Phase {N}: {name} — Built                    ║
╚═══════════════════════════════════════════════╝

  Department Results:
    ✓ UI/UX: PASS (3/3 plans, TDD: red_green)
    ✓ Frontend: PASS (4/4 plans, TDD: red_green)
    ✓ Backend: PASS (3/3 plans, TDD: red_green)

  Integration: PASS
  Security: PASS
  Owner: SHIP
```
