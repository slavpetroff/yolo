---
name: execute-protocol
description: "YOLO execution protocol for phased plan execution with agent teams, gates, and observability"
category: lifecycle
---

# YOLO Execution Protocol

**V3 Extensions:** If ANY `v3_*` flag is `true` in `.yolo-planning/config.json`, also read `skills/execute-protocol/V3-EXTENSIONS.md` before executing. Otherwise skip it entirely.

Loaded on demand by /yolo:vibe Execute mode. Not a user-facing command.

### Step 2: Load plans and detect resume state

1. Glob `*-PLAN.md` in phase dir. Read each plan's YAML frontmatter.
2. Check existing SUMMARY.md files (complete plans).
3. `git log --oneline -20` for committed tasks (crash recovery).
4. Build remaining plans list. If `--plan=NN`, filter to that plan.
5. Partially-complete plans: note resume-from task number.
6. **Crash recovery:** If `.yolo-planning/.execution-state.json` exists with `"status": "running"`, update plan statuses to match current SUMMARY.md state.
   <!-- v3: event-recovery — see V3-EXTENSIONS.md when v3_* flags enabled -->
     6b. **Generate correlation_id:** Generate a UUID for this phase execution:
   - If `.yolo-planning/.execution-state.json` already exists and has `correlation_id` (crash-resume):
     preserve it: `CORRELATION_ID=$(jq -r '.correlation_id // ""' .yolo-planning/.execution-state.json 2>/dev/null || echo "")`
   - Otherwise generate fresh:
     `CORRELATION_ID=$(uuidgen 2>/dev/null | tr '[:upper:]' '[:lower:]' || echo "$(date -u +%s)-${RANDOM}${RANDOM}")`

7. **Write execution state** to `.yolo-planning/.execution-state.json`:

```json
{
  "phase": N, "phase_name": "{slug}", "status": "running",
  "started_at": "{ISO 8601}", "wave": 1, "total_waves": N,
  "correlation_id": "{UUID}",
  "plans": [{"id": "NN-MM", "title": "...", "wave": W, "status": "pending|complete"}]
}
```

Set completed plans (with SUMMARY.md) to `"complete"`, others to `"pending"`.

7b. **Export correlation_id:** Set `YOLO_CORRELATION_ID={CORRELATION_ID}` in the execution environment
so yolo log-event can fall back to it if .execution-state.json is temporarily unavailable.
Log a confirmation: `◆ Correlation ID: {CORRELATION_ID}`

<!-- v3: event-log-phase-start — see V3-EXTENSIONS.md when v3_* flags enabled -->

<!-- v3: snapshot-resume — see V3-EXTENSIONS.md when v3_* flags enabled -->
<!-- v3: schema-validation — see V3-EXTENSIONS.md when v3_* flags enabled -->

1. **Cross-phase deps (PWR-04):** Run plan validation for each plan:

```bash
"$HOME/.cargo/bin/yolo" validate-plan {plan_path} {phase_dir}
```

- Exit 0: all deps satisfied -- proceed. Display: `✓ Cross-phase dependencies verified`
- Exit 1: deps unsatisfied -- STOP with error from JSON output. Display errors from the `errors` array: "Cross-phase dependency not met. {error}. Fix: Run /yolo:vibe {P}"
- Exit 2: partial -- STOP with details from JSON output
- No cross_phase_deps in plan: command returns exit 0 with `checked: 0` -- skip silently

### Step 2b: Review gate (optional)

**Activation:** Read `review_gate` from config:
```bash
REVIEW_GATE=$(jq -r '.review_gate // "on_request"' .yolo-planning/config.json 2>/dev/null)
```

| review_gate | Behavior |
|-------------|----------|
| always | Run automated review on every plan before execution |
| on_request | Skip unless user passes `--review` flag |
| never | Skip entirely |

**When active:**

Read `review_max_cycles` from config (default 3):
```bash
REVIEW_MAX_CYCLES=$(jq -r '.review_max_cycles // 3' .yolo-planning/config.json 2>/dev/null)
```

For each plan in the phase, run automated review:

```bash
REVIEW_RESULT=$("$HOME/.cargo/bin/yolo" review-plan {plan_path} {phase_dir})
VERDICT=$(echo "$REVIEW_RESULT" | jq -r '.verdict')
```

**Verdict: approve** -- Display `✓ Plan {NN-MM} review: approved` and proceed. No loop needed.

**Verdict: conditional** (first pass or final loop cycle):
- Attach findings as warnings to DEV_CONTEXT variable (append to compiled context)
- Display `⚠ Plan {NN-MM} review: conditional (cycle 1/{max})`
- Proceed to Step 3

**Verdict: reject** -- Enter review feedback loop:

1. Initialize loop state:
```bash
REVIEW_CYCLE=1
ACCUMULATED_FINDINGS="[]"
PREVIOUS_FINDINGS=""
CURRENT_FINDINGS=$(echo "$REVIEW_RESULT" | jq '.findings')
ACCUMULATED_FINDINGS=$(echo "$ACCUMULATED_FINDINGS" | jq --argjson f "$CURRENT_FINDINGS" '. + $f')
```

   **Track loop start in execution-state.json:**
   ```bash
   jq --arg plan "{NN-MM}" --argjson max "$REVIEW_MAX_CYCLES" \
     '.review_loops[$plan] = {"cycle": 1, "max": $max, "status": "running", "findings_per_cycle": []}' \
     .yolo-planning/.execution-state.json > /tmp/exec-state-tmp.json && \
     mv /tmp/exec-state-tmp.json .yolo-planning/.execution-state.json
   ```

   **Log review_loop_start event:**
   ```bash
   "$HOME/.cargo/bin/yolo" log-event review_loop_start {phase} plan={NN-MM} max_cycles=${REVIEW_MAX_CYCLES} 2>/dev/null || true
   ```

