# Shipped: Agent Routing & Release Automation

**Date:** 2026-02-23
**Version:** v2.8.0
**Tag:** milestone/agent-routing-release-automation

## Summary

Fixed two workflow issues: (1) execute-protocol now spawns specialized agents via `subagent_type` instead of generic general-purpose agents; (2) archive flow includes consolidated release step (Step 8b) for automatic version bump, changelog finalization, and tagging.

## Metrics

| Metric | Value |
|--------|-------|
| Phases | 3 |
| Plans | 5 |
| Tasks | 15 |
| Commits | 12 |
| Deviations | 0 |

## Phases

1. **Specialized Agent Routing** — Fixed 4 spawn points (3 in execute-protocol, 1 in plan.md) with subagent_type routing. Added mapping table.
2. **Archive Release Automation** — Added Step 8b to archive.md with version bump, changelog finalization, release commit, version tag, and push gating.
3. **Testing & Release** — 11 new bats tests, README/CHANGELOG updates, version bump to v2.8.0. 722 total tests, 0 regressions.
