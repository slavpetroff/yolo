---
phase: 1
plan: 03
title: "Clippy Fixes — Commands A-L"
wave: 1
depends_on: []
must_haves:
  - REQ-01
---

# Plan 03: Clippy Fixes — Commands A-L

Fix all clippy warnings (collapsible if, strip_prefix, push_str, to_vec, etc.) in command files alphabetically A through L. ~106 warnings across 24 files.

## Files Modified (24 — disjoint from Plans 01/02/04)
All in `src/commands/`:
assess_plan_risk.rs, atomic_io.rs, auto_repair.rs, bump_version.rs,
cache_context.rs, check_regression.rs, clean_stale_teams.rs, collect_metrics.rs,
compile_progress.rs, compile_rolling_summary.rs, contract_revision.rs, delta_files.rs,
detect_stack.rs, diff_against_plan.rs, doctor_cleanup.rs, generate_contract.rs,
generate_gsd_index.rs, help_output.rs, infer_gsd_summary.rs, infer_project_context.rs,
install_hooks.rs, lease_lock.rs, lock_lite.rs, log_event.rs

## Task 1: Fix clippy warnings in high-count files (detect_stack, infer_project_context, lease_lock)

**Description:** These three files have 9-10 warnings each (mostly collapsible if-let chains). Collapse nested `if let` + `if` into single `if let ... &&` expressions. Also apply strip_prefix, push_str, to_vec fixes as flagged.

**Files:**
- `src/commands/detect_stack.rs` (9 warnings)
- `src/commands/infer_project_context.rs` (10 warnings)
- `src/commands/lease_lock.rs` (10 warnings)

**Commit:** `fix(commands): resolve clippy warnings in detect_stack, infer_project_context, lease_lock`
**Verify:** `cargo clippy 2>&1 | grep -cE "(detect_stack|infer_project_context|lease_lock)\.rs"` returns 0

## Task 2: Fix clippy warnings in doctor_cleanup, lock_lite, delta_files, diff_against_plan

**Description:** Collapse nested if statements, apply strip_prefix and push_str fixes.

**Files:**
- `src/commands/doctor_cleanup.rs` (7 warnings)
- `src/commands/lock_lite.rs` (6 warnings)
- `src/commands/delta_files.rs` (5 warnings)
- `src/commands/diff_against_plan.rs` (5 warnings)

**Commit:** `fix(commands): resolve clippy warnings in doctor_cleanup, lock_lite, delta_files, diff_against_plan`
**Verify:** `cargo clippy 2>&1 | grep -cE "(doctor_cleanup|lock_lite|delta_files|diff_against_plan)\.rs"` returns 0

## Task 3: Fix clippy warnings in cache_context, compile_rolling_summary, log_event, auto_repair, help_output

**Description:** Collapse nested if statements and apply minor clippy fixes.

**Files:**
- `src/commands/cache_context.rs` (4 warnings)
- `src/commands/compile_rolling_summary.rs` (4 warnings)
- `src/commands/log_event.rs` (4 warnings)
- `src/commands/auto_repair.rs` (3 warnings)
- `src/commands/help_output.rs` (3 warnings)

**Commit:** `fix(commands): resolve clippy warnings in cache_context, compile_rolling_summary, log_event, auto_repair, help_output`
**Verify:** `cargo clippy 2>&1 | grep -cE "(cache_context|compile_rolling_summary|log_event|auto_repair|help_output)\.rs"` returns 0

## Task 4: Fix clippy warnings in contract_revision, collect_metrics, compile_progress, infer_gsd_summary, atomic_io, generate_contract

**Description:** Collapse nested if statements and apply minor fixes. All 2-warning files.

**Files:**
- `src/commands/contract_revision.rs` (2 warnings)
- `src/commands/collect_metrics.rs` (2 warnings)
- `src/commands/compile_progress.rs` (2 warnings)
- `src/commands/infer_gsd_summary.rs` (2 warnings)
- `src/commands/atomic_io.rs` (2 warnings)
- `src/commands/generate_contract.rs` (2 warnings)

**Commit:** `fix(commands): resolve clippy warnings in contract_revision, collect_metrics, compile_progress, infer_gsd_summary, atomic_io, generate_contract`
**Verify:** `cargo clippy 2>&1 | grep -cE "(contract_revision|collect_metrics|compile_progress|infer_gsd_summary|atomic_io|generate_contract)\.rs"` returns 0

## Task 5: Fix clippy warnings in 1-warning files (A-L)

**Description:** Fix single remaining clippy warnings in assess_plan_risk, bump_version, check_regression, clean_stale_teams, generate_gsd_index, install_hooks.

**Files:**
- `src/commands/assess_plan_risk.rs` (1 warning)
- `src/commands/bump_version.rs` (1 warning)
- `src/commands/check_regression.rs` (1 warning)
- `src/commands/clean_stale_teams.rs` (1 warning)
- `src/commands/generate_gsd_index.rs` (1 warning)
- `src/commands/install_hooks.rs` (1 warning)

**Commit:** `fix(commands): resolve clippy warnings in assess_plan_risk, bump_version, check_regression, clean_stale_teams, generate_gsd_index, install_hooks`
**Verify:** `cargo clippy 2>&1 | grep -cE "(assess_plan_risk|bump_version|check_regression|clean_stale_teams|generate_gsd_index|install_hooks)\.rs"` returns 0