2. Resolve Architect model:
```bash
ARCH_MODEL=$("$HOME/.cargo/bin/yolo" resolve-model architect .yolo-planning/config.json ${CLAUDE_PLUGIN_ROOT}/config/model-profiles.json)
```

3. **Loop** while `VERDICT == "reject"` AND `REVIEW_CYCLE < REVIEW_MAX_CYCLES`:

   a. Increment cycle:
   ```bash
   REVIEW_CYCLE=$((REVIEW_CYCLE + 1))
   ```

   b. Display: `◆ Review loop cycle {REVIEW_CYCLE}/{REVIEW_MAX_CYCLES} — spawning Architect to revise plan...`

   c. **Extract delta findings** (token-efficient: only pass what changed):
   ```bash
   # On first loop iteration, PREVIOUS_FINDINGS is empty — all current findings are "new"
   if [ -z "$PREVIOUS_FINDINGS" ]; then
     DELTA_FINDINGS=$(echo "$CURRENT_FINDINGS" | jq '[.[] | select(.severity == "high" or .severity == "medium")]')
   else
     # Extract only NEW findings (not present in previous cycle by ID)
     # and findings that CHANGED severity since last cycle
     DELTA_FINDINGS=$(jq -n \
       --argjson curr "$CURRENT_FINDINGS" \
       --argjson prev "$PREVIOUS_FINDINGS" \
       '[
         # New findings: present in current but not in previous (by .id)
         ($prev | map(.id)) as $prev_ids |
         ($curr[] | select(.severity == "high" or .severity == "medium") |
           select(.id as $id | $prev_ids | index($id) | not)),
         # Changed severity: same .id exists in both but severity differs
         ($curr[] | select(.severity == "high" or .severity == "medium") | . as $c |
           ($prev[] | select(.id == $c.id and .severity != $c.severity)) | $c)
       ] | unique_by(.id)')
   fi
   PREVIOUS_FINDINGS="$CURRENT_FINDINGS"
   ```

   > **Cache note:** Architect and Reviewer share the "planning" Tier 2 cache.
   > Only Tier 3 content (these delta findings) changes between iterations.
   > This avoids re-sending the full context on each cycle, saving significant tokens.

   d. Spawn Architect subagent via Task tool (subagent, NOT team):
   ```
   subject: "Revise plan {NN-MM} — review cycle {REVIEW_CYCLE}"
   description: |
     {PLANNING_CONTEXT}

     You are revising a plan that was rejected by the Reviewer.

     **Plan path:** {plan_path}
     **Review cycle:** {REVIEW_CYCLE} of {REVIEW_MAX_CYCLES}

     **Delta findings to address (new + changed severity, high + medium only):**
     {DELTA_FINDINGS}

     Findings already addressed (no longer present in latest review) have been
     excluded. Focus only on the items listed above.

     Instructions:
     1. Read the plan at {plan_path}
     2. Address each finding listed above
     3. Overwrite the original PLAN.md with your revised version
     4. Preserve the YAML frontmatter structure
     5. Do NOT change the plan's scope — only fix the identified issues
   activeForm: "Revising plan {NN-MM} (cycle {REVIEW_CYCLE})"
   model: "${ARCH_MODEL}"
   ```

   e. After Architect completes, re-run review on the revised plan:
   ```bash
   REVIEW_RESULT=$("$HOME/.cargo/bin/yolo" review-plan {plan_path} {phase_dir})
   VERDICT=$(echo "$REVIEW_RESULT" | jq -r '.verdict')
   CURRENT_FINDINGS=$(echo "$REVIEW_RESULT" | jq '.findings')
   ACCUMULATED_FINDINGS=$(echo "$ACCUMULATED_FINDINGS" | jq --argjson f "$CURRENT_FINDINGS" '. + $f')
   ```

   **Track cycle in execution-state.json:**
   ```bash
   CYCLE_SUMMARY=$(echo "$CURRENT_FINDINGS" | jq '{verdict: "'"$VERDICT"'", finding_count: length, high: [.[] | select(.severity == "high")] | length}')
   jq --arg plan "{NN-MM}" --argjson cycle "$REVIEW_CYCLE" --argjson summary "$CYCLE_SUMMARY" \
     '.review_loops[$plan].cycle = $cycle | .review_loops[$plan].findings_per_cycle += [$summary]' \
     .yolo-planning/.execution-state.json > /tmp/exec-state-tmp.json && \
     mv /tmp/exec-state-tmp.json .yolo-planning/.execution-state.json
   ```

   **Log review_loop_cycle event:**
   ```bash
   HIGH_COUNT=$(echo "$CURRENT_FINDINGS" | jq '[.[] | select(.severity == "high")] | length')
   "$HOME/.cargo/bin/yolo" log-event review_loop_cycle {phase} plan={NN-MM} cycle=${REVIEW_CYCLE} verdict=${VERDICT} high_count=${HIGH_COUNT} 2>/dev/null || true
   ```

   f. Parse new verdict:
      - `verdict: "approve"` -- Exit loop. Display `✓ Plan {NN-MM} review: approved (cycle {REVIEW_CYCLE}/{max})`. Update execution-state and log:
        ```bash
        jq --arg plan "{NN-MM}" '.review_loops[$plan].status = "passed"' \
          .yolo-planning/.execution-state.json > /tmp/exec-state-tmp.json && \
          mv /tmp/exec-state-tmp.json .yolo-planning/.execution-state.json
        "$HOME/.cargo/bin/yolo" log-event review_loop_end {phase} plan={NN-MM} cycles_used=${REVIEW_CYCLE} final_verdict=approve 2>/dev/null || true
        ```
      - `verdict: "conditional"` -- Exit loop. Attach findings as warnings to DEV_CONTEXT. Display `⚠ Plan {NN-MM} review: conditional (cycle {REVIEW_CYCLE}/{max})`. Update execution-state and log:
        ```bash
        jq --arg plan "{NN-MM}" '.review_loops[$plan].status = "passed"' \
          .yolo-planning/.execution-state.json > /tmp/exec-state-tmp.json && \
          mv /tmp/exec-state-tmp.json .yolo-planning/.execution-state.json
        "$HOME/.cargo/bin/yolo" log-event review_loop_end {phase} plan={NN-MM} cycles_used=${REVIEW_CYCLE} final_verdict=conditional 2>/dev/null || true
        ```
        Proceed to Step 3.
      - `verdict: "reject"` -- Continue loop (next iteration)

