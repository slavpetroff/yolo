# Multi-Department Execution Protocol

Extends `references/execute-protocol.md` for multi-department orchestration. Loaded when `departments.frontend` or `departments.uiux` is true in config.

## Pre-Execution Extensions

After standard pre-execution from @references/execute-protocol.md ## Pre-Execution:
1. **Detect active departments** from config (jq .departments from config.json)
2. **Resolve models** for all active department agents (same pattern as execute-protocol.md step 3, for fe-* and ux-* roles)
3. **Validate department readiness** (verify agent files + dept protocol files exist)

See execute-protocol.md ## Multi-Department Pre-Execution for full bash examples.

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

See @references/company-hierarchy.md ## Context Isolation. Key rule: Owner splits context, no bleed, escalation restores context upward.

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

`.execution-state.json` gains `departments` object tracking per-department status, step, and result. Example structure in `references/artifact-formats.md`.

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
