---
phase: 1
plan: 01
title: "Migrate resolve-agent-model.sh and resolve-agent-max-turns.sh to Rust CLI"
status: complete
---

## What Was Built

Native Rust implementations of `resolve-model` and `resolve-turns` CLI commands, replacing the bash scripts `resolve-agent-model.sh` and `resolve-agent-max-turns.sh`. Both commands parse config.json and model-profiles.json to resolve agent model assignments and turn budgets with full effort normalization support.

## Tasks

| # | Task | Commit |
|---|------|--------|
| 1 | Implement resolve-model command | `c4ed65d` |
| 2 | Implement resolve-turns command | `f80f57c` |
| 3 | Register both commands in CLI router | `05b2d8b` |
| 4 | Add integration tests | `72de9cd` |

## Files Created

- `yolo-mcp-server/src/commands/resolve_model.rs` — Model resolution with profile lookup, per-agent overrides, mtime caching
- `yolo-mcp-server/src/commands/resolve_turns.rs` — Turn budget resolution with effort multipliers, object/scalar modes, false=unlimited

## Deviations

None.