4. **Max cycles exceeded** (loop exits with `VERDICT == "reject"`):
   - Update execution-state and log:
     ```bash
     jq --arg plan "{NN-MM}" '.review_loops[$plan].status = "failed"' \
       .yolo-planning/.execution-state.json > /tmp/exec-state-tmp.json && \
       mv /tmp/exec-state-tmp.json .yolo-planning/.execution-state.json
     "$HOME/.cargo/bin/yolo" log-event review_loop_end {phase} plan={NN-MM} cycles_used=${REVIEW_MAX_CYCLES} final_verdict=reject 2>/dev/null || true
     ```
   - Display `✗ Plan {NN-MM} review: REJECTED after {REVIEW_MAX_CYCLES} cycles`
   - Display accumulated findings summary (deduplicated by finding ID):
     ```bash
     echo "$ACCUMULATED_FINDINGS" | jq -r 'group_by(.id) | map(last) | .[] | "  ✗ [\(.severity)] \(.title): \(.description)"'
     ```
   - STOP execution -- do not create Dev team
   - Return to user with suggestion: "Review loop exhausted after {max} cycles. Fix issues manually and re-run `/yolo:vibe --execute {N}`"

5. **Per-plan loop independence:**

   Each plan in the phase gets its **own independent review loop**. Plans do NOT share loop state.

   - Plans are reviewed sequentially in order (01, 02, 03, ...)
   - Each plan starts with `REVIEW_CYCLE=1` and its own `ACCUMULATED_FINDINGS`
   - If plan A passes review (approve/conditional), it is marked ready for Step 3 while plan B enters its own loop
   - Loop variables (`REVIEW_CYCLE`, `PREVIOUS_FINDINGS`, `ACCUMULATED_FINDINGS`, `CURRENT_FINDINGS`) are scoped per plan -- reset at the start of each plan's review
   - The `review_loops` object in execution-state.json tracks each plan independently under its plan ID key (e.g., `review_loops["01-01"]`, `review_loops["01-02"]`)

   **Phase-level stop behavior:**
   - If ANY plan hits max_cycles with a reject verdict: STOP the entire phase immediately
   - Do not proceed to Step 3 for ANY plan (even those that already passed review)
   - Display summary of all plan review outcomes:
     ```
     Review gate results:
       ✓ Plan 01-01: approved (cycle 1/3)
       ✗ Plan 01-02: REJECTED after 3 cycles
     Phase halted — all plans must pass review before execution.
     ```
   - If ALL plans approve or conditional: proceed to Step 3 with all plans

**When inactive:** Display `○ Review gate skipped (review_gate: {value})` and proceed to Step 3.

### Step 3: Create Agent Team and execute

**Team creation (multi-agent only):**
Read prefer_teams config to determine team creation:

```bash
PREFER_TEAMS=$(jq -r '.prefer_teams // "always"' .yolo-planning/config.json 2>/dev/null)
```

**Single-plan optimization:** Before evaluating prefer_teams, count uncompleted plans for this phase. If exactly 1 uncompleted plan exists:
- Skip TeamCreate entirely -- single agent mode, no team overhead
- Spawn Dev agent directly via Task tool (no `team_name` parameter)
- Skip TeamDelete in Step 5

This optimization applies regardless of the prefer_teams config value. Teams only provide value when 2+ agents can work in parallel. A team of 1 agent adds overhead (TeamCreate, TaskCreate, TaskUpdate, SendMessage, TeamDelete) with zero parallelism benefit.

Decision tree (when 2+ uncompleted plans):

- `prefer_teams='always'`: Create team for ALL plan counts, unless turbo or smart-routed to turbo
- `prefer_teams='when_parallel'`: Create team only when 2+ uncompleted plans, unless turbo or smart-routed to turbo
- `prefer_teams='auto'`: Same as when_parallel (use current behavior, smart routing can downgrade)

When team should be created based on prefer_teams:

- Create team via TeamCreate: `team_name="yolo-phase-{NN}"`, `description="Phase {N}: {phase-name}"`
- All Dev agents below MUST be spawned with `team_name: "yolo-phase-{NN}"` and `name: "dev-{MM}"` (from plan number) parameters on the Task tool invocation.

When team should NOT be created (single plan via optimization above, turbo, or smart-routed turbo):

- Skip TeamCreate -- single agent, no team overhead.

