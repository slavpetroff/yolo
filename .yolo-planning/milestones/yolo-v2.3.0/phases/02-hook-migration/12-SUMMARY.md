---
phase: 2
plan: 12
status: complete
commits: 5
tests_added: 43
tests_passing: 43
---

## Summary

Migrated all 4 routing scripts (assess-plan-risk.sh, resolve-gate-policy.sh, smart-route.sh, route-monorepo.sh) to native Rust modules. Zero shell-outs -- all logic is pure Rust with serde_json for output.

## Commits

1. `feat(commands): implement assess_plan_risk module for plan risk classification` -- 9 tests
2. `feat(commands): implement resolve_gate_policy module for validation gate matrix` -- 12 tests
3. `feat(commands): implement smart_route module for agent routing by effort` -- 13 tests
4. `feat(commands): implement route_monorepo module for monorepo-aware routing` -- 9 tests
5. `feat(commands): register assess-risk, gate-policy, smart-route, route-monorepo CLI commands` -- wiring

## Files Created

- `yolo-mcp-server/src/commands/assess_plan_risk.rs` (301 lines)
- `yolo-mcp-server/src/commands/resolve_gate_policy.rs` (199 lines)
- `yolo-mcp-server/src/commands/smart_route.rs` (185 lines)
- `yolo-mcp-server/src/commands/route_monorepo.rs` (309 lines)

## Files Modified

- `yolo-mcp-server/src/commands/mod.rs` -- added 4 module declarations
- `yolo-mcp-server/src/cli/router.rs` -- added 4 CLI command routes

## CLI Commands

| Command | Description |
|---------|-------------|
| `yolo assess-risk <plan-path>` | Classify plan risk as low/medium/high |
| `yolo gate-policy <effort> <risk> <autonomy>` | Resolve gate policy from matrix |
| `yolo smart-route <agent> <effort>` | Route agent include/skip by effort |
| `yolo route-monorepo <phase-dir>` | Detect monorepo packages for phase |

## Deviations

None. All acceptance criteria met. No shell-outs, no Command::new("bash"), no jq, no awk.
