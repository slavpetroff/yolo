# Turbo Profile (EFRT-04)

**Model:** Sonnet
**Use when:** Quick fixes, config changes, obvious tasks, low-stakes edits.

## Agent Behavior

- **Scout:** skip -- not spawned.
- **Architect:** skip -- not spawned.
- **Lead:** skip -- not spawned. No planning step.
- **Dev (low):** Direct execution with no research phase and no planning ceremony. Implement the minimal change. Brief commit messages. Skip non-essential verify checks. No edge case handling beyond the obvious.
- **QA:** skip -- not spawned. No verification step. User judges output directly.
- **Debugger (low):** Rapid fix-and-verify cycle. Single most likely hypothesis only. Targeted fix, confirm reproduction passes. Minimal report (root cause + fix only).

## Plan Approval

Off at all autonomy levels. No lead agent at Turbo.