<!-- v3: smart-routing — see V3-EXTENSIONS.md when v3_* flags enabled -->

**Delegation directive (all except Turbo):**
You are the team LEAD. NEVER implement tasks yourself.

- Delegate ALL implementation to Dev teammates via TaskCreate
- NEVER Write/Edit files in a plan's `files_modified` — only state files: STATE.md, ROADMAP.md, .execution-state.json, SUMMARY.md
- If Dev fails: guidance via SendMessage, not takeover. If all Devs unavailable: create new Dev.
- At Turbo (or smart-routed to turbo): no team — Dev executes directly.

<!-- v3: monorepo-routing — see V3-EXTENSIONS.md when v3_* flags enabled -->

**Control Plane Coordination (REQ-05):** If `"$HOME/.cargo/bin/yolo" control-plane` exists:

- **Once per plan (before first task):** Run the `full` action to generate contract and compile context:

  ```bash
  CP_RESULT=$("$HOME/.cargo/bin/yolo" control-plane full {phase} {plan} 1 \
    --plan-path={plan_path} --role=dev --phase-dir={phase-dir} 2>/dev/null || echo '{"action":"full","steps":[]}')
  ```

  Extract `contract_path` and `context_path` from result for subsequent per-task calls.

- **Before each task:** Run the `pre-task` action:

  ```bash
  CP_RESULT=$("$HOME/.cargo/bin/yolo" control-plane pre-task {phase} {plan} {task} \
    --plan-path={plan_path} --task-id={phase}-{plan}-T{task} \
    --claimed-files={files_from_task} 2>/dev/null || echo '{"action":"pre-task","steps":[]}')
  ```

  If the result contains a gate failure (step with `status=fail`), treat as gate failure and follow existing auto-repair + escalation flow.

- **After each task:** Run the `post-task` action:

  ```bash
  CP_RESULT=$("$HOME/.cargo/bin/yolo" control-plane post-task {phase} {plan} {task} \
    --task-id={phase}-{plan}-T{task} 2>/dev/null || echo '{"action":"post-task","steps":[]}')
  ```

- If `yolo control-plane` does NOT exist: fall through to the individual script calls below (backward compatibility).
- On any `yolo control-plane` error: fall through to individual script calls (fail-open).

The existing individual script call sections (V3 Contract-Lite, V2 Hard Gates, Context compilation, Token Budgets) remain unchanged below as the fallback path.

**Context compilation (REQ-11):** If yolo control-plane `full` action was used above and returned a `context_path`, use that path directly. Otherwise, if `config_context_compiler=true` from Context block above, before creating Dev tasks run:
`"$HOME/.cargo/bin/yolo" compile-context {phase} dev {phase-dir} {plan_path}`
This produces `{phase-dir}/.context-dev.md` with phase goal and conventions. The output file contains three clearly marked sections:
- `--- TIER 1: SHARED BASE ---` (byte-identical for all roles in the same project)
- `--- TIER 2: ROLE FAMILY (execution) ---` (byte-identical for dev/qa/senior/debugger/security)
- `--- TIER 3: VOLATILE TAIL (phase={N}) ---` (phase-specific goal, requirements, delta)

The plan_path argument enables skill bundling: yolo compile-context reads `skills_used` from the plan's frontmatter and bundles referenced SKILL.md content into .context-dev.md. Skills are resolved in order: first from the project-local `${CLAUDE_PLUGIN_ROOT}/skills/{name}/SKILL.md`, then from the global `~/.claude/skills/{name}/SKILL.md`. Project-local skills take precedence over global skills with the same name. If the plan has no skills_used, this is a no-op.
If compilation fails, proceed without it — Dev reads files directly.

**Prefix-first injection (cache-optimal):** Read the compiled context file content into a variable BEFORE creating Dev tasks. All sibling Dev agents MUST receive byte-identical Tier 1 + Tier 2 content for cache hits. When multiple Dev agents receive the same content from position 0 in their Task description, the API caches the shared prefix and subsequent agents get cache reads instead of cold reads. When the MCP `compile_context` tool is used instead of CLI, the response contains `tier1_prefix`, `tier2_prefix`, and `volatile_tail` as separate fields. Callers should concatenate them in order.

```bash
DEV_CONTEXT=""
if [ -f "{phase-dir}/.context-dev.md" ]; then
  DEV_CONTEXT=$(<"{phase-dir}/.context-dev.md")
fi
```

**Compiled context format:** The compiled context uses a 3-tier structure to maximize Anthropic API prompt prefix caching. Tier 1 is byte-identical across all roles for the same project, enabling cache hits even across different agent types. Tier 2 is byte-identical within role families (planning or execution), enabling cache hits across same-family agents. Tier 3 contains phase-specific content that changes per phase.

```
--- TIER 1: SHARED BASE ---
{project-wide: architecture, conventions — byte-identical for all roles}
--- TIER 2: ROLE FAMILY ({family}) ---
{family-scoped: patterns, codebase structure — byte-identical within planning or execution families}
--- TIER 3: VOLATILE TAIL (phase={N}) ---
{phase-specific: goal, requirements, delta}
--- END COMPILED CONTEXT ---
```

Tier 1 (`--- TIER 1: SHARED BASE ---`) contains project-wide content shared by every agent. Tier 2 (`--- TIER 2: ROLE FAMILY ({family}) ---`) contains family-scoped content (e.g., all execution agents share the same Tier 2). Tier 3 (`--- TIER 3: VOLATILE TAIL (phase={N}) ---`) contains phase-specific content. This 3-tier separation means the API caches Tier 1 across all concurrent agents, and Tier 1 + Tier 2 across same-family agents — only Tier 3 changes per phase.

