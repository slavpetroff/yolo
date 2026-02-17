# YOLO Structured Handoff Schemas

JSON-structured SendMessage schemas with `type` discriminator. Receivers: `JSON.parse` content; fall back to plain text on parse failure.

## `critique_result` (Critic -> Lead)

Brainstorm and gap-analysis findings for a phase, produced before architecture begins.

```json
{
  "type": "critique_result",
  "phase": "01",
  "findings": 7,
  "critical": 1,
  "major": 3,
  "minor": 3,
  "categories": ["gap", "risk", "improvement", "question"],
  "artifact": "phases/01-auth/critique.jsonl",
  "committed": false
}
```

Note: Critic has no Write tool — returns findings to Lead who writes critique.jsonl and commits.

## `test_plan_result` (Tester -> Senior)

TDD RED phase test authoring results.

```json
{
  "type": "test_plan_result",
  "plan_id": "01-01",
  "tasks_tested": 3,
  "tasks_skipped": 1,
  "total_tests": 12,
  "all_red": true,
  "artifact": "phases/01-auth/test-plan.jsonl",
  "committed": true
}
```

## `architecture_design` (Architect -> Lead)

Architecture decisions and system design for a phase.

```json
{
  "type": "architecture_design",
  "phase": "01",
  "artifact": "phases/01-company-hierarchy/architecture.toon",
  "decisions": [
    { "decision": "JWT RS256", "rationale": "Key rotation support", "alternatives": ["HS256"] }
  ],
  "risks": [
    { "risk": "Token theft via XSS", "impact": "high", "mitigation": "HttpOnly cookies" }
  ],
  "committed": true
}
```

## `senior_spec` (Senior -> Lead, after Design Review)

Notification that plan specs have been enriched.

```json
{
  "type": "senior_spec",
  "plan_id": "01-01",
  "tasks_enriched": 3,
  "concerns": ["Complex auth flow may need checkpoint at T2"],
  "committed": true
}
```

## `dev_progress` (Dev -> Senior)

Status update after completing a task.

```json
{
  "type": "dev_progress",
  "task": "01-01/T3",
  "plan_id": "01-01",
  "commit": "abc1234",
  "status": "complete | partial | failed",
  "concerns": ["Interface changed — downstream plans may need update"]
}
```

## `dev_blocker` (Dev -> Senior)

Escalation when blocked and cannot proceed.

```json
{
  "type": "dev_blocker",
  "task": "01-02/T1",
  "plan_id": "01-02",
  "blocker": "Dependency module from plan 01-01 not yet committed",
  "needs": "01-01 to complete first",
  "attempted": ["Checked git log for 01-01 commits — none found"]
}
```

## `code_review_changes` (Senior -> Dev)

Exact fix instructions when code review requests changes. Dev MUST follow these instructions precisely — no creative interpretation.

```json
{
  "type": "code_review_changes",
  "plan_id": "01-01",
  "cycle": 1,
  "changes": [
    {"f": "src/auth.ts", "ln": 42, "issue": "Missing error propagation", "fix": "Add throw after logging"},
    {"f": "src/auth.ts", "ln": 78, "issue": "Hardcoded timeout", "fix": "Use AUTH_TIMEOUT from config"}
  ],
  "must_fix": ["src/auth.ts:42", "src/auth.ts:78"],
  "rerun_tests": true
}
```

## `code_review_result` (Senior -> Lead)

Code review verdict after reviewing Dev's implementation.

```json
{
  "type": "code_review_result",
  "plan_id": "01-01",
  "result": "approve | changes_requested",
  "cycle": 1,
  "findings_count": 3,
  "critical": 0,
  "artifact": "phases/01-company-hierarchy/code-review.jsonl",
  "committed": true
}
```

## `qa_result` (QA Lead -> Lead)

Plan-level verification results.

```json
{
  "type": "qa_result",
  "tier": "quick | standard | deep",
  "result": "PASS | FAIL | PARTIAL",
  "checks": { "passed": 18, "failed": 2, "total": 20 },
  "failures": [
    {
      "check": "yolo-senior.md has Opus model",
      "expected": "model: opus in frontmatter",
      "actual": "model: inherit found",
      "evidence": "grep output from agents/yolo-senior.md"
    }
  ],
  "artifact": "phases/01-company-hierarchy/verification.jsonl",
  "committed": true
}
```

## `qa_code_result` (QA Code -> Lead)

Code-level verification results.

```json
{
  "type": "qa_code_result",
  "result": "PASS | FAIL | PARTIAL",
  "tests": { "passed": 42, "failed": 0, "skipped": 3 },
  "lint": { "errors": 0, "warnings": 2 },
  "findings_count": 5,
  "critical": 0,
  "artifact": "phases/01-company-hierarchy/qa-code.jsonl",
  "committed": true
}
```

## `security_audit` (Security -> Lead)

Security audit results.

