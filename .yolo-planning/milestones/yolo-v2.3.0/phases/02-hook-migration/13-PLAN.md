---
phase: 2
plan: 13
title: "Migrate token/lock/completion scripts to native Rust (token-budget, lock-lite, lease-lock, two-phase-complete)"
wave: 2
depends_on: [1, 2]
must_haves:
  - "token_budget enforces character-based budgets with per-task complexity scoring"
  - "lock_lite provides file ownership locks with mkdir-based locking"
  - "lease_lock extends lock_lite with TTL/heartbeat/expired lease cleanup"
  - "two_phase_complete implements candidate/validate/confirm completion protocol"
  - "All use native Rust — no jq, no awk, no Command::new(bash)"
---

## Task 1: Implement token_budget module

**Files:** `yolo-mcp-server/src/commands/token_budget.rs` (new)

**Acceptance:** `token_budget::execute(role, content, contract_path, budgets_path, config_path) -> Result<(String, i32), String>`. Check `v2_token_budgets` flag. Per-task budget: read contract must_haves/allowed_paths/depends_on counts, apply weights from token-budgets.json, compute complexity score, find matching tier, multiply role base budget. Per-role fallback: read `budgets[role].max_chars` from token-budgets.json. No budget -> pass through. Truncation: head strategy (preserve goal/criteria at top) using `&content[..max_chars]` with char boundary safety. Log overage via `collect_metrics::collect()`. Also expose CLI entry point (`yolo token-budget <role> [file]`).

## Task 2: Implement lock_lite module

**Files:** `yolo-mcp-server/src/commands/lock_lite.rs` (new)

**Acceptance:** `lock_lite::execute(action, task_id, files, planning_dir) -> Result<(String, i32), String>`. Actions: `acquire` (mkdir `.locks/`, check for conflicts against existing .lock files, write lock JSON with task_id/pid/timestamp/files), `release` (remove .lock file), `check` (scan for conflicts, report count). Lock files: `.yolo-planning/.locks/{task-id}.lock`. Conflict detection: iterate existing locks, compare file lists for overlap. Emit `file_conflict` metric via `collect_metrics::collect()` on conflict. Gated by `v3_lock_lite` flag. Exit 0 always. Also expose CLI entry point.

## Task 3: Implement lease_lock module (extends lock_lite)

**Files:** `yolo-mcp-server/src/commands/lease_lock.rs` (new)

**Acceptance:** `lease_lock::execute(action, task_id, files, ttl, planning_dir) -> Result<(String, i32), String>`. Actions: `acquire` (cleanup expired first, check conflicts, write lock with TTL and expires_at epoch), `renew` (extend expiry by existing TTL), `release` (remove), `check` (cleanup expired, detect conflicts), `query` (read-only lock inspection). Parse `--ttl=N` from args (default 300s). Expired lock detection: compare `expires_at` against current epoch. Hard enforcement: exit 1 on conflict when `v2_hard_gates=true`. Gated by `v3_lease_locks` or `v3_lock_lite`. Also expose CLI entry point.

## Task 4: Implement two_phase_complete module

**Files:** `yolo-mcp-server/src/commands/two_phase_complete.rs` (new)

**Acceptance:** `two_phase_complete::execute(task_id, phase, plan, contract_path, evidence) -> Result<(String, i32), String>`. Gated by `v2_two_phase_completion`. Phase 1: emit `task_completed_candidate` via `log_event::log()`. Phase 2: validate must_haves (require non-empty evidence), validate files_modified against allowed_paths (prefix matching), run verification_checks (each is a shell command via `Command::new("sh").arg("-c").arg(check)` -- this is acceptable as checks are user-defined). Phase 3: emit `task_completed_confirmed` or `task_completion_rejected`. Output JSON: `{result, checks_passed, checks_total, errors}`. Exit 0 on confirmed, exit 2 on rejected. Also expose CLI entry point.

## Task 5: Register CLI commands and add tests

**Files:** `yolo-mcp-server/src/commands/mod.rs`, `yolo-mcp-server/src/cli/router.rs`, `yolo-mcp-server/src/commands/token_budget.rs` (append tests), `yolo-mcp-server/src/commands/lock_lite.rs` (append tests), `yolo-mcp-server/src/commands/lease_lock.rs` (append tests), `yolo-mcp-server/src/commands/two_phase_complete.rs` (append tests)

**Acceptance:** Register `yolo token-budget`, `yolo lock`, `yolo lease-lock`, `yolo two-phase-complete` in router. Tests cover: budget enforcement with truncation, per-task complexity scoring, lock acquire/release/check, conflict detection between tasks, lease TTL expiry, lease renewal, two-phase confirm (all checks pass), two-phase reject (out-of-scope files), two-phase skip (flag off). `cargo test` passes.
