# ADR-004: Gaps-Based Remediation Loop

**Status:** Accepted
**Date:** 2026-02-13
**Deciders:** User + Architect

## Context

QA failures require Dev to fix issues, but the handoff was unstructured. QA would report findings in prose, Dev would interpret them. No tracking of which issues were fixed vs still open.

## Decision

QA Code writes gaps.jsonl on PARTIAL/FAIL with structured gap entries (id, severity, description, expected, actual, status). Dev reads gaps.jsonl before normal tasks, fixes open gaps, marks them fixed with commit hash. Max 2 remediation cycles before escalation (2x -> Senior, 3x -> Architect).

## Consequences

**Positive:**
- Structured handoff: Dev knows exactly what to fix
- Trackable: each gap has a status and resolution
- Bounded: max 2 cycles prevents infinite loops
- Escalation path prevents design-level bugs from being patched repeatedly

**Negative:**
- QA Code needs Write tool access (was previously read-only)
- More complex orchestration in execute-protocol

**Neutral:**
- gaps.jsonl is committed with other artifacts for crash resilience
