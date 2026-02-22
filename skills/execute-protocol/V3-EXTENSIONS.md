# V3 Extensions — Execute Protocol

Loaded on demand when ANY `v3_*` flag is `true` in `.yolo-planning/config.json`.
Parent: `skills/execute-protocol/SKILL.md`

---

## V3 Event Recovery (REQ-17)

If `v3_event_recovery=true` in config, attempt event-sourced recovery first:
`RECOVERED=$("$HOME/.cargo/bin/yolo" recover-state {phase} 2>/dev/null || echo "{}")`
If non-empty and has `plans` array, use recovered state as the baseline instead of the stale execution-state.json. This provides more accurate status when execution-state.json was not written (crash before flush).

## V3 Event Log — phase start (REQ-16)

If `v3_event_log=true` in config:
- Log phase start: `"$HOME/.cargo/bin/yolo" log-event phase_start {phase} 2>/dev/null || true`

## V3 Snapshot Resume (REQ-18)

If `v3_snapshot_resume=true` in config:
- On crash recovery (execution-state.json exists with `"status": "running"`): attempt restore:
  `SNAPSHOT=$("$HOME/.cargo/bin/yolo" snapshot-resume restore {phase} {preferred-role} 2>/dev/null || echo "")`
- If snapshot found, log: `✓ Snapshot found: ${SNAPSHOT}` — use snapshot's `recent_commits` to cross-reference git log for more reliable resume-from detection.

## V3 Schema Validation (REQ-17)

If `v3_schema_validation=true` in config:

- Validate each PLAN.md frontmatter before execution:
  `VALID=$("$HOME/.cargo/bin/yolo" validate-schema plan {plan_path} 2>/dev/null || echo "valid")`
- If `invalid`: log warning `⚠ Plan {NN-MM} schema: ${VALID}` — continue execution (advisory only).
- Log to metrics: `"$HOME/.cargo/bin/yolo" collect-metrics schema_check {phase} {plan} result=$VALID 2>/dev/null || true`

## V3 Smart Routing (REQ-15)

If `v3_smart_routing=true` in config:

- Before creating agent teams, assess each plan:

  ```bash
  RISK=$("$HOME/.cargo/bin/yolo" assess-plan-risk {plan_path} 2>/dev/null || echo "medium")
  TASK_COUNT=$(grep -c '^### Task [0-9]' {plan_path} 2>/dev/null || echo "0")
  ```

- If `RISK=low` AND `TASK_COUNT<=3` AND effort is not `thorough`: force turbo execution for this plan (no team, direct implementation). Log routing decision:
  `"$HOME/.cargo/bin/yolo" collect-metrics smart_route {phase} {plan} risk=$RISK tasks=$TASK_COUNT routed=turbo 2>/dev/null || true`
- Otherwise: proceed with normal team delegation. Log:
  `"$HOME/.cargo/bin/yolo" collect-metrics smart_route {phase} {plan} risk=$RISK tasks=$TASK_COUNT routed=team 2>/dev/null || true`
- On script error: fall back to configured effort level.

## V3 Monorepo Routing (REQ-17)

If `v3_monorepo_routing=true` in config:

- Before context compilation, detect relevant package paths:
  `PACKAGES=$("$HOME/.cargo/bin/yolo" route-monorepo {phase_dir} 2>/dev/null || echo "[]")`
- If non-empty array (not `[]`): pass package paths to context compilation for scoped file inclusion.
  Log: `"$HOME/.cargo/bin/yolo" collect-metrics monorepo_route {phase} packages=$PACKAGES 2>/dev/null || true`
- If empty or error: proceed with default (full repo) context compilation.

## V3 Validation Gates (REQ-13, REQ-14)

If `v3_validation_gates=true` in config:

- **Per plan:** Assess risk and resolve gate policy:

  ```bash
  RISK=$("$HOME/.cargo/bin/yolo" assess-plan-risk {plan_path} 2>/dev/null || echo "medium")
  GATE_POLICY=$("$HOME/.cargo/bin/yolo" resolve-gate-policy {effort} $RISK {autonomy} 2>/dev/null || echo '{}')
  ```