**V2 Token Budgets (REQ-12):** If yolo control-plane `compile` or `full` action was used and included token budget enforcement, skip this step. Otherwise, if `v2_token_budgets=true` in config:

- After context compilation, enforce per-role token budgets. When `v3_contract_lite=true` or `v2_hard_contracts=true`, pass the contract path and task number for per-task budget computation:

  ```bash
  BUDGET_OUT=$("$HOME/.cargo/bin/yolo" token-budget dev {phase-dir}/.context-dev.md {contract_path} {task_number})
  if echo "$BUDGET_OUT" | head -c 1 | grep -qv '{'; then
    echo "$BUDGET_OUT" > {phase-dir}/.context-dev.md
  fi
  ```

  The guard prevents overwriting the context file when `token-budget` reports within-budget (JSON metadata starting with `{`). Only when the output is truncated context (non-JSON) does the redirect apply.

  Where `{contract_path}` is `.yolo-planning/.contracts/{phase}-{plan}.json` (generated by yolo generate-contract in Step 3) and `{task_number}` is the current task being executed (1-based). When no contract is available, omit the contract_path and task_number arguments (per-role fallback).

- Role caps defined in `config/token-budgets.json`: Lead/Architect (500), Dev/Debugger (800).
- Per-task budgets use contract metadata (must_haves, allowed_paths, depends_on) to compute a complexity score, which maps to a tier multiplier applied to the role's base budget.
- Overage logged to metrics as `token_overage` event with role, lines truncated, and budget_source (task or role).
- **Escalation:** When overage occurs, yolo token-budget emits a `token_cap_escalated` event and reduces the remaining budget for subsequent tasks in the plan. The budget reduction state is stored in `.yolo-planning/.token-state/{phase}-{plan}.json`. Escalation is advisory only -- execution continues regardless.
- **Cleanup:** At phase end, clean up token state: `rm -f .yolo-planning/.token-state/*.json 2>/dev/null || true`
- Truncation uses tail strategy (keep most recent context).
- When `v2_token_budgets=false`: no truncation (pass through).

**Model resolution:** Resolve models for Dev agents:

```bash
DEV_MODEL=$("$HOME/.cargo/bin/yolo" resolve-model dev .yolo-planning/config.json ${CLAUDE_PLUGIN_ROOT}/config/model-profiles.json)
if [ $? -ne 0 ]; then echo "$DEV_MODEL" >&2; exit 1; fi
DEV_MAX_TURNS=$("$HOME/.cargo/bin/yolo" resolve-turns dev .yolo-planning/config.json "{effort}")
if [ $? -ne 0 ]; then echo "$DEV_MAX_TURNS" >&2; exit 1; fi
```

For each uncompleted plan, TaskCreate:

```
subject: "Execute {NN-MM}: {plan-title}"
description: |
  {DEV_CONTEXT}

  Execute all tasks in {PLAN_PATH}.
  Effort: {DEV_EFFORT}. Working directory: {pwd}.
  Model: ${DEV_MODEL}
  If `.yolo-planning/codebase/META.md` exists, read CONVENTIONS.md, PATTERNS.md, STRUCTURE.md, and DEPENDENCIES.md (whichever exist) from `.yolo-planning/codebase/` to bootstrap codebase understanding before executing.
  {If resuming: "Resume from Task {N}. Tasks 1-{N-1} already committed."}
  {If autonomous: false: "This plan has checkpoints -- pause for user input."}
activeForm: "Executing {NN-MM}"
```

Display: `◆ Spawning Dev teammate (${DEV_MODEL})...`

**CRITICAL:** Pass `model: "${DEV_MODEL}"` and `maxTurns: ${DEV_MAX_TURNS}` parameters to the Task tool invocation when spawning Dev teammates.
**CRITICAL:** When team was created (2+ plans), pass `team_name: "yolo-phase-{NN}"` and `name: "dev-{MM}"` parameters to each Task tool invocation. This enables colored agent labels and status bar entries.

Wire dependencies via TaskUpdate: read `depends_on` from each plan's frontmatter, add `addBlockedBy: [task IDs of dependency plans]`. Plans with empty depends_on start immediately.

Spawn Dev teammates and assign tasks. Platform enforces execution ordering via task deps. If `--plan=NN`: single task, no dependencies.

**Blocked agent notification (mandatory):** When a Dev teammate completes a plan (task marked completed + SUMMARY.md verified), check if any other tasks have `blockedBy` containing that completed task's ID. For each newly-unblocked task, send its assigned Dev a message: "Blocking task {id} complete. Your task is now unblocked — proceed with execution." This ensures blocked agents resume without manual intervention.

<!-- v3: validation-gates — see V3-EXTENSIONS.md when v3_* flags enabled -->

**Plan approval gate (effort-gated, autonomy-gated):**
When `v3_validation_gates=true`: use `approval_required` from gate policy above.
When `v3_validation_gates=false` (default): use static table:

| Autonomy            | Approval active at  |
| ------------------- | ------------------- |
| cautious            | Thorough + Balanced |
| standard            | Thorough only       |
| confident/pure-vibe | OFF                 |

When active: spawn Devs with `plan_mode_required`. Dev reads PLAN.md, proposes approach, waits for lead approval. Lead approves/rejects via plan_approval_response.
When off: Devs begin immediately.

**Teammate communication (effort-gated):**
When `v3_validation_gates=true`: use `communication_level` from gate policy (none/blockers/blockers_findings/full).
When `v3_validation_gates=false` (default): use static table:

