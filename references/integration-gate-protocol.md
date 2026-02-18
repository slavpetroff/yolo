# Integration Gate Protocol

Cross-department barrier convergence and contract validation. Runs after all active departments complete their execution pipeline (post-phase QA gates passed) and before Owner sign-off.

## Overview

The Integration Gate is the final automated check before Owner reviews department results. It validates that cross-department contracts are honored, design handoffs are implemented, all departments have signaled completion, and no department has failing tests. The gate produces `integration-gate-result.jsonl` consumed by Owner for Mode 3 sign-off.

## Trigger Conditions

The Integration Gate fires when ALL of these are true:

1. All active departments have written `.dept-status-{dept}.json` with `status:"complete"`
2. All active departments have passed their post-phase QA gates
3. The workflow step is between "security" (Step 10) and "signoff" (Step 11)

The gate is invoked by `scripts/integration-gate.sh` and optionally by the `yolo-integration-gate` agent for deeper LLM-powered analysis.

## Check Matrix

| Check | Artifact | Pass Condition | Fail Condition | Skip Condition |
|-------|----------|---------------|----------------|----------------|
| API Contracts | `api-contracts.jsonl` | All endpoints `status:"agreed"` or `status:"implemented"` | Any endpoint `status:"proposed"` or `status:"disputed"` | File missing or single-dept mode |
| Design Sync | `design-handoff.jsonl` + `*.summary.jsonl` | All `status:"ready"` components have implementation evidence in summary `fm` fields | Ready components with no implementation match | File missing or UI/UX dept disabled |
| Handoff Sentinels | `.handoff-{dept}-complete` | Sentinel exists for every active department | Missing sentinel for any active department | N/A (always runs) |
| Test Results | `test-results.jsonl` | All departments have `fl:0` (zero failures) | Any department has `fl > 0` | File missing |

## Failure Handling

### PASS (all checks green)

Gate writes `integration-gate-result.jsonl` with `r:"PASS"`. Owner proceeds to Mode 3 sign-off. No remediation needed.

### FAIL (critical check red)

Gate writes `integration-gate-result.jsonl` with `r:"FAIL"` and populated `failures` array. Each failure entry identifies the check, specific detail, and source file. Lead routes failures to the responsible department for remediation. After fix, gate re-runs.

Remediation routing:
- API contract failures -> Frontend Lead + Backend Lead negotiate resolution
- Design sync failures -> UX Lead + Frontend Lead coordinate
- Handoff sentinel missing -> Responsible department Lead completes workflow
- Test failures -> Responsible department Lead dispatches fix via Senior -> Dev

### PARTIAL (non-critical failures only)

Gate writes `integration-gate-result.jsonl` with `r:"PARTIAL"`. Owner reviews accepted gaps and decides SHIP or HOLD. Typical PARTIAL scenarios: design sync skip (UX dept disabled), API contracts skip (single-dept mode).

## Timeout Behavior

The `--timeout` flag (default 300s) controls how long the script waits for department completion. Timeout is checked BEFORE cross-dept checks run.

| State | Output |
|-------|--------|
| All depts complete before timeout | Run cross-dept checks, output gate result |
| Not all depts complete, timeout not reached | Exit 1 with `gate:"timeout"` and per-dept status |
| Not all depts complete, timeout reached | Exit 1 with `gate:"timeout"` and per-dept status |

The orchestrator is responsible for retry logic. The script itself does not poll or wait -- it checks current state and exits.

## Single-Department Mode

When only one department is active (typically backend-only):

- API contract check: **skip** (no cross-dept contracts to validate)
- Design sync check: **skip** (no UX handoff)
- Handoff sentinels: **still checked** (even single dept needs completion signal)
- Test results: **still checked** (test failures block regardless)

Single-dept mode produces `gate:"pass"` when handoffs and tests pass, even with API/design skipped. This ensures backward compatibility with existing single-department workflows.

## Effort-Based Behavior

| Effort | Gate Behavior |
|--------|--------------|
| turbo | Skip gate entirely. Departments self-certify via `.dept-status` files. |
| fast | Handoff sentinels + test results only. Skip API contract and design sync. |
| balanced | Full 4-check protocol. |
| thorough | Full protocol + deep cross-reference of every `fm` field against design components. |

## Artifacts

**Input:** `api-contracts.jsonl`, `design-handoff.jsonl`, `test-results.jsonl`, `*.summary.jsonl`, `.dept-status-{dept}.json`, `.handoff-{dept}-complete`, `config/defaults.json`

**Output:** `integration-gate-result.jsonl` (schema in `references/artifact-formats.md`)

**Script:** `scripts/integration-gate.sh --phase-dir <dir> --config <config-path> [--timeout <seconds>]`

**Agent:** `agents/yolo-integration-gate.md` (read-only, LLM-powered deeper analysis)
