---
phase: 4
plan: 1
title: "Split vibe.md into router + mode-specific skill files"
status: complete
commits: 4
deviations: 0
---

# Summary: Split vibe.md

## What Was Built
Split the monolithic vibe.md (427 lines, ~7,220 tokens) into a router (110 lines, ~1,190 tokens) plus 6 mode-specific skill files in skills/vibe-modes/. Each /yolo:vibe invocation now loads only the router + active mode (~2,060 tokens) instead of all 11 modes.

## Files Modified
- `commands/vibe.md` — rewritten as router-only (427 -> 110 lines)
- `skills/vibe-modes/bootstrap.md` — new Bootstrap mode
- `skills/vibe-modes/scope.md` — new Scope mode
- `skills/vibe-modes/plan.md` — new Plan mode
- `skills/vibe-modes/phase-mutation.md` — new Add/Insert/Remove Phase modes
- `skills/vibe-modes/archive.md` — new Archive mode
- `skills/vibe-modes/assumptions.md` — new Assumptions mode
- `tests/vibe-mode-split.bats` — 9 new tests

## Commits
- `46bd0b3` feat(vibe-modes): create 6 mode skill files for vibe.md splitting
- `eb4391e` refactor(vibe): rewrite vibe.md as router-only (427 -> 109 lines)
- `169b49b` fix(vibe): restore subagent isolation note for Discuss mode in router
- `436bdef` test(vibe-modes): add vibe-mode-split.bats with 9 tests

## Metrics
- 71% token reduction per invocation (7,220 -> ~2,060 tokens)
