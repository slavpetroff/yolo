---
phase: 2
plan: 08
title: "Eliminate session_start.rs shell-outs (migrate-config, install-hooks, clean-stale-teams, migrate-orphaned-state, tmux-watchdog)"
wave: 2
depends_on: [1, 2]
must_haves:
  - "migrate_config inlined as Rust: rename legacy keys, ensure required keys, merge defaults.json"
  - "install_hooks inlined as Rust: create standalone pre-push hook script in .git/hooks/"
  - "clean_stale_teams inlined as Rust: scan ~/.claude/teams/ for stale dirs, atomic removal"
  - "migrate_orphaned_state inlined as Rust: find latest archived STATE.md, reconstruct root"
  - "tmux_watchdog inlined as Rust: poll tmux for detached sessions, terminate orphaned agents"
  - "All Command::new(bash) calls in session_start.rs replaced with direct Rust function calls"
---

## Task 1: Implement migrate_config module

**Files:** `yolo-mcp-server/src/commands/migrate_config.rs` (new)

**Acceptance:** `migrate_config::execute(config_path, defaults_path) -> Result<(i32, String), String>` returns count of added keys. Logic: (1) read defaults.json and config.json via serde_json, (2) rename `agent_teams` to `prefer_teams` (true->"always", false->"auto"), (3) ensure `model_profile`, `model_overrides`, `prefer_teams` keys exist, (4) generic brownfield merge: `defaults + config` (config values win), (5) write back atomically (temp file + rename). Fail on malformed JSON with descriptive error. Pure serde_json, no jq.

## Task 2: Implement install_hooks module

**Files:** `yolo-mcp-server/src/commands/install_hooks.rs` (new)

**Acceptance:** `install_hooks::execute(cwd) -> Result<String, String>`. Logic: (1) find git root via `Command::new("git").args(["rev-parse", "--show-toplevel"])` (direct git binary), (2) ensure `.git/hooks/` exists, (3) check if `pre-push` hook exists: if symlink to YOLO script -> upgrade to standalone, if contains "YOLO pre-push hook" -> skip, if other -> skip with warning, if absent -> create, (4) write standalone hook content with proper `#!/usr/bin/env bash` shebang and `CLAUDE_CONFIG_DIR` resolution, (5) chmod +x via `std::fs::set_permissions`. No `Command::new("bash")`.

## Task 3: Implement clean_stale_teams and migrate_orphaned_state modules

**Files:** `yolo-mcp-server/src/commands/clean_stale_teams.rs` (new), `yolo-mcp-server/src/commands/migrate_orphaned_state.rs` (new)

**Acceptance:** `clean_stale_teams::execute(claude_dir, planning_dir) -> Result<String, String>`: scan `{claude_dir}/teams/*/inboxes/`, get most recent mtime per team, remove teams stale > 2 hours (atomic: rename to `/tmp/yolo-stale-teams-{pid}/` then delete). Also remove paired `{claude_dir}/tasks/{team_name}/` dirs. Log to `.hook-errors.log`. `migrate_orphaned_state::execute(planning_dir) -> Result<String, String>`: guard checks (no STATE.md, no ACTIVE file, has milestones), find latest archived STATE.md by mtime, call `persist_state::execute()` (Plan 09). Both use `std::fs` for file ops, `std::time::SystemTime` for age checks.

## Task 4: Implement tmux_watchdog module

**Files:** `yolo-mcp-server/src/commands/tmux_watchdog.rs` (new)

**Acceptance:** `tmux_watchdog::execute(session_name) -> Result<String, String>`. Background polling loop: (1) check session exists via `Command::new("tmux").args(["has-session", "-t", session])`, (2) count clients via `Command::new("tmux").args(["list-clients", "-t", session])`, (3) require 2 consecutive empty polls before cleanup, (4) read PIDs from `agent_pid_tracker::list()`, (5) send SIGTERM via `libc::kill(pid, SIGTERM)`, (6) sleep 3s, (7) SIGKILL survivors, (8) clean up `.agent-pids`. Log to `.watchdog.log`. Direct tmux binary calls, no bash wrapper.

## Task 5: Replace session_start.rs shell-outs with native calls and add tests

**Files:** `yolo-mcp-server/src/commands/session_start.rs`, `yolo-mcp-server/src/commands/mod.rs`, `yolo-mcp-server/src/commands/migrate_config.rs` (append tests), `yolo-mcp-server/src/commands/install_hooks.rs` (append tests)

**Acceptance:** In session_start.rs: replace `Command::new("bash").arg(migrate_sh)` with `migrate_config::execute()`, replace `Command::new("bash").arg("install-hooks.sh")` with `install_hooks::execute()`, replace `Command::new("bash").arg("clean-stale-teams.sh")` with `clean_stale_teams::execute()`, replace `Command::new("bash").arg("migrate-orphaned-state.sh")` with `migrate_orphaned_state::execute()`, replace `Command::new("bash").arg("tmux-watchdog.sh")` with spawning `tmux_watchdog::execute()` in a thread. Remove `#[cfg(not(tarpaulin_include))]` guards. Tests cover: config migration with legacy key rename, defaults merge, hook installation idempotency, stale team detection. `cargo test` passes.
