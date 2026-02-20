---
phase: 2
plan: 04
title: "Migrate agent lifecycle hooks to native Rust (agent-start, agent-stop, agent-health, agent-pid-tracker)"
wave: 1
depends_on: [1]
must_haves:
  - "agent_start handler: normalize role, reference counting with mkdir-based lock, PID registration, tmux pane mapping"
  - "agent_stop handler: decrement-or-cleanup with lock, PID unregister, tmux pane auto-close"
  - "agent_health handler: start/idle/stop/cleanup subcommands, PID liveness check, orphan recovery"
  - "agent_pid_tracker: register/unregister/list with mkdir-based locking"
  - "All use std::fs for file I/O and libc/nix for kill signals — no Command::new(bash)"
---

## Task 1: Implement agent_pid_tracker module

**Files:** `yolo-mcp-server/src/hooks/agent_pid_tracker.rs` (new)

**Acceptance:** Three public functions: `register(pid, planning_dir)`, `unregister(pid, planning_dir)`, `list(planning_dir) -> Vec<u32>`. PID file at `.yolo-planning/.agent-pids` (newline-delimited). mkdir-based locking at `/tmp/yolo-agent-pid-lock` with 50 retries at 100ms. `list` filters dead PIDs using `libc::kill(pid, 0)`. Validate PID format (numeric only). Create `.yolo-planning/` if needed. All functions return `Result<String, String>`. No `Command::new("bash")`.

## Task 2: Implement agent_start hook handler

**Files:** `yolo-mcp-server/src/hooks/agent_start.rs` (new)

**Acceptance:** SubagentStart handler. Parse `agent_type`/`agent_name`/`name` from hook input JSON via serde. Call `utils::normalize_agent_role()` from Plan 01. Only track YOLO agents: require explicit yolo prefix (`yolo-`, `yolo:`, `@yolo:`) OR existing YOLO context (`.yolo-session`, `.active-agent`, `.active-agent-count` file). mkdir-based lock at `.active-agent-count.lock` with stale lock guard (>5s age check using `std::fs::metadata().modified()`). Increment count in `.active-agent-count`, write role to `.active-agent`. Call `agent_pid_tracker::register()`. Tmux pane mapping: if `TMUX` env set, run `Command::new("tmux").args(["list-panes", "-a", "-F", "#{pane_pid} #{pane_id}"])` (direct tmux binary, not bash), walk parent chain via `/proc/{pid}/status` or `sysctl` on macOS, write `PID PANE_ID` to `.agent-panes`. Exit 0 always.

## Task 3: Implement agent_stop hook handler

**Files:** `yolo-mcp-server/src/hooks/agent_stop.rs` (new)

**Acceptance:** SubagentStop handler. mkdir-based lock with stale guard (shared lock logic with agent_start). `decrement_or_cleanup`: read count, handle corrupted count (<=0 with active-agent marker -> treat as 1), decrement, remove markers when count reaches 0. Call `agent_pid_tracker::unregister()`. Tmux pane auto-close: read `.agent-panes`, find matching PID line, remove entry, spawn `Command::new("tmux").args(["kill-pane", "-t", pane_id])` after 1s delay (use `std::thread::sleep`). Exit 0 always.

## Task 4: Implement agent_health hook handler

**Files:** `yolo-mcp-server/src/hooks/agent_health.rs` (new)

**Acceptance:** Four subcommands dispatched by first arg: `start` (create health JSON in `.agent-health/{role}.json` with pid, role, started_at, last_event_at, last_event, idle_count), `idle` (check PID liveness via `libc::kill(pid, 0)`, increment idle_count, orphan recovery if dead, stuck agent warning at idle_count>=3), `stop` (check PID liveness, orphan recovery if dead, remove health file), `cleanup` (remove entire `.agent-health/` dir). Orphan recovery: scan `~/.claude/tasks/*/` for task JSONs where owner matches dead role and status is `in_progress`, clear owner field. All JSON via serde_json. Exit 0 always.

## Task 5: Wire lifecycle hooks into dispatcher and add tests

**Files:** `yolo-mcp-server/src/hooks/dispatcher.rs`, `yolo-mcp-server/src/hooks/mod.rs`, `yolo-mcp-server/src/hooks/agent_start.rs` (append tests), `yolo-mcp-server/src/hooks/agent_stop.rs` (append tests), `yolo-mcp-server/src/hooks/agent_pid_tracker.rs` (append tests)

**Acceptance:** Dispatcher routes `SubagentStart` to `agent_start::handle()` which internally also calls `agent_health::cmd_start()`. Routes `SubagentStop` to `agent_stop::handle()` which calls `agent_health::cmd_stop()`. Routes `TeammateIdle` to `agent_health::cmd_idle()`. Tests cover: PID register/unregister/list with dead PID filtering, agent start reference counting, agent stop decrement-or-cleanup, health file creation/update/deletion, orphan recovery with mock task files. `cargo test` passes.
