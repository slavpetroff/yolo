# ADR-002: JSONL with Abbreviated Keys for Agent Artifacts

**Status:** Accepted
**Date:** 2026-02-13
**Deciders:** User + Architect

## Context

Agent artifacts (plans, summaries, verification results) were stored as Markdown with YAML frontmatter. This format was human-readable but token-expensive (85-93% overhead vs data content) and fragile to parse with grep/sed.

## Decision

Use JSONL with abbreviated keys for all agent-facing artifacts. Key dictionary in artifact-formats.md maps abbreviations (p=phase, n=plan, t=title, etc.). Parse with jq only, never grep/sed on JSON. User-facing files remain Markdown.

## Consequences

**Positive:**
- 85-93% token savings on artifact reads
- jq parsing is reliable and scriptable
- JSONL is append-friendly (decisions.jsonl, research.jsonl)
- Zero new dependencies (jq already required)

**Negative:**
- Not human-readable without jq
- Backward compatibility needed for legacy MD files
- Abbreviated keys require lookup table

**Neutral:**
- All scripts check both .plan.jsonl and -PLAN.md for transition period