Schema ref: `${CLAUDE_PLUGIN_ROOT}/references/handoff-schemas.md`

| Effort   | Messages sent                                                                                                |
| -------- | ------------------------------------------------------------------------------------------------------------ |
| Thorough | blockers (blocker_report), findings (scout_findings), progress (execution_update), contracts (plan_contract) |
| Balanced | blockers (blocker_report), progress (execution_update)                                                       |
| Fast     | blockers only (blocker_report)                                                                               |
| Turbo    | N/A (no team)                                                                                                |

Use targeted `message` not `broadcast`. Reserve broadcast for critical blocking issues only.

**V2 Typed Protocol (REQ-04, REQ-05):** If `v2_typed_protocol=true` in config:

- **On message receive** (from any teammate): validate before processing:
  `VALID=$(echo "$MESSAGE_JSON" | "$HOME/.cargo/bin/yolo" validate-message 2>/dev/null || echo '{"valid":true}')`
  If `valid=false`: log rejection, send error back to sender with `errors` array. Do not process the message.
- **On message send** (before sending): agents should construct messages using full V2 envelope (id, type, phase, task, author_role, timestamp, schema_version, payload, confidence). Reference `${CLAUDE_PLUGIN_ROOT}/references/handoff-schemas.md` for schema details.
- **Backward compatibility:** When `v2_typed_protocol=false`, validation is skipped. Old-format messages accepted.

**Execution state updates:**

- Task completion: update plan status in .execution-state.json (`"complete"` or `"failed"`)
- Wave transition: update `"wave"` when first wave N+1 task starts
- Use `jq` for atomic updates

Hooks handle continuous verification: PostToolUse validates SUMMARY.md, TaskCompleted verifies commits, TeammateIdle runs quality gate.

<!-- v3: event-log-plan-lifecycle — see V3-EXTENSIONS.md when v3_* flags enabled -->
<!-- v3: v2-full-event-types — see V3-EXTENSIONS.md when v3_* flags enabled -->

<!-- v3: snapshot-checkpoint — see V3-EXTENSIONS.md when v3_* flags enabled -->

<!-- v3: metrics — see V3-EXTENSIONS.md when v3_* flags enabled -->

<!-- v3: contract-lite — see V3-EXTENSIONS.md when v3_* flags enabled -->

**V2 Hard Gates (REQ-02, REQ-03):** If `v2_hard_gates=true` in config:

- **Pre-task gate sequence (before each task starts):**
  1. `contract_compliance` gate: `"$HOME/.cargo/bin/yolo" hard-gate contract_compliance {phase} {plan} {task} {contract_path}`
  2. **Lease acquisition** (V2 control plane): acquire exclusive file lease before protected_file check:
     - If `v3_lease_locks=true`: `"$HOME/.cargo/bin/yolo" lease-lock acquire {task_id} --ttl=300 {claimed_files...}`
     - Else if `v3_lock_lite=true`: `"$HOME/.cargo/bin/yolo" lock-lite acquire {task_id} {claimed_files...}`
     - Lease conflict → auto-repair attempt (wait + re-acquire), then escalate blocker if unresolved.
  3. `protected_file` gate: `"$HOME/.cargo/bin/yolo" hard-gate protected_file {phase} {plan} {task} {contract_path}`
  - If any gate fails (exit 2): attempt auto-repair:
    `REPAIR=$("$HOME/.cargo/bin/yolo" auto-repair {gate_type} {phase} {plan} {task} {contract_path})`
  - If `repaired=true`: re-run the failed gate to confirm, then proceed.
  - If `repaired=false`: emit blocker, halt task execution. Send Lead a message with the failure evidence and next action from the blocker event.
- **Post-task gate sequence (after each task commit):**
  1. `required_checks` gate: `"$HOME/.cargo/bin/yolo" hard-gate required_checks {phase} {plan} {task} {contract_path}`
  2. `commit_hygiene` gate: `"$HOME/.cargo/bin/yolo" hard-gate commit_hygiene {phase} {plan} {task} {contract_path}`
  3. **Lease release**: release file lease after task completes:
     - If `v3_lease_locks=true`: `"$HOME/.cargo/bin/yolo" lease-lock release {task_id}`
     - Else if `v3_lock_lite=true`: `"$HOME/.cargo/bin/yolo" lock-lite release {task_id}`
  - Gate failures trigger auto-repair with same flow as pre-task.
- **Post-plan gate (after all tasks complete, before marking plan done):**
  1. `artifact_persistence` gate: `"$HOME/.cargo/bin/yolo" hard-gate artifact_persistence {phase} {plan} {task} {contract_path}`
  2. `verification_threshold` gate: `"$HOME/.cargo/bin/yolo" hard-gate verification_threshold {phase} {plan} {task} {contract_path}`
  - These gates fire AFTER SUMMARY.md verification but BEFORE updating execution-state.json to "complete".
- **YOLO mode:** Hard gates ALWAYS fire regardless of autonomy level. YOLO only skips confirmation prompts.
- **Fallback:** If yolo hard-gate or yolo auto-repair errors (not a gate fail, but a script error), log to metrics and continue (fail-open on script errors, hard-stop only on gate verdicts).

<!-- v3: lock-lite — see V3-EXTENSIONS.md when v3_* flags enabled -->

<!-- v3: lease-locks — see V3-EXTENSIONS.md when v3_* flags enabled -->

### Step 3b: V2 Two-Phase Completion (REQ-09)

**If `v2_two_phase_completion=true` in config:**

After each task commit (and after post-task gates pass), run two-phase completion:

