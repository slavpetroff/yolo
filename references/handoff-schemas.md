# VBW Structured Handoff Schemas

JSON-structured SendMessage schemas with `type` discriminator. Receivers: `JSON.parse` content; fall back to plain text on parse failure.

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
      "check": "vbw-senior.md has Opus model",
      "expected": "model: opus in frontmatter",
      "actual": "model: inherit found",
      "evidence": "grep output from agents/vbw-senior.md"
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
