---
phase: {phase-id}
plan: {plan-number}
tier: {quick|standard|deep}
status: {pass|fail|partial}
verified_by: {agent|human}
verified_at: {YYYY-MM-DD}
checks_passed: {N}
checks_total: {N}
failures: ["{failure-description}"]
---

## Must-Haves

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | {invariant} | {pass/fail} | {how-verified} |

## Artifacts

| Artifact | Contains | Status |
|----------|----------|--------|
| {file-path} | {required-content} | {pass/fail} |

## Result

**Status:** {PASS|FAIL|PARTIAL}
**Summary:** {one-line-result}
