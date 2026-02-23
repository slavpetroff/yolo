# YOLO Typed Communication Protocol

V2 inter-agent messages use strict JSON schemas. Every message includes a mandatory envelope. Machine-readable definitions at `config/schemas/message-schemas.json`.

## Envelope (mandatory on all messages)

```json
{
  "id": "uuid-v4",
  "type": "plan_contract|execution_update|blocker_report|approval_request|approval_response|scout_findings|shutdown_request|shutdown_response",
  "phase": 1,
  "task": "1-1-T3",
  "author_role": "lead|dev|debugger|architect|docs",
  "timestamp": "2026-02-12T10:00:00Z",
  "schema_version": "2.0",
  "payload": {},
  "confidence": "high|medium|low"
}
```

## Role Authorization Matrix

| Message Type      | Allowed Senders           | Typical Receivers         |
| ----------------- | ------------------------- | ------------------------- |
| plan_contract     | lead, architect           | dev                       |
| execution_update  | dev, docs                 | lead                      |
| blocker_report    | dev, docs                 | lead                      |
| debugger_report   | debugger                  | lead                      |
| approval_request  | dev, lead                 | lead, architect           |
| approval_response | lead, architect           | dev, lead                 |
| scout_findings    | scout                     | lead, architect           |
| shutdown_request  | lead (orchestrator)       | dev, lead, debugger, docs |
| shutdown_response | dev, lead, debugger, docs | lead (orchestrator)       |

Unauthorized sender -> message rejected (v2_typed_protocol=true) or logged (false).

## Payload Schemas

All examples below show only the `payload` field. Wrap in the envelope above before sending.

## `plan_contract` (Lead/Architect -> Dev)

```json
{
  "plan_id": "phase-1-plan-1",
  "phase_id": "phase-1",
  "objective": "Implement feature X",
  "tasks": ["1-1-T1", "1-1-T2"],
  "allowed_paths": ["src/feature.js", "tests/feature.test.js"],
  "must_haves": ["Feature passes tests", "No regressions"],
  "forbidden_paths": [".env", "secrets/"],
  "depends_on": [],
  "verification_checks": ["npm test"],
  "token_budget": 50000
}
```

## `execution_update` (Dev/Docs -> Lead)

```json
{
  "plan_id": "1-1",
  "task_id": "1-1-T3",
  "status": "complete|partial|failed",
  "commit": "abc1234",
  "files_modified": ["src/feature.js"],
  "concerns": ["Interface changed — downstream plans may need update"],
  "evidence": "All tests pass",
  "pre_existing_issues": [{ "test": "testName", "file": "path", "error": "msg" }]
}
```

## `blocker_report` (Dev/Docs -> Lead)

```json
{
  "plan_id": "1-2",
  "task_id": "1-2-T1",
  "blocker": "Dependency module from plan 1-1 not yet committed",
  "needs": "Plan 1-1 to complete first",
  "attempted": ["Checked git log for 1-1 commits — none found"],
  "severity": "blocking|degraded|informational",
  "pre_existing_issues": []
}
```

## `debugger_report` (Debugger -> Lead)

Envelope: `"type": "debugger_report"`. Distinct from `blocker_report` -- uses diagnostic fields, not escalation fields.

```json
{
  "hypothesis": "Race condition in sync handler causes intermittent auth failure",
  "evidence_for": ["Thread dump shows concurrent access at auth.js:42", "Failure rate correlates with load"],
  "evidence_against": ["Single-threaded test passes consistently"],
  "confidence": "high",
  "recommended_fix": "Add mutex lock around credential refresh in auth.js:40-50",
  "pre_existing_issues": []
}
```

`pre_existing_issues`: omit or pass empty array if none found (applies to execution_update, blocker_report, debugger_report).

## `approval_request` (Dev/Lead -> Lead/Architect)

```json
{
  "subject": "Scope expansion needed for Task 3",
  "request_type": "scope_change|plan_approval|gate_override",
  "evidence": "Task requires modifying auth module not in allowed_paths",
  "options": ["Expand contract", "Split into new task"],
  "deadline": "2026-02-12T12:00:00Z"
}
```

## `approval_response` (Lead/Architect -> Dev/Lead)

```json
{
  "request_id": "approve-678",
  "approved": true,
  "reason": "Auth module access justified by cross-cutting dependency",
  "conditions": ["Must not change existing API surface"],
  "modifications": []
}
```

## `scout_findings` (Scout -> Lead/Architect)

```json
{
  "topic": "Research topic or question",
  "findings": [
    {
      "source": "URL or file path",
      "insight": "Key finding text",
      "confidence": "high|medium|low"
    }
  ],
  "recommendations": ["Actionable next step 1", "Actionable next step 2"]
}
```

## `shutdown_request` (Orchestrator -> All teammates)

```json
{ "reason": "phase_complete|plan_complete|user_abort", "team_name": "yolo-phase-01" }
```

## `shutdown_response` (Teammate -> Orchestrator)

```json
{ "request_id": "shut-001", "approved": true, "final_status": "complete|idle|in_progress", "pending_work": "" }
```

On receiving `shutdown_request`: respond with `shutdown_response` (approved=true), finish any in-progress tool call, then STOP all further work. Do NOT start new tasks after responding.

> **Conditional refusal:** The schema allows `approved: false` with `pending_work` describing what remains. Currently all agents always approve. The orchestrator retries up to 3 times on rejection before proceeding.
