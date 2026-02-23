---
phase: 1
plan: 04
title: "Clippy Fixes — Commands M-Z + Hooks + MCP + Telemetry"
wave: 1
depends_on: []
must_haves:
  - REQ-01
  - REQ-02
---

# Plan 04: Clippy Fixes — Commands M-Z + Hooks + MCP + Telemetry

Fix all remaining clippy warnings across commands M-Z, all hook files (except those in Plan 01), MCP modules, and telemetry. ~164 warnings across 36 files.

## Files Modified (36 — disjoint from Plans 01/02/03)

**Commands (24):** metrics_report.rs, migrate_orphaned_state.rs, parse_frontmatter.rs,
phase_detect.rs, planning_git.rs, prune_completed.rs, recover_state.rs,
resolve_gate_policy.rs, resolve_plugin_root.rs, resolve_turns.rs, review_plan.rs,
rollout_stage.rs, route_monorepo.rs, smart_route.rs, snapshot_resume.rs,
statusline.rs, suggest_next.rs, tier_context.rs, tmux_watchdog.rs,
token_budget.rs, token_economics_report.rs, validate_plan.rs,
validate_requirements.rs, verify_plan_completion.rs

**Hooks (9):** agent_start.rs, agent_stop.rs, agent_pid_tracker.rs, post_compact.rs,
prompt_preflight.rs, security_filter.rs, test_validation.rs, validate_contract.rs,
validate_message.rs

**MCP (2):** retry.rs, tools.rs

**Telemetry (1):** db.rs

## Task 1: Fix clippy warnings in highest-count files (statusline, suggest_next, phase_detect, validate_plan)

**Description:** These four files have 10-21 warnings each (mostly collapsible if-let chains). Collapse nested `if let` + `if` into combined expressions. Apply strip_prefix, push_str, to_vec, and other clippy suggestions.

**Files:**
- `src/commands/statusline.rs` (21 warnings)
- `src/commands/suggest_next.rs` (17 warnings)
- `src/commands/phase_detect.rs` (12 warnings)
- `src/commands/validate_plan.rs` (10 warnings)

**Commit:** `fix(commands): resolve clippy warnings in statusline, suggest_next, phase_detect, validate_plan`
**Verify:** `cargo clippy 2>&1 | grep -cE "(statusline|suggest_next|phase_detect|validate_plan)\.rs"` returns 0

## Task 2: Fix clippy warnings in medium-count command files

**Description:** Collapse nested ifs and apply clippy fixes in 4-8 warning files.

**Files:**
- `src/commands/metrics_report.rs` (8 warnings)
- `src/commands/token_economics_report.rs` (6 warnings)
- `src/commands/token_budget.rs` (6 warnings)
- `src/commands/validate_requirements.rs` (5 warnings)
- `src/commands/rollout_stage.rs` (5 warnings)
- `src/commands/parse_frontmatter.rs` (5 warnings)

**Commit:** `fix(commands): resolve clippy warnings in metrics_report, token_economics_report, token_budget, validate_requirements, rollout_stage, parse_frontmatter`
**Verify:** `cargo clippy 2>&1 | grep -cE "(metrics_report|token_economics_report|token_budget|validate_requirements|rollout_stage|parse_frontmatter)\.rs"` returns 0

## Task 3: Fix clippy warnings in low-count command files (M-Z)

**Description:** Fix remaining 1-4 warning command files.

**Files:**
- `src/commands/review_plan.rs` (4 warnings)
- `src/commands/planning_git.rs` (4 warnings)
- `src/commands/migrate_orphaned_state.rs` (4 warnings)
- `src/commands/tier_context.rs` (3 warnings)
- `src/commands/snapshot_resume.rs` (3 warnings)
- `src/commands/resolve_turns.rs` (3 warnings)
- `src/commands/verify_plan_completion.rs` (2 warnings)
- `src/commands/tmux_watchdog.rs` (2 warnings)
- `src/commands/smart_route.rs` (2 warnings)
- `src/commands/recover_state.rs` (2 warnings)
- `src/commands/route_monorepo.rs` (1 warning)
- `src/commands/resolve_plugin_root.rs` (1 warning)
- `src/commands/resolve_gate_policy.rs` (1 warning)
- `src/commands/prune_completed.rs` (1 warning)

**Commit:** `fix(commands): resolve clippy warnings in remaining M-Z command files`
**Verify:** `cargo clippy 2>&1 | grep -c "src/commands/"` returns 0 (combined with other plans)

## Task 4: Fix clippy warnings in all hook files

**Description:** Fix collapsible ifs and other clippy warnings across 9 hook files. Includes validate_message (6), agent_start (6), agent_stop (4), prompt_preflight (4), validate_contract (3), post_compact (2), and 3 single-warning files.

**Files:**
- `src/hooks/validate_message.rs` (6 warnings)
- `src/hooks/agent_start.rs` (6 warnings)
- `src/hooks/agent_stop.rs` (4 warnings)
- `src/hooks/prompt_preflight.rs` (4 warnings)
- `src/hooks/validate_contract.rs` (3 warnings)
- `src/hooks/post_compact.rs` (2 warnings)
- `src/hooks/test_validation.rs` (1 warning)
- `src/hooks/security_filter.rs` (1 warning)
- `src/hooks/agent_pid_tracker.rs` (1 warning)

**Commit:** `fix(hooks): resolve all clippy warnings across hook modules`
**Verify:** `cargo clippy 2>&1 | grep -c "src/hooks/"` returns 0

## Task 5: Fix clippy warnings in MCP + Telemetry + add Default impls

**Description:**
- `mcp/tools.rs` (3 warnings) — includes adding `Default` impl for `ToolState`
- `mcp/retry.rs` (2 warnings) — includes adding `Default` impl for `CircuitBreaker`
- `telemetry/db.rs` (3 warnings) — excessive fn args (3x functions with 8-9 params). Refactor into builder or struct params.

**Files:**
- `src/mcp/tools.rs`
- `src/mcp/retry.rs`
- `src/telemetry/db.rs`

**Commit:** `fix(mcp,telemetry): resolve clippy warnings, add Default impls, refactor excessive args`
**Verify:** `cargo clippy 2>&1 | grep -cE "(mcp/|telemetry/)"` returns 0
