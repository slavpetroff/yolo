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

## `qa_code_result` (QA --mode code -> Lead)

Code-level verification results. Sent by QA agent in code mode (formerly qa-code agent).

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

## `research_request` (Any agent -> Orchestrator)

On-demand research request emitted by any agent when blocked by missing external information. Orchestrator routes to Scout and manages blocking vs informational dispatch.

```json
{
  "type": "research_request",
  "from": "dev",
  "task": "01-02/T3",
  "plan_id": "01-02",
  "query": "JWT RS256 key rotation best practices for multi-tenant systems",
  "context": "Spec requires key rotation but no pattern guidance in codebase or architecture",
  "request_type": "blocking",
  "priority": "high"
}
```

| Field | Type | Values |
|-------|------|--------|
| `type` | string | "research_request" |
| `from` | string | Agent role (e.g., "dev", "senior", "tester", "lead", "architect") |
| `task` | string | Task reference (e.g., "01-02/T3") |
| `plan_id` | string | Plan identifier (e.g., "01-02") |
| `query` | string | Research question |
| `context` | string | Why the information is needed |
| `request_type` | string | "blocking" (agent cannot proceed) or "informational" (agent continues with assumption) |
| `priority` | string | "high", "medium", or "low" |

Note: Orchestrator writes research.jsonl from Scout findings. Scout never writes directly. Blocking requests pause requesting agent until response delivered. Informational requests are async -- agent continues, findings appended when available.

## `research_response` (Orchestrator -> Requesting agent)

Response delivered to the agent that emitted a research_request. Contains Scout findings routed through the orchestrator.

```json
{
  "type": "research_response",
  "request_from": "dev",
  "query": "JWT RS256 key rotation best practices for multi-tenant systems",
  "findings": [
    { "q": "JWT RS256 key rotation", "src": "web", "finding": "JWKS endpoint with kid header for seamless rotation", "conf": "high" }
  ],
  "request_type": "blocking",
  "resolved_at": "2026-02-18T14:30:00Z"
}
```

| Field | Type | Values |
|-------|------|--------|
| `type` | string | "research_response" |
| `request_from` | string | Agent role that requested the research |
| `query` | string | Original research question (for correlation) |
| `findings` | object[] | Array of `{q, src, finding, conf}` from Scout |
| `request_type` | string | "blocking" or "informational" (echoed from request) |
| `resolved_at` | string | ISO 8601 timestamp when response was produced |

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

## `escalation_timeout_warning` (Lead -> Architect/Owner)

Sent by Lead when an escalation has been pending longer than the configured `escalation.timeout_seconds` (default 300s). Triggers auto-escalation to the next level in the chain.

```json
{
  "type": "escalation_timeout_warning",
  "original_escalation": "ESC-01-02-T3",
  "elapsed_seconds": 312,
  "current_level": "lead",
  "agent_blocked": "dev-1 (task 01-02/T3)",
  "recommended_action": "Escalate to Architect for design-level decision on library choice"
}
```

- `original_escalation`: References the escalation id in .execution-state.json
- `elapsed_seconds`: Time since `last_escalated_at` in the escalation entry
- `current_level`: The level where escalation is currently stalled ("senior" | "lead" | "architect")
- `agent_blocked`: Human-readable description of who is waiting (agent name + task ref)
- `recommended_action`: What the timeout handler recommends as next step

Note: This schema is produced by check-escalation-timeout.sh (Plan 05-04) and consumed by the orchestrator for auto-escalation routing. The escalation entry's `level` field is updated when auto-escalation fires.

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

## `po_qa_verdict` (PO -> Orchestrator)

PO's post-integration Q&A verdict after validating department results against scope. Produced by PO Mode 4 after reviewing `integration-gate-result.jsonl` and all `department_result` schemas.

