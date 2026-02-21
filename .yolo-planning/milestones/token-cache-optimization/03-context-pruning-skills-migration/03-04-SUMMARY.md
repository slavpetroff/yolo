---
phase: 3
plan: 04
title: Wire skills into compile-context and measure savings
status: complete
tasks_completed: 4
tasks_total: 4
deviations: 1
completed: 2026-02-21
---

# Summary: Wire Skills into Compile-Context and Measure Savings

## What Was Built

Wired the 3 migrated skills into the test suite and Rust verification, fixed 12 test regressions from the protocol migrations, and measured context window savings: ~13,402 tokens saved per conversation (804 from CLAUDE.md pruning + 12,598 from on-demand protocol loading). Confirmed CLAUDE.md at 40 lines (target < 45) and all skills load correctly.

## Accomplishments

### Task 1: Skill resolution audit
- Confirmed Rust `tier_context.rs` and MCP `compile_context` tool have NO skill resolution logic
- Skills are loaded on-demand via direct `Read` by the command (e.g., `commands/vibe.md` reads `skills/execute-protocol/SKILL.md` directly)
- The execute-protocol SKILL.md already documents this pattern at line 163 (skill bundling via CLI compile-context)
- No code changes needed -- this is a documentation/architecture gap, not a regression

### Task 2: Bats test regression fixes
- Updated 5 test files to point from `references/execute-protocol.md` to `skills/execute-protocol/SKILL.md`
- Updated `yolo-mcp-server/src/commands/verify_vibe.rs` to validate SKILL.md location (flipped `name:` frontmatter assertion since skills have `name:`)
- Updated `README.md` reference from `references/execute-protocol.md` to `skills/execute-protocol/SKILL.md`
- Net result: 12 previously-failing tests now pass (104 -> 116 passing), zero regressions introduced
- Remaining 569 failures are pre-existing (missing `scripts/*.sh` files migrated to Rust CLI)

### Task 3: Context window savings measurement

**CLAUDE.md reduction:**
- Before (pre-Phase 3): 133 lines, 5,254 chars (~1,314 tokens)
- After: 40 lines, 2,038 chars (~510 tokens)
- Reduction: 93 lines, 3,216 chars (~804 tokens saved per conversation)

**Protocol migration to on-demand loading:**
| Skill | Lines | Chars | Est. Tokens |
|-------|-------|-------|-------------|
| execute-protocol | 553 | 36,319 | ~9,080 |
| discussion-engine | 181 | 6,636 | ~1,659 |
| verification-protocol | 170 | 7,438 | ~1,860 |
| **Total moved to on-demand** | **904** | **50,393** | **~12,598** |

These 904 lines are no longer loaded in every conversation. They load only when Execute, Discuss, or Verify modes are activated.

**Total estimated savings:**
- CLAUDE.md per-conversation: ~804 tokens
- Protocol on-demand: ~12,598 tokens (not loaded unless needed)
- Combined: ~13,402 tokens saved per conversation that doesn't use all 3 protocols

### Task 4: Verification
- CLAUDE.md: 40 lines (target: < 45) -- PASS
- All 3 skills have complete SKILL.md content -- PASS
- All 3 redirect stubs in references/ point to correct skill paths -- PASS
- Commands (vibe.md, discuss.md) reference skills/ locations -- PASS
- Rust verify_vibe.rs validates new skill location -- PASS

## Task Commits

| Task | Commit | Files |
|------|--------|-------|
| T2 | test(03-04): update test paths and verify_vibe.rs for skill migration | 7 files |

## Files Modified
- `tests/role-isolation.bats` (path update)
- `tests/two-phase-completion.bats` (path + pattern update)
- `tests/phase0-bugfix-verify.bats` (path update)
- `tests/token-budgets.bats` (path + pattern update)
- `tests/discovered-issues-surfacing.bats` (15 path updates)
- `yolo-mcp-server/src/commands/verify_vibe.rs` (skill path + assertion flip)
- `README.md` (reference path update)

## Deviations
- Task 1 required no code changes (skill resolution is by direct Read, not compile-context bundling) -- documented as architecture note rather than code fix
- Two test pattern updates: `two-phase-complete.sh` -> `two-phase-complete` and `metrics-report.sh` -> `metrics-report` (SKILL.md uses CLI names without .sh suffix)