```json
{
  "type": "security_audit",
  "result": "PASS | FAIL | WARN",
  "findings": 2,
  "critical": 0,
  "categories": ["secrets", "owasp", "deps", "config"],
  "artifact": "phases/01-company-hierarchy/security-audit.jsonl",
  "committed": true
}
```

## `scout_findings` (Scout -> Lead)

Research findings from a Scout investigating a specific topic.

```json
{
  "type": "scout_findings",
  "domain": "tech-stack | architecture | quality | concerns",
  "findings": [
    { "query": "JWT RS256 best practices", "finding": "...", "confidence": "high" }
  ],
  "artifact": "phases/01-company-hierarchy/research.jsonl",
  "committed": true
}
```

## `debugger_report` (Debugger -> Lead)

Investigation findings from competing hypotheses mode.

```json
{
  "type": "debugger_report",
  "hypothesis": "Race condition in session middleware",
  "evidence_for": ["Mutex not held during token refresh"],
  "evidence_against": ["Token TTL is 30min"],
  "confidence": "high | medium | low",
  "recommended_fix": "Add mutex lock around token refresh",
  "artifact": "phases/01-company-hierarchy/debug-report.jsonl"
}
```

## `escalation` (Any -> Up the chain)

Escalation when agent cannot resolve an issue within their authority.

```json
{
  "type": "escalation",
  "from": "dev | senior | lead",
  "to": "senior | lead | architect",
  "issue": "Design assumption invalid — auth flow needs state management",
  "evidence": ["Token refresh requires server-side session"],
  "recommendation": "Re-evaluate stateless design decision",
  "severity": "blocking | major | minor"
}
```

## `escalation_resolution` (Resolver -> Down the chain)

Resolution for a previously-escalated blocker. Flows DOWNWARD only (never upward). Sent by the agent that resolved the escalation (User via go.md, Owner, Architect, or Lead) back down through the chain to unblock the originating agent.

```json
{
  "type": "escalation_resolution",
  "original_escalation": "ESC-01-02-T3",
  "decision": "Use library A with caching layer",
  "rationale": "Library A has better long-term support and the caching layer addresses the performance concern",
  "action_items": [
    "Update spec for T3 to use library A import path",
    "Add caching middleware before the API call",
    "Update error handling to cover library A exceptions"
  ],
  "resolved_by": "user"
}
```

- `original_escalation`: References the `id` field from the escalation entry in .execution-state.json (e.g., "ESC-01-02-T3" = phase-plan-task)
- `decision`: The concrete choice made by the resolver
- `rationale`: Why this decision was made (for audit trail and downstream understanding)
- `action_items`: Array of specific instructions that Senior translates into Dev-actionable code_review_changes
- `resolved_by`: Who made the decision: "user" | "owner" | "architect" | "lead"
- Direction: Always downward (resolver to originator). Never sent upward.

## `agent_health_event` (Lead internal, when team_mode=teammate)

Lead-internal health tracking record. NOT sent via SendMessage -- logged locally for debugging and circuit breaker state transitions.

```json
{
  "type": "agent_health_event",
  "agent_id": "dev-1",
  "dept": "backend",
  "state": "start | idle | stop | disappeared",
  "timestamp": "2026-02-17T10:30:00Z",
  "prev_state": "idle",
  "timeout_triggered": false
}
```

## `circuit_breaker_state` (Lead internal, when team_mode=teammate)

Per-department circuit breaker state. Lead-internal -- used to decide fallback behavior. NOT sent via SendMessage.

```json
{
  "type": "circuit_breaker_state",
  "dept": "backend",
  "state": "closed | open | half-open",
  "opened_at": "2026-02-17T10:30:00Z",
  "failure_count": 2,
  "last_probe_at": "2026-02-17T10:35:00Z"
}
```

## `task_claim` (Dev -> Lead, when team_mode=teammate)

Dev claims a task from the shared task list. Sent after calling TaskUpdate to set status to claimed.

```json
{
  "type": "task_claim",
  "task_id": "T3",
  "plan_id": "03-01",
  "files": ["references/teammate-api-patterns.md"],
  "claimed_at": "2026-02-17T10:30:00Z"
}
```

Dev sends to Lead after calling TaskUpdate to claim a task. Lead adds task files to `claimed_files` set for file-overlap detection. In task mode, this message is not used (Dev works sequentially).

## `task_complete` (Dev -> Lead, when team_mode=teammate)

Dev reports task completion with commit hash. Sent after committing the task.

```json
{
  "type": "task_complete",
  "task_id": "T3",
  "plan_id": "03-01",
  "commit": "abc1234",
  "files_modified": ["references/teammate-api-patterns.md"],
  "status": "complete",
  "deviations": []
}
```

Dev sends to Lead after committing task. Lead removes files from `claimed_files`, checks if all tasks in plan are complete, and aggregates into summary.jsonl. Distinct from `dev_progress` (sent to Senior for visibility) -- `task_complete` is for Lead accounting only.

