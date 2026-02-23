# Shipped: Quality Gate Feedback Loops

**Version:** v2.7.0
**Shipped:** 2026-02-23
**Phases:** 4
**Plans:** 8
**Tasks:** 35
**Commits:** 29

## Summary

Added configurable feedback loops to both quality gates. When the Reviewer rejects a plan,
the Architect automatically revises it and the Reviewer re-reviews — looping until approved
or the hard cap (review_max_cycles, default 3) is hit. When QA checks fail, dev-fixable
failures trigger a scoped Dev remediation subagent that fixes and re-runs only the failed checks.
Both loops are cache-efficient — review loop agents share the "planning" Tier 2 cache, QA loop
agents share "execution" Tier 2. Loops use delta-findings passing between iterations for
token efficiency.

## Phase Breakdown

| Phase | Title | Plans | Tasks | Commits |
|-------|-------|-------|-------|---------|
| 1 | Loop Config & Structured Feedback Infrastructure | 2 | 10 | 8 |
| 2 | Review Feedback Loop (Architect ↔ Reviewer) | 2 | 9 | 8 |
| 3 | QA Feedback Loop (Dev ↔ QA) | 2 | 8 | 7 |
| 4 | Testing & Release | 2 | 8 | 6 |

## Key Deliverables

- `review_max_cycles` / `qa_max_cycles` config keys (default 3, range 1-5)
- `review_plan.rs` enhanced: `suggested_fix` + `auto_fixable` on all findings
- 5 QA commands enhanced: `fixable_by` classification (dev/architect/manual)
- 6 loop event types: review_loop_start/cycle/end, qa_loop_start/cycle/end
- Execute-protocol Step 2b: full review feedback loop with delta-findings
- Execute-protocol Step 3d: full QA remediation loop with fixable_by routing
- Architect agent: Revision Protocol for plan revision from findings
- Reviewer agent: Delta-Aware Review + Escalation Protocol
- QA agent: Remediation Classification + Feedback Loop Behavior
- 12 new bats tests covering loop infrastructure
- README, CHANGELOG updated; version bumped to v2.7.0
