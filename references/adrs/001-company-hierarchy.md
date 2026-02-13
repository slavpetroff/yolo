# ADR-001: Company-Grade Agent Hierarchy

**Status:** Accepted
**Date:** 2026-02-13
**Deciders:** User + Architect

## Context

VBW originally had 6 flat agents (Lead, Dev, QA, Scout, Debugger, Architect). No separation of concerns between planning and implementation, no code review step, no security audit. Quality depended on a single QA pass.

## Decision

Adopt a company hierarchy mirroring real engineering orgs: Architect -> Lead -> Senior -> Dev, with QA Lead, QA Code, Security, Scout, and Debugger as specialized roles. 8-step workflow per phase: Architecture -> Plan -> Design Review -> Implement -> Code Review -> QA -> Security -> Sign-off.

## Consequences

**Positive:**
- Each agent has a clear, bounded responsibility
- Senior enriches specs before Dev touches code (fewer errors)
- Code review catches issues before QA (cheaper fixes)
- Security audit as explicit step (not afterthought)

**Negative:**
- More agent spawns per phase (higher token cost)
- Longer execution time for simple changes
- Turbo mode must bypass most steps to stay fast

**Neutral:**
- Effort profiles control which steps are active