- Extract policy fields: `approval_required`, `communication_level`, `two_phase`
- Use these to override the static tables below for this plan
- Log to metrics: `"$HOME/.cargo/bin/yolo" collect-metrics gate_policy {phase} {plan} risk=$RISK approval=$APPROVAL 2>/dev/null || true`
- On script error: fall back to static tables below

## V3 Event Log — plan lifecycle (REQ-16)

If `v3_event_log=true` in config:

- At plan start: `"$HOME/.cargo/bin/yolo" log-event plan_start {phase} {plan} 2>/dev/null || true`
- At agent spawn: `"$HOME/.cargo/bin/yolo" log-event agent_spawn {phase} {plan} role=dev model=$DEV_MODEL 2>/dev/null || true`
- At agent shutdown: `"$HOME/.cargo/bin/yolo" log-event agent_shutdown {phase} {plan} role=dev 2>/dev/null || true`
- At plan complete: `"$HOME/.cargo/bin/yolo" log-event plan_end {phase} {plan} status=complete 2>/dev/null || true`
- At plan failure: `"$HOME/.cargo/bin/yolo" log-event plan_end {phase} {plan} status=failed 2>/dev/null || true`
- On error: `"$HOME/.cargo/bin/yolo" log-event error {phase} {plan} message={error_summary} 2>/dev/null || true`

## V2 Full Event Types (REQ-09, REQ-10)

If `v3_event_log=true` in config, emit all 13 V2 event types at correct lifecycle points.

> **Naming convention:** Event types (`shutdown_sent`/`shutdown_received`) log _what happened_ — the orchestrator sent or received a message. Message types (`shutdown_request`/`shutdown_response`) define _what was communicated_ — the typed payload in SendMessage. Events are emitted by `yolo log-event`; messages are validated by `yolo validate-message`.

- `phase_planned`: at plan completion (after Lead writes PLAN.md): `yolo log-event phase_planned {phase}`
- `task_created`: when task is defined in plan: `yolo log-event task_created {phase} {plan} task_id={id}`
- `task_claimed`: when Dev starts a task: `yolo log-event task_claimed {phase} {plan} task_id={id} role=dev`
- `task_started`: when task execution begins: `yolo log-event task_started {phase} {plan} task_id={id}`
- `artifact_written`: after writing/modifying a file: `yolo log-event artifact_written {phase} {plan} path={file} task_id={id}`
  - Also register in artifact registry: `"$HOME/.cargo/bin/yolo" artifact-registry register {file} {event_id} {phase} {plan}`
- `gate_passed` / `gate_failed`: already emitted by yolo hard-gate
- `task_completed_candidate`: emitted by yolo two-phase-complete
- `task_completed_confirmed`: emitted by yolo two-phase-complete after validation
- `task_blocked`: already emitted by yolo auto-repair
- `task_reassigned`: when task is re-assigned to different agent: `yolo log-event task_reassigned {phase} {plan} task_id={id} from={old} to={new}`
- `shutdown_sent`: when orchestrator sends shutdown_request to teammates: `yolo log-event shutdown_sent {phase} team={team_name} targets={count}`
- `shutdown_received`: when orchestrator has collected all shutdown_response messages: `yolo log-event shutdown_received {phase} team={team_name} approved={count} rejected={count}`

## V3 Snapshot — per-plan checkpoint (REQ-18)

If `v3_snapshot_resume=true` in config:

- After each plan completes (SUMMARY.md verified):
  `"$HOME/.cargo/bin/yolo" snapshot-resume save {phase} .yolo-planning/.execution-state.json {agent-role} {trigger} 2>/dev/null || true`
- This captures execution state + recent git context for crash recovery. The optional `{agent-role}` and `{trigger}` arguments add metadata to the snapshot for role-filtered restore.

## V3 Metrics instrumentation (REQ-09)

