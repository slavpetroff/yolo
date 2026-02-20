---
plan: 04
title: "Migrate agent lifecycle hooks to native Rust"
status: complete
commits: 5
tests_added: 41
tests_total: 412
---

## What Was Built

Native Rust replacements for `agent-pid-tracker.sh`, `agent-start.sh`, `agent-stop.sh`, and `agent-health.sh`:

- **agent_pid_tracker.rs** -- register/unregister/list with mkdir-based locking at `/tmp/yolo-agent-pid-lock`, dead PID filtering via `libc::kill(pid, 0)`, 50 retries at 100ms
- **agent_start.rs** -- SubagentStart handler: role normalization via `utils::normalize_agent_role()`, explicit YOLO agent detection (`yolo-`/`yolo:`/`@yolo:` prefix), existing YOLO context check (`.yolo-session`/`.active-agent`/`.active-agent-count`), reference counting with stale lock guard (>5s age), PID registration, tmux pane mapping via parent chain walk using `ps`
- **agent_stop.rs** -- SubagentStop handler: decrement-or-cleanup with corrupted count recovery, PID unregistration, tmux pane auto-close with 1s delay thread
- **agent_health.rs** -- Four subcommands: `start` (create health JSON), `idle` (PID liveness check, idle_count increment, stuck agent warning at >=3, orphan recovery for dead PIDs), `stop` (PID check, orphan recovery, remove health file), `cleanup` (remove entire `.agent-health/` dir). Orphan recovery scans `~/.claude/tasks/*/` for tasks owned by dead agents and clears ownership
- **dispatcher.rs** -- Wired SubagentStart to agent_start+agent_health::cmd_start, SubagentStop to agent_stop+agent_health::cmd_stop, TeammateIdle to agent_health::cmd_idle

## Files Modified

- `yolo-mcp-server/src/hooks/agent_pid_tracker.rs` (new)
- `yolo-mcp-server/src/hooks/agent_start.rs` (new)
- `yolo-mcp-server/src/hooks/agent_stop.rs` (new)
- `yolo-mcp-server/src/hooks/agent_health.rs` (new)
- `yolo-mcp-server/src/hooks/mod.rs` (modified -- added 4 lifecycle module declarations)
- `yolo-mcp-server/src/hooks/dispatcher.rs` (modified -- wired 3 lifecycle events)

## Test Results

41 tests across 4 modules:
- agent_pid_tracker: 12 tests (register/dedup/unregister, dead PID filtering, current process alive, invalid lines)
- agent_start: 10 tests (explicit/non-yolo agents, YOLO context, reference counting, PID extraction)
- agent_stop: 7 tests (decrement, cleanup at zero, corrupted count, legacy no-count, PID handling)
- agent_health: 12 tests (start/idle/stop/cleanup, stuck warning, dead PID recovery, orphan task clearing)

Full suite: 412 passed, 0 failed.

## Commits

1. `1879d8a` feat(hooks): implement agent_pid_tracker with mkdir-based locking
2. `644e3e3` feat(hooks): implement agent_start SubagentStart handler
3. `f532e23` feat(hooks): implement agent_stop SubagentStop handler
4. `74a19dc` feat(hooks): implement agent_health with start/idle/stop/cleanup
5. `cd6cbed` feat(hooks): wire lifecycle hooks into dispatcher

## Deviations

None. All must-haves met.
