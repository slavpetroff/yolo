---
phase: "02"
plan: "02"
title: "Execute protocol vision gate enforcement"
wave: 1
depends_on: []
must_haves:
  - "REQ-06: Execute protocol checks awaiting_approval status before Step 3"
  - "REQ-06: Vision gate check added between Step 2b and Step 3"
  - "REQ-06: awaiting_approval is a valid execution state status"
---

# Plan 02: Execute protocol vision gate enforcement

## Goal

Add a vision gate check to the execute protocol (SKILL.md) that verifies the Architect's `request_human_approval` call was answered before allowing Dev team spawn in Step 3. Currently the protocol has no enforcement -- the Architect is told to halt but nothing prevents execution from continuing.

## Tasks

### Task 1: Add Step 2c -- Vision gate enforcement check

**File:** `skills/execute-protocol/SKILL.md`

**What to change:**

Insert a new `### Step 2c: Vision gate enforcement` section between Step 2b (Review gate) and Step 3 (Create Agent Team). The new step:

1. Reads `.yolo-planning/.execution-state.json`
2. Checks if `"status"` is `"awaiting_approval"`
3. If awaiting approval:
   - Display: `⏸ Vision gate: Awaiting human approval for {plan_path}. Execution paused.`
   - HARD STOP. Do NOT proceed to Step 3.
   - Display: `Resume: User must approve the roadmap, then execution state will be updated to "running".`
4. If status is `"running"` or no approval metadata exists (backward compat for phases that skip the Architect vision gate):
   - Display: `✓ Vision gate: cleared`
   - Proceed to Step 3
5. Track step completion:

```bash
jq '.steps_completed += ["step_2c"]' \
  .yolo-planning/.execution-state.json > /tmp/exec-state-tmp.json && \
  mv /tmp/exec-state-tmp.json .yolo-planning/.execution-state.json
```

**Why:** Without this check, execution can proceed past the Architect's HITL gate even if the human never approved. This makes the gate genuinely blocking at the protocol level.

### Task 2: Add awaiting_approval to valid status values in Step 2

**File:** `skills/execute-protocol/SKILL.md`

**What to change:**

In Step 2 (line ~30), the execution state JSON schema shows `"status": "running"`. Update the surrounding documentation to list all valid status values:

```
Valid statuses: "running", "awaiting_approval", "complete"
```

Also update the crash recovery logic in Step 2 item 6 to handle `"awaiting_approval"` -- if the execution state has `"status": "awaiting_approval"`, do NOT overwrite it with `"running"`. Preserve the approval state so the gate in Step 2c can enforce it.

**Why:** The protocol needs to formally recognize `"awaiting_approval"` as a valid state to prevent crash recovery from accidentally clearing a pending approval.

### Task 3: Update Step 5 step ordering verification to include step_2c

**File:** `skills/execute-protocol/SKILL.md`

**What to change:**

In Step 5, the `REQUIRED_STEPS` array currently lists:
```bash
REQUIRED_STEPS='["step_2","step_2b","step_3","step_3c","step_3d"]'
```

Update to include `step_2c`:
```bash
REQUIRED_STEPS='["step_2","step_2b","step_2c","step_3","step_3c","step_3d"]'
```

Also update the display text:
```
Required: step_2 → step_2b → step_2c → step_3 → step_3c → step_3d
```

**Why:** The step ordering verification gate must include the new vision gate step to prevent it from being skipped. Without this, an agent could bypass the vision gate and still pass Step 5 validation.

### Task 4: Document UAT checkpoint for all autonomy levels

**File:** `skills/execute-protocol/SKILL.md`

**What to change:**

In Step 4.5 (UAT checkpoint), add a documentation note after the autonomy gate table:

```markdown
**HITL gate summary (all autonomy levels):**

| Gate | Where | Blocking mechanism |
|------|-------|--------------------|
| Vision gate (Architect) | Step 2c | execution-state.json status=awaiting_approval |
| Review gate | Step 2b | Reviewer verdict loop |
| Plan approval gate | Step 3 | plan_mode_required on Dev spawn |
| UAT checkpoint | Step 4.5 | User-interactive CHECKPOINT loop |

Vision gate and Review gate are autonomy-independent (always active when triggered).
Plan approval and UAT are autonomy-gated per the tables above.
```

**Why:** Consolidates all HITL gates in one reference table so agents and maintainers understand the full checkpoint landscape across the protocol.