If `v3_metrics=true` in config:

- At phase start: `"$HOME/.cargo/bin/yolo" collect-metrics execute_phase_start {phase} plan_count={N} effort={effort}`
- At each plan completion: `"$HOME/.cargo/bin/yolo" collect-metrics execute_plan_complete {phase} {plan} task_count={N} commit_count={N}`
- At phase end: `"$HOME/.cargo/bin/yolo" collect-metrics execute_phase_complete {phase} plans_completed={N} total_tasks={N} total_commits={N} deviations={N}`
  All metrics calls should be `2>/dev/null || true` — never block execution.

## V3 Contract-Lite (REQ-10)

If `v3_contract_lite=true` in config:

- **Once per plan (before first task):** Generate contract sidecar:
  `"$HOME/.cargo/bin/yolo" generate-contract {plan_path} 2>/dev/null || true`
  This produces `.yolo-planning/.contracts/{phase}-{plan}.json` with allowed_paths and must_haves.
- **Before each task:** Validate task start:
  `"$HOME/.cargo/bin/yolo" validate-contract start {contract_path} {task_number} 2>/dev/null || true`
- **After each task:** Validate modified files against contract:
  `"$HOME/.cargo/bin/yolo" validate-contract end {contract_path} {task_number} {modified_files...} 2>/dev/null || true`
  Where `{modified_files}` comes from `git diff --name-only HEAD~1` after the task's commit.
- Violations are advisory only (logged to metrics, not blocking).

## V3 Lock-Lite (REQ-11)

If `v3_lock_lite=true` in config:

- **Before each task:** Acquire lock with claimed files:
  `"$HOME/.cargo/bin/yolo" lock-lite acquire {task_id} {claimed_files...} 2>/dev/null || true`
  Where `{task_id}` is `{phase}-{plan}-T{N}` and `{claimed_files}` from the task's **Files:** list.
- **After each task (or on failure):** Release lock:
  `"$HOME/.cargo/bin/yolo" lock-lite release {task_id} 2>/dev/null || true`
- Conflicts are advisory only (logged to metrics, not blocking).
- Lock cleanup: at phase end, `rm -f .yolo-planning/.locks/*.lock 2>/dev/null || true`.

## V3 Lease Locks (REQ-17)

If `v3_lease_locks=true` in config:

- Use `yolo lease-lock` instead of `yolo lock-lite` for all lock operations above:
  - Acquire: `"$HOME/.cargo/bin/yolo" lease-lock acquire {task_id} --ttl=300 {claimed_files...} 2>/dev/null || true`
  - Release: `"$HOME/.cargo/bin/yolo" lease-lock release {task_id} 2>/dev/null || true`
- **During long-running tasks** (>2 minutes estimated): renew lease periodically:
  `"$HOME/.cargo/bin/yolo" lease-lock renew {task_id} 2>/dev/null || true`
- Check for expired leases before acquiring: `"$HOME/.cargo/bin/yolo" lease-lock check {task_id} {claimed_files...} 2>/dev/null || true`
- If both `v3_lease_locks` and `v3_lock_lite` are true, lease-lock takes precedence.

## V3 Rolling Summary (REQ-03)

If `v3_rolling_summary=true` in config:

- After TeamDelete (team fully shut down), before phase_end event log:

  ```bash
  "$HOME/.cargo/bin/yolo" compile-rolling-summary \
    .yolo-planning/phases .yolo-planning/ROLLING-CONTEXT.md 2>/dev/null || true
  ```

  This compiles all completed SUMMARY.md files into a condensed digest for the next phase's agents.
  Fail-open: if script errors, log warning and continue — never block phase completion.

- When `v3_rolling_summary=false` (default): skip this step silently.

## V3 Event Log — phase end (REQ-16)

If `v3_event_log=true` in config:

- `"$HOME/.cargo/bin/yolo" log-event phase_end {phase} plans_completed={N} total_tasks={N} 2>/dev/null || true`