## `summary_aggregation` (Lead internal, when team_mode=teammate)

Lead constructs this internally from collected `task_complete` messages to write summary.jsonl.

```json
{
  "type": "summary_aggregation",
  "plan_id": "03-01",
  "tasks_completed": 7,
  "tasks_total": 7,
  "commit_hashes": ["abc1234", "def5678"],
  "files_modified": ["a.md", "b.md"],
  "deviations": [],
  "status": "complete"
}
```

Lead constructs this internally from collected `task_complete` messages. Used to write summary.jsonl. In task mode, Dev writes summary.jsonl directly and this schema is not used.

## `phase_progress` (Lead -> go.md, intra-phase progress)

Intra-phase progress update from Lead to orchestrator. Used by go.md to display progress during execution.

```json
{
  "type": "phase_progress",
  "department": "backend | frontend | uiux",
  "phase": "03",
  "step": "implementation",
  "plans_complete": 2,
  "plans_total": 4,
  "percent_complete": 50,
  "blockers": [],
  "eta": ""
}
```

Sent at each workflow step transition. go.md uses this for progress display and timeout calculation. In single-department mode, Lead sends this to go.md directly. In multi-department mode, go.md reads from .dept-status-{dept}.json (file-based) instead.

## `shutdown_request` (Lead -> Teammates, when team_mode=teammate)

Lead sends to all registered teammates to initiate graceful shutdown.

```json
{
  "type": "shutdown_request",
  "reason": "phase_complete | timeout | error",
  "deadline_seconds": 30
}
```

Sent at Step 10 (sign-off) or on unrecoverable error. See references/teammate-api-patterns.md ### Shutdown Protocol for the full protocol. See agents/yolo-lead.md ## Shutdown Protocol Enforcement for Lead-side algorithm.

## `shutdown_response` (Teammates -> Lead, when team_mode=teammate)

Teammate sends to Lead after receiving shutdown_request.

```json
{
  "type": "shutdown_response",
  "status": "clean | in_progress | error",
  "pending_work": ["task T3 implementation incomplete"],
  "artifacts_committed": true
}
```

See agents/yolo-dev.md ## Shutdown Response for teammate-side protocol.

---

## Cross-Department Schemas

Used when multiple departments are active (`departments.frontend` or `departments.uiux` = true).

## `design_handoff` (UX Lead -> Frontend Lead + Backend Lead)

UI/UX design artifacts ready for Frontend consumption. Produced after UI/UX 11-step workflow completes.

```json
{
  "type": "design_handoff",
  "phase": "01",
  "department": "uiux",
  "artifacts": {
    "design_tokens": "phases/01-auth/design-tokens.jsonl",
    "component_specs": "phases/01-auth/component-specs.jsonl",
    "user_flows": "phases/01-auth/user-flows.jsonl"
  },
  "ready_components": ["LoginForm", "AuthProvider", "TokenDisplay"],
  "deferred": ["PasswordReset"],
  "acceptance_criteria": ["All components pass A11y audit", "Design tokens cover all states"],
  "status": "complete"
}
```

## `api_contract` (Frontend Lead <-> Backend Lead)

API contract negotiation between Frontend and Backend. Bidirectional.

```json
{
  "type": "api_contract",
  "direction": "frontend_to_backend | backend_to_frontend",
  "endpoints": [
    {
      "method": "POST",
      "path": "/auth/login",
      "request": {"email": "string", "password": "string"},
      "response": {"token": "string", "user": "object"}
    }
  ],
  "status": "proposed | agreed | implemented"
}
```

## `department_result` (Department Lead -> Owner)

Department completion report sent to Owner for final sign-off.

```json
{
  "type": "department_result",
  "department": "backend | frontend | uiux",
  "phase": "01",
  "result": "PASS | PARTIAL | FAIL",
  "plans_completed": 3,
  "plans_total": 3,
  "qa_result": "PASS",
  "security_result": "PASS",
  "tdd_coverage": "red_green"
}
```

## `owner_review` (Owner -> Leads, after critique review)

Owner's critique review with department priorities and dispatch order.

```json
{
  "type": "owner_review",
  "phase": "01",
  "departments_needed": ["backend", "frontend", "uiux"],
  "dispatch_order": ["uiux", "frontend", "backend"],
  "priorities": ["UX must define design tokens before frontend starts"],
  "risks": ["Backend API changes may invalidate frontend component specs"]
}
```

## `owner_signoff` (Owner -> All Leads, final decision)

Owner's final phase decision after all departments complete.

```json
{
  "type": "owner_signoff",
  "phase": "01",
  "decision": "SHIP | HOLD",
  "departments_approved": ["backend", "frontend", "uiux"],
  "integration_qa": "PASS",
  "notes": ""
}
```
