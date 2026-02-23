---
phase: 1
plan: 01
title: "Critical & High — Cargo.toml + Unused Parameters"
wave: 1
depends_on: []
must_haves:
  - REQ-01
  - REQ-02
---

# Plan 01: Critical & High — Cargo.toml + Unused Parameters

Fix the one critical issue (dual bin target) and all four high-severity unused parameter warnings.

## Files Modified (5 — disjoint from Plans 02/03/04)
- `Cargo.toml`
- `src/hooks/map_staleness.rs`
- `src/commands/session_start.rs`
- `src/commands/state_updater.rs`
- `src/hooks/agent_health.rs`

## Task 1: Fix Cargo.toml dual bin target

**Description:** Both `[[bin]]` entries (`yolo` and `yolo-mcp-server`) point to the same `src/main.rs`. This triggers a compiler warning on every build. Remove the `yolo` bin target — the binary is already aliased via install hooks.

**Files:** `Cargo.toml` (lines 27-29)
**Commit:** `fix(build): remove duplicate yolo bin target from Cargo.toml`
**Verify:** `cargo clippy 2>&1 | grep -c "found to be present in multiple"` returns 0

## Task 2: Prefix unused `input` parameter in map_staleness.rs

**Description:** `handle()` at line 14 accepts `input: &HookInput` but never reads it. Prefix with underscore: `_input`.

**Files:** `src/hooks/map_staleness.rs:14`
**Commit:** `fix(hooks): prefix unused input param in map_staleness::handle`
**Verify:** `cargo clippy 2>&1 | grep "map_staleness" | grep "unused"` returns empty

## Task 3: Prefix unused `cwd` parameter in session_start.rs

**Description:** `build_context()` at line 796 accepts `cwd: &Path` but never reads it. Prefix with underscore: `_cwd`.

**Files:** `src/commands/session_start.rs:796`
**Commit:** `fix(commands): prefix unused cwd param in session_start::build_context`
**Verify:** `cargo clippy 2>&1 | grep "session_start" | grep "unused variable"` returns empty

## Task 4: Prefix unused `phase_dir` parameter in state_updater.rs

**Description:** `update_model_profile()` at line 255 accepts `phase_dir: &Path` but never reads it. Prefix with underscore: `_phase_dir`.

**Files:** `src/commands/state_updater.rs:255`
**Commit:** `fix(commands): prefix unused phase_dir param in state_updater::update_model_profile`
**Verify:** `cargo clippy 2>&1 | grep "state_updater" | grep "unused variable"` returns empty

## Task 5: Prefix unused `planning_dir` parameter in agent_health.rs

**Description:** `orphan_recovery()` at line 150 accepts `planning_dir: &Path` but never reads it. Prefix with underscore: `_planning_dir`.

**Files:** `src/hooks/agent_health.rs:150`
**Commit:** `fix(hooks): prefix unused planning_dir param in agent_health::orphan_recovery`
**Verify:** `cargo clippy 2>&1 | grep "agent_health" | grep "unused variable"` returns empty
