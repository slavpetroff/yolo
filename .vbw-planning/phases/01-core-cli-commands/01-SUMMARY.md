---
phase: 1
plan: 01
title: "Migrate resolve-model + resolve-turns to Rust CLI"
status: complete
---

## What Was Built

Two Rust CLI subcommands that replace the bash scripts `resolve-agent-model.sh` and `resolve-agent-max-turns.sh`:

- `yolo resolve-model <agent> <config-path> <profiles-path>` -- resolves the model tier (opus/sonnet/haiku) for an agent based on the active model profile and per-agent overrides. Includes session-level mtime caching.
- `yolo resolve-turns <agent> <config-path> [effort]` -- resolves the max turn budget for an agent with effort-based multipliers, object/scalar config modes, legacy effort aliases, and false=unlimited support.

Both commands are registered in the CLI router and produce identical output to the original bash scripts.

## Tasks

| # | Title | Commit |
|---|-------|--------|
| 1 | Implement resolve-model command | c4ed65d |
| 2 | Implement resolve-turns command | f80f57c |
| 3 | Register both in CLI router + mod.rs | 05b2d8b |
| 4 | Add integration tests | 72de9cd |

## Files Modified

- `yolo-mcp-server/src/commands/resolve_model.rs` (new, 310 lines)
- `yolo-mcp-server/src/commands/resolve_turns.rs` (new, 490 lines)
- `yolo-mcp-server/src/commands/mod.rs` (added 2 module declarations)
- `yolo-mcp-server/src/cli/router.rs` (added 2 imports + 2 match arms)

## Test Results

- 34 tests total (12 resolve-model + 22 resolve-turns)
- 0 failures across both binary targets

## Deviations

- Added path-hash to model cache key (`/tmp/yolo-model-{agent}-{mtime}-{hash}`) to prevent test isolation issues where concurrent temp dirs with same mtime would collide. Production behavior unchanged since real config paths are stable.