```json
{
  "type": "po_qa_verdict",
  "verdict": "approve | patch | major",
  "findings": [
    { "check": "auth-flow-integration", "result": "fail", "dept": "backend", "detail": "Token refresh not wired to frontend" }
  ],
  "target_dept": "backend",
  "re_scope_items": [],
  "scope_confidence": 0.92
}
```

| Field | Type | Values |
|-------|------|--------|
| `type` | string | "po_qa_verdict" |
| `verdict` | string | "approve" (all pass) \| "patch" (minor gaps) \| "major" (vision misalignment) |
| `findings` | object[] | Array of `{check, result, dept, detail}` for failing checks |
| `target_dept` | string | Department responsible for fixes (patch only; empty string for approve/major) |
| `re_scope_items` | string[] | Items requiring re-scoping (major only; empty for approve/patch) |
| `scope_confidence` | float | 0-1 confidence in scope coverage |

Orchestrator routes based on `verdict`: approve -> `user_presentation` for delivery, patch -> `patch_request` to dept Senior, major -> `major_rejection` to PO Mode 0.

## `patch_request` (PO -> Orchestrator -> Dept Senior)

Targeted fix request when PO Q&A verdict is `patch`. Routes to the responsible department's Senior for scoped remediation. Maximum 2 tasks, <20% token budget of a full re-plan.

```json
{
  "type": "patch_request",
  "target_dept": "backend",
  "failing_checks": ["auth-token-refresh", "session-validation"],
  "fix_instructions": "Wire token refresh endpoint to frontend auth provider. Add session validation middleware before protected routes.",
  "scope_ref": "scope-document section 2.3 (Authentication Flow)",
  "max_tasks": 2
}
```

| Field | Type | Values |
|-------|------|--------|
| `type` | string | "patch_request" |
| `target_dept` | string | Department whose Senior receives the fix request |
| `failing_checks` | string[] | Integration gate check names that failed |
| `fix_instructions` | string | PO's description of what needs to be fixed (product-level, not code-level) |
| `scope_ref` | string | Reference to the scope document section covering the failing area |
| `max_tasks` | number | Maximum tasks allowed for the patch (hard cap: 2) |

Senior re-specs the fix, Dev implements, then re-run integration gate for the specific failing checks only. If patch fails, escalate to Major path.

## `major_rejection` (PO -> Orchestrator -> Questionary)

Re-scope request when PO Q&A verdict is `major`. Triggers PO-Questionary loop (Mode 0) with re-scope context. Only affected departments re-run the full pipeline.

```json
{
  "type": "major_rejection",
  "re_scope_items": ["Authentication must support SSO — original scope only covered email/password", "User onboarding flow missing entirely"],
  "affected_depts": ["backend", "frontend"],
  "rationale": "Delivered auth flow covers only basic email/password. Product vision requires SSO support as P0. Onboarding flow was in scope but no department addressed it.",
  "original_scope_ref": "scope-document v2 sections 1.1, 3.2"
}
```

| Field | Type | Values |
|-------|------|--------|
| `type` | string | "major_rejection" |
| `re_scope_items` | string[] | Scope items that need re-definition or were missed |
| `affected_depts` | string[] | Departments that must re-run the full pipeline after re-scoping |
| `rationale` | string | PO's explanation of why the vision misalignment requires re-scoping |
| `original_scope_ref` | string | Reference to original scope document sections for traceability |

Orchestrator routes to PO Mode 0 with `re_scope_items` as input. After re-scoping, only `affected_depts` re-enter the full 11-step workflow.

## `feedback_response` (User -> Orchestrator -> PO)

User feedback routed to PO after delivery presentation. Orchestrator captures user response to `user_presentation` and wraps it for PO consumption.

```json
{
  "type": "feedback_response",
  "response": "approve | request_changes | reject",
  "comments": "SSO integration looks good but the error states need polish",
  "change_requests": ["Improve error messages for SSO timeout", "Add loading state during token refresh"],
  "scope_ref": "scope-document v2"
}
```

