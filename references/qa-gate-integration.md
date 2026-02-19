# QA Gate Integration

Three-level continuous QA system providing fast automated pre-checks at task, plan, and phase boundaries. These gates run script-only validation (no LLM cost) before expensive LLM-powered QA agents are spawned. Gates catch obvious failures early -- test regressions, missing artifacts, coverage gaps -- so QA agents focus on deep verification rather than discovering surface-level breakage.

## Gate Levels

All gate tiers are consolidated into a single `qa-gate.sh` dispatcher with a `--tier` flag:

| Level | Trigger Point | Invocation | Scope | Timeout | Blocking Behavior |
|-------|--------------|------------|-------|---------|-------------------|
| post-task | After each Dev commit in Step 7 | `qa-gate.sh --tier task` | `--scope` (task-modified files only) | 30s | Blocks next task |
| post-plan | After summary.jsonl written in Step 7 | `qa-gate.sh --tier plan` | Full test suite | 300s | Blocks next plan |
| post-phase | Before QA agent spawn in Step 9 | `qa-gate.sh --tier phase` | Full test suite + gate validation | 300s | Blocks QA agent spawn |
| (no tier) | TeammateIdle notification hook | `qa-gate.sh` (stdin) | Structural checks | N/A | Exit 0=allow, 2=block |

## Failure Handling

### Post-task Failure

1. Dev pauses current task loop.
2. Senior reviews test failures from gate JSON output (`tst.fl` field).
3. Senior re-specs fix instructions.
4. Dev implements fix and re-commits.
5. Re-run post-task gate.
6. Max 2 remediation cycles per task -- after cycle 2 still failing, Senior escalates to Lead.

### Post-plan Failure

1. Block progression to next plan.
2. Read gate JSON: check `tst` (test failures), `mh` (must_have failures).
3. For test failures: Senior reviews, re-specs fix tasks, Dev implements.
4. For must_have failures: Senior reviews plan coverage gaps.
5. Max 1 remediation cycle at post-plan level -- persistent failure escalates to Lead.

### Post-phase Failure

1. BLOCK QA agent spawn (saves LLM cost on obviously-broken phases).
2. Read gate JSON for failure details: `plans.complete` (incomplete plans), `steps.fl` (failed validation gates), `tst.fl` (test failures).
3. Generate remediation: for incomplete plans, route back to Step 7. For failed gates, identify which step artifacts are missing. For test failures, route to Senior for re-spec.
4. Do NOT spawn QA agents until post-phase gate passes.

## Skip Conditions

| Condition | Effect | Gate Output |
|-----------|--------|-------------|
| `--skip-qa` flag | Skips all gates AND Step 9 QA agents | `{"gate":"skipped"}` (exit 0) |
| `--effort=turbo` | Skips all gates (no tests run) | `{"gate":"skipped"}` (exit 0) |
| `qa_gates.post_task=false` | Skips post-task gate only | `{"gate":"skipped"}` (exit 0) |
| `qa_gates.post_plan=false` | Skips post-plan gate only | `{"gate":"skipped"}` (exit 0) |
| `qa_gates.post_phase=false` | Skips post-phase gate only | `{"gate":"skipped"}` (exit 0) |

When skipped, gate outputs `{"gate":"skipped"}` JSON and exits 0. Downstream consumers treat `skipped` as a non-blocking pass.

## Team Mode Differences

| Aspect | `team_mode=task` | `team_mode=teammate` |
|--------|-----------------|---------------------|
| Post-task gate runner | Orchestrator (Lead) runs after each Dev task commit | Dev runs autonomously after each self-claimed task commit |
| Post-task reporting | Sequential execution, orchestrator tracks results | Dev sends gate result to Senior via `dev_progress` message (include `gate_status` field). On fail, Dev sends `dev_blocker` to Senior with gate output. |
| Post-plan gate runner | Orchestrator runs after Dev writes summary.jsonl | Lead runs after writing summary.jsonl (Lead is sole summary writer in teammate mode) |
| Post-plan failure routing | Orchestrator routes to Senior | Lead sends gate result to Senior for review |
| Post-phase gate runner | Orchestrator runs before QA agent spawn | Lead runs before registering QA teammates |
| Execution model | Sequential gate execution | Dev-level gates run in parallel across self-claiming Devs |

Post-task in teammate mode: Dev is responsible for gate execution and reporting result to Senior. This is part of the Dev claim loop (steps 5-6 in the self-claiming flow).

## Config Options

Configuration lives in `config/defaults.json` under the `qa_gates` object. See `commands/config.md` for interactive configuration via `/yolo:config`.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `post_task` | bool | `true` | Enable/disable post-task gate after each Dev commit |
| `post_plan` | bool | `true` | Enable/disable post-plan gate after summary.jsonl |
| `post_phase` | bool | `true` | Enable/disable post-phase gate before QA agent spawn |
| `timeout_seconds` | int | `300` | Maximum gate execution time before timeout |
| `failure_threshold` | enum | `"critical"` | Minimum severity to trigger gate failure (`critical`, `major`, `minor`) |

## Result Storage

Gate results are stored in `{phase-dir}/.qa-gate-results.jsonl` in append mode. Writes are serialized via `flock` to prevent concurrent write corruption when multiple Devs run post-task gates simultaneously in teammate mode.

Schema reference: see `references/artifact-formats.md` for the gate result JSONL schema.

Results are consumed by QA agents in Step 9. QA Lead and QA Code can reference prior gate results in `.qa-gate-results.jsonl` for incremental verification -- avoiding re-checking issues already caught and resolved by gates.

## Output Format

See `references/qa-output-patterns.md` for human-readable output templates used by gate scripts.

## Relationship to QA Agents

Gates and QA agents serve complementary but distinct roles:

- **Gates** are fast automated pre-checks (<60s). They run scripts only -- no LLM invocation. They catch obvious failures: test regressions, missing artifacts, coverage gaps.
- **QA agents** (`yolo-qa`, `yolo-qa-code`) are deep LLM-powered verification (5-10min). They analyze code quality, architectural compliance, edge cases, and cross-cutting concerns.

Gates do NOT replace agents. Gates catch obvious failures early so agents can focus on deep analysis. Cost optimization: if a gate fails, agents never spawn -- this saves LLM tokens on phases that have surface-level breakage. If a gate passes, agents still run full verification.