```bash
RESULT=$("$HOME/.cargo/bin/yolo" two-phase-complete {task_id} {phase} {plan} {contract_path} {evidence...})
```

- If `result=confirmed`: proceed to next task.
- If `result=rejected`: treat as gate failure — attempt auto-repair (re-run checks), then escalate blocker if still failing.
- Artifact registration: after each file write during task execution, register the artifact:

  ```bash
  "$HOME/.cargo/bin/yolo" artifact-registry register {file_path} {event_id} {phase} {plan}
  ```

- When `v2_two_phase_completion=false`: skip (direct task completion as before).

### Step 3c: SUMMARY.md verification gate (mandatory)

After all tasks in a plan complete, the Dev agent MUST write `{phase-dir}/{NN-MM}-SUMMARY.md` using the template at `templates/SUMMARY.md`.

**Required YAML frontmatter fields:**
- `phase` — phase ID (e.g., "03")
- `plan` — plan number (e.g., "01")
- `title` — plan title from PLAN.md frontmatter
- `status` — one of: `complete`, `partial`, `failed`
- `completed` — date in YYYY-MM-DD format
- `tasks_completed` — number of tasks completed
- `tasks_total` — total tasks in plan
- `commit_hashes` — list of commit SHAs (one per task)
- `deviations` — list of deviation descriptions, or empty list

**Required body sections:**
- `## What Was Built` — bullet list of deliverables
- `## Files Modified` — each file with action and purpose (`{file-path}` -- {action}: {purpose})
- `## Deviations` — any deviations from plan, or "None"

**Gate checks (all must pass for plan to be marked complete):**
1. File exists at `{phase-dir}/{NN-MM}-SUMMARY.md`
2. YAML frontmatter parses and contains all required fields listed above
3. `tasks_completed` equals `tasks_total` when `status` is `complete`
4. At least one entry in `commit_hashes`

If SUMMARY.md is missing or invalid, the plan is NOT considered complete. The Lead must not update execution-state.json to `"complete"` until this gate passes.

### Step 3d: QA gate verification (optional)

**Activation:** Read `qa_gate` from config:
```bash
QA_GATE=$(jq -r '.qa_gate // "on_request"' .yolo-planning/config.json 2>/dev/null)
```

| qa_gate | Behavior |
|---------|----------|
| always | Run QA verification on every phase after all Dev tasks complete |
| on_request | Skip unless user passes `--qa` flag |
| never | Skip entirely |

**When active:**

For each completed plan in the phase, run the following verification commands:

1. **Verify plan completion:**
```bash
"$HOME/.cargo/bin/yolo" verify-plan-completion {summary_path} {plan_path}
```
Check: SUMMARY.md has all required fields, task counts match plan, commit hashes present.

2. **Commit lint:**
```bash
"$HOME/.cargo/bin/yolo" commit-lint {commit_range}
```
Where `{commit_range}` is derived from the first commit before the phase to HEAD. Check: all commits follow `{type}({scope}): {description}` format.

3. **Diff against plan:**
```bash
"$HOME/.cargo/bin/yolo" diff-against-plan {summary_path}
```
Check: files modified in git match files declared in SUMMARY.md.

4. **Validate requirements:**
```bash
"$HOME/.cargo/bin/yolo" validate-requirements {plan_path} {phase_dir}
```
Check: must_haves from plan have evidence in SUMMARY/code.

5. **Check regression:**
```bash
"$HOME/.cargo/bin/yolo" check-regression {phase_dir}
```
Check: test count hasn't decreased.

**Aggregate results:**
- If ALL checks pass (exit 0): Display `✓ QA verification passed` and proceed to Step 4
- If ANY check fails (exit 1): Display `✗ QA verification failed` with findings. STOP execution.
- Produce structured report: `{passed: bool, checks: [{name, status, evidence}], regressions: N}`

**When inactive:** Display `○ QA gate skipped (qa_gate: {value})` and proceed to Step 4.

### Step 4: Verification (Native Testing)

**Deprecated `yolo-qa` Agent:** The conceptual QA agent has been natively integrated into the Dev execution tools via MCP. The Dev agent is responsible for executing expected tests from the PLAN.md directly using the native run_test_suite MCP command and fixing their own stack traces within the exact same context loop.

No parallel QA agent should be spawned. Verification operates continuously within the Dev lifecycle.

### Step 4.5: Human acceptance testing (UAT)

**Autonomy gate:**

| Autonomy  | UAT active |
| --------- | ---------- |
| cautious  | YES        |
| standard  | YES        |
| confident | OFF        |
| pure-vibe | OFF        |

Read autonomy from config: `jq -r '.autonomy // "standard"' .yolo-planning/config.json`

If autonomy is confident or pure-vibe: display "○ UAT verification skipped (autonomy: {level})" and proceed to Step 5.

**UAT execution (cautious + standard):**

1. Check if `{phase-dir}/{phase}-UAT.md` already exists with `status: complete`. If so: "○ UAT already complete" and proceed to Step 5.
2. Generate test scenarios from completed SUMMARY.md files (same logic as `commands/verify.md`).
3. Run CHECKPOINT loop inline (same protocol as `commands/verify.md` Steps 4-8).
4. After all tests complete:
   - If no issues: proceed to Step 5
   - If issues found: display issue summary, suggest `/yolo:fix`, STOP (do not proceed to Step 5)

Note: "Run inline" means the execute-protocol agent runs the verify protocol directly, not by invoking /yolo:verify as a command. The protocol is the same; the entry point differs.

### Step 5: Update state and present summary

