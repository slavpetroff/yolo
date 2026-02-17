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
1. UI/UX Department: Spawned as background Task subagent
   ├── run_in_background: true
   ├── Steps 1-10: Critique -> ... -> Sign-off (foreground Task subagents internally)
   ├── Produce: design-handoff.jsonl, design-tokens.jsonl, component-specs.jsonl
   └── On completion: write .dept-status-uiux.json + .handoff-ux-complete sentinel

2. HANDOFF GATE: dept-gate.sh --gate ux-complete --phase-dir {phase-dir}
   Validates: .handoff-ux-complete exists + design artifacts valid

3. Frontend + Backend: Spawned as parallel background Task subagents
   ├── Frontend: run_in_background=true, reads UX handoff artifacts
   ├── Backend: run_in_background=true, independent execution
   ├── Each writes .dept-status-{dept}.json on completion
   └── go.md polls via dept-gate.sh --gate all-depts

4. API CONTRACT GATE: dept-gate.sh --gate api-contract --phase-dir {phase-dir}
   Non-blocking: FE and BE negotiate async via api-contracts.jsonl with flock

5. Integration QA: dept-gate.sh --gate all-depts verifies all departments complete
   Then runs cross-department verification (foreground)

6. Security: Shared Security audits all departments (foreground)

7. Owner Sign-off: Final review
   On completion: bash dept-cleanup.sh --phase-dir {phase-dir} --reason complete
```

**If `department_workflow` = "sequential":**
```
UI/UX → Frontend → Backend → Integration QA → Security → Owner Sign-off
```

**If `department_workflow` = "backend_only":**
```
Standard 11-step (no cross-department orchestration)
```

### Per-Department 11-Step Execution

Each department runs the same 11-step workflow from `execute-protocol.md`. Department Leads are spawned as **background Task subagents** (`run_in_background=true`) by go.md. Internally, each Lead spawns its specialists (Critic, Scout, Architect, Senior, Dev, etc.) as **foreground Task subagents** — the same proven single-agent workflow. The only change is the outer spawning mechanism; the inner 11-step is identical to single-dept mode.

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

## Coordination Files

All coordination files live in the phase directory. Created by dept-status.sh and dept-gate.sh. Cleaned up by dept-cleanup.sh.

| File Pattern | Purpose | Schema | Written By |
|---|---|---|---|
| `.dept-status-{dept}.json` | Per-department status tracking | `{"dept":"backend","status":"running","step":"implementation","started_at":"ISO","updated_at":"ISO","plans_complete":2,"plans_total":3,"error":""}` | dept-status.sh (called by dept Lead) |
| `.handoff-ux-complete` | Sentinel: UX workflow finished | Empty file (existence = gate passed) | UX Lead on Step 10 completion |
| `.handoff-api-contract` | Sentinel: API contract agreed | Empty file | BE Lead after api-contracts.jsonl agreed |
| `.dept-lock-{dept}` | flock lockfile for atomic status writes | N/A (flock internal) | dept-status.sh |
| `.phase-orchestration.json` | Master orchestration state | See execute-protocol.md ## Multi-Department Execution | go.md at orchestration start |

All coordination files are prefixed with `.` (hidden) to distinguish from user artifacts.

## Polling Mechanism

go.md polls for gate satisfaction using a simple loop:

- **Interval:** 500ms (`sleep 0.5`)
- **Timeout:** Configurable, default 30 minutes per gate. Read from spawn plan JSON `timeout_minutes` field.
- **Check method:** `bash dept-gate.sh --gate {name} --phase-dir {dir} --no-poll` — single check, exit 0 if satisfied, exit 1 if not.
- **Timeout handling:** After elapsed seconds exceed `timeout_minutes * 60`, STOP with error. Run `dept-cleanup.sh --phase-dir {dir} --reason timeout`. Display per-department status report (read each .dept-status-{dept}.json for current step and error).
- **Error handling:** If dept-gate.sh exits 2 (gate check error, e.g., corrupt status file), STOP with error. Run dept-cleanup.sh --reason failure.

## Cleanup

Run `bash dept-cleanup.sh --phase-dir {phase-dir} --reason {reason}` at:
- Phase completion (reason=complete): after Owner sign-off
- Gate timeout (reason=timeout): after any polling timeout
- Failure (reason=failure): after any unrecoverable error

Removes: `.dept-status-*.json`, `.handoff-*`, `.dept-lock-*`, `.phase-orchestration.json`
Preserves: All user artifacts (plan.jsonl, summary.jsonl, architecture.toon, etc.)

## Integration QA

**Gate check:** Before running Integration QA, verify all departments are complete via `bash dept-gate.sh --gate all-depts --phase-dir {phase-dir}`. This validates every active department has `.dept-status-{dept}.json` with `status: "complete"` and at least one summary.jsonl.

After all departments complete their individual 11-step workflows:

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
6. Run `bash dept-cleanup.sh --phase-dir {phase-dir} --reason complete` to remove coordination files.

## Execution State Extensions

`.execution-state.json` gains `departments` object when multi_dept=true:
```json
"departments": {
  "uiux": {"status":"complete","step":"signoff"},
  "frontend": {"status":"running","step":"implementation"},
  "backend": {"status":"running","step":"code_review"}
}
```
Mirrored from `.phase-orchestration.json`. Updated by state-updater.sh on each plan/summary write. See `execute-protocol.md ## Multi-Department Execution` for full `.phase-orchestration.json` schema.

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