| Field | Type | Values |
|-------|------|--------|
| `type` | string | "feedback_response" |
| `response` | string | "approve" (ship it) \| "request_changes" (minor adjustments) \| "reject" (fundamental issues) |
| `comments` | string | User's free-text feedback |
| `change_requests` | string[] | Specific changes requested (empty for approve) |
| `scope_ref` | string | Scope document version for context |

PO processes `feedback_response` to determine next action: approve -> finalize delivery, request_changes -> produce `patch_request`, reject -> produce `major_rejection`.

## Cross-Phase Handoff Artifacts

### `phase-handoff.jsonl` (Phase Transition Data)

**Location:** `.yolo-planning/phases/{NN}-{slug}/phase-handoff.jsonl`

Written by the orchestrator at phase completion. Captures key outputs, decisions, and open items for the next phase to consume. Enables resumable phase transitions.

```json
{
  "type": "phase_handoff",
  "from_phase": "03",
  "to_phase": "04",
  "dt": "2026-02-19T08:00:00Z",
  "decisions": ["Use JWT RS256 for auth", "PostgreSQL over MongoDB"],
  "open_items": ["SSO integration deferred to Phase 5"],
  "artifacts": ["architecture.toon", "03-01.summary.jsonl", "03-02.summary.jsonl"],
  "research_refs": ["research-archive.jsonl entries 12-18"],
  "escalations_resolved": 1,
  "escalations_pending": 0
}
```

| Key | Full Name | Type |
|-----|-----------|------|
| `type` | handoff type | "phase_handoff" |
| `from_phase` | source phase | string (e.g. "03") |
| `to_phase` | target phase | string (e.g. "04") |
| `dt` | timestamp | string (ISO 8601) |
| `decisions` | key decisions carried forward | string[] |
| `open_items` | deferred/unresolved items | string[] |
| `artifacts` | produced artifact filenames | string[] |
| `research_refs` | research archive references | string[] |
| `escalations_resolved` | resolved escalation count | number |
| `escalations_pending` | pending escalation count | number |

The orchestrator writes this after all plans in a phase are complete and before advancing to the next phase. The next phase's Critic (Step 1) and Architect (Step 3) receive `phase-handoff.jsonl` from the previous phase as additional context.

### `dept-handoff.jsonl` (Cross-Department Coordination)

**Location:** `.yolo-planning/phases/{NN}-{slug}/dept-handoff.jsonl`

Written by department Leads during multi-department execution. Captures artifacts and contracts produced by one department that another department depends on. Replaces implicit file-based coordination with explicit structured handoffs.

```json
{
  "type": "dept_handoff",
  "from_dept": "uiux",
  "to_dept": "frontend",
  "dt": "2026-02-19T09:00:00Z",
  "artifacts": ["design-tokens.jsonl", "component-specs.jsonl", "user-flows.jsonl"],
  "contracts": [{"name": "Button component", "spec": "component-specs.jsonl#btn-01"}],
  "blockers": [],
  "notes": "Design tokens finalized, all component specs reviewed by UX Senior"
}
```

| Key | Full Name | Type |
|-----|-----------|------|
| `type` | handoff type | "dept_handoff" |
| `from_dept` | source department | "backend"\|"frontend"\|"uiux" |
| `to_dept` | target department | "backend"\|"frontend"\|"uiux" |
| `dt` | timestamp | string (ISO 8601) |
| `artifacts` | shared artifact filenames | string[] |
| `contracts` | API/component contracts | object[] `{name, spec}` |
| `blockers` | unresolved blockers | string[] |
| `notes` | Lead commentary | string |

**Flow:** UX Lead writes `dept-handoff.jsonl` after UX workflow completes (design-handoff gate). FE Lead and BE Lead receive this as input. Integration Gate Agent validates that all `contracts` entries are satisfied by receiving departments. If `blockers` is non-empty, Integration Gate flags as FAIL.