**HARD GATE — Shutdown before ANY output or state updates:** If a team was created (2+ uncompleted plans AND prefer_teams permitted it -- see single-plan optimization in Step 3), you MUST shut down the team BEFORE updating state, presenting results, or asking the user anything. This is blocking and non-negotiable:

1. Send `shutdown_request` via SendMessage to EVERY active teammate (excluding yourself -- the orchestrator controls the sequence, not the lead agent) -- do not skip any
2. Log event: `"$HOME/.cargo/bin/yolo" log-event shutdown_sent {phase} team={team_name} targets={count} 2>/dev/null || true`
3. Wait for each `shutdown_response` with `approved: true`. If a teammate rejects, re-request immediately (max 3 attempts per teammate -- if still rejected after 3 attempts, log a warning and proceed with TeamDelete).
4. Log event: `"$HOME/.cargo/bin/yolo" log-event shutdown_received {phase} team={team_name} approved={count} rejected={count} 2>/dev/null || true`
5. Call TeamDelete for team "yolo-phase-{NN}"
6. Only THEN proceed to state updates and user-facing output below
   Failure to shut down leaves agents running in the background, consuming API credits (visible as hanging panes in tmux, invisible but still costly without tmux).

If no team was created (single-plan optimization applied, turbo mode, or smart-routed turbo): skip the entire shutdown sequence above and proceed directly to state updates.

**Post-shutdown verification:** After TeamDelete, there must be ZERO active teammates. If the Pure-Vibe loop or auto-chain will re-enter Plan mode next, confirm no prior agents linger before spawning new ones. This gate survives compaction — if you lost context about whether shutdown happened, assume it did NOT and send `shutdown_request` to any teammates that may still exist before proceeding.

**Control Plane cleanup:** Lock and token state cleanup already handled by existing V3 Lock-Lite and Token Budget cleanup blocks.

<!-- v3: rolling-summary — see V3-EXTENSIONS.md when v3_* flags enabled -->

<!-- v3: event-log-phase-end — see V3-EXTENSIONS.md when v3_* flags enabled -->

**V2 Observability Report (REQ-14):** After phase completion, if `v3_metrics=true` or `v3_event_log=true`:

- Generate observability report: `"$HOME/.cargo/bin/yolo" metrics-report {phase}`
- The report aggregates 7 V2 metrics: task latency, tokens/task, gate failure rate, lease conflicts, resume success, regression escape, fallback %.
- Display summary table in phase completion output.
- Dashboards show by profile (thorough|balanced|fast|turbo) and autonomy (cautious|standard|confident|pure-vibe).

**Mark complete:** Set .execution-state.json `"status"` to `"complete"` (statusline auto-deletes on next refresh).
**Update STATE.md:** phase position, plan completion counts, effort used.
**Update ROADMAP.md:** mark completed plans.

**Planning artifact boundary commit (conditional):**

```bash
"$HOME/.cargo/bin/yolo" planning-git commit-boundary "complete phase {N}" .yolo-planning/config.json
```

- `planning_tracking=commit`: commits `.yolo-planning/` + `CLAUDE.md` when changed
- `planning_tracking=manual|ignore`: no-op
- `auto_push=always`: push happens inside the boundary commit command when upstream exists

**After-phase push (conditional):**

```bash
"$HOME/.cargo/bin/yolo" planning-git push-after-phase .yolo-planning/config.json
```

- `auto_push=after_phase`: pushes once after phase completion (if upstream exists)
- other modes: no-op

Display per @${CLAUDE_PLUGIN_ROOT}/references/yolo-brand-essentials.md:

```text
╔═══════════════════════════════════════════════╗
║  Phase {N}: {name} -- Built                   ║
╚═══════════════════════════════════════════════╝

  Plan Results:
    ✓ Plan 01: {title}  /  ✗ Plan 03: {title} (failed)

  Metrics:
    Plans: {completed}/{total}  Effort: {profile}  Model Profile: {profile}  Deviations: {count}

  Verification: Integrated (Native Testing)
```

**"What happened" (NRW-02):** If config `plain_summary` is true (default), append 2-4 plain-English sentences between Verification and Next Up. No jargon. Source from SUMMARY.md files. If false, skip.

**Discovered Issues:** If any Dev or QA agent reported pre-existing failures, out-of-scope bugs, or issues unrelated to this phase's work, collect and de-duplicate them by test name and file (when the same test+file pair appears with different error messages, keep the first error message encountered), then list them in the summary output between "What happened" and Next Up. To keep context size manageable, cap the displayed list at 20 entries; if more exist, show the first 20 and append `... and {N} more`. Format each bullet as `⚠ testName (path/to/file): error message`:

```text
  Discovered Issues:
    ⚠ {issue-1}
    ⚠ {issue-2}
  Suggest: /yolo:todo <description> to track
```

This is **display-only**. Do NOT edit STATE.md, do NOT add todos, do NOT invoke /yolo:todo, and do NOT enter an interactive loop. The user decides whether to track these. If no discovered issues: omit the section entirely. After displaying discovered issues, STOP. Do not take further action.

Run `"$HOME/.cargo/bin/yolo" suggest-next execute pass` and display output.

**STOP.** Execute mode is complete. Return control to the user. Do NOT take further actions — no file edits, no additional commits, no interactive prompts, no improvised follow-up work. The user will decide what to do next based on the summary and suggest-next output.

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/yolo-brand-essentials.md — Phase Banner (double-line box), ◆ running, ✓ complete, ✗ failed, ○ skipped, Metrics Block, Next Up Block, no ANSI color codes.
