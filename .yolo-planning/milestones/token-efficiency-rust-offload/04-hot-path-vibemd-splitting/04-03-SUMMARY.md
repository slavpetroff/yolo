---
phase: 4
plan: 3
title: "Enable v2_token_budgets by default + session-start step-level reporting"
status: complete
commits: 2
deviations: 0
---

# Summary: Token Budgets Default + Session-Start Steps

## What Was Built
Enabled v2_token_budgets=true by default for new projects. Enhanced session-start to report per-step status (ok/warn/skip/error) with timing instead of flat string arrays.

## Files Modified
- `config/defaults.json` — v2_token_budgets changed from false to true
- `tests/config-migration.bats` — 2 new tests for migration behavior
- `yolo-mcp-server/src/commands/session_start.rs` — StepResult struct, per-step timing, status mapping

## Commits
- `742370f` feat(config): enable v2_token_budgets by default
- `7402a4b` feat(session-start): add per-step status and timing to step reporting

## Metrics
- New projects get token budget enforcement out of the box
- 15 init steps now report individual status and timing
