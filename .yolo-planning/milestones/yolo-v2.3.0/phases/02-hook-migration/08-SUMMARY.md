# Plan 08 Summary: Eliminate session_start.rs shell-outs

## Status: COMPLETE

## Tasks Completed: 5/5

### Task 1: Implement migrate_config module
- **File**: `yolo-mcp-server/src/commands/migrate_config.rs` (new, 231 lines)
- **Commit**: `feat(commands): implement native migrate_config module`
- Pure serde_json config migration: renames `agent_teams` to `prefer_teams`, ensures required keys (`model_profile`, `model_overrides`, `prefer_teams`), merges defaults with config-wins semantics, atomic write via temp file
- **Tests**: 9 unit tests (missing config, missing defaults, rename true/false, prefer_teams exists, required keys, merge, count, malformed)

### Task 2: Implement install_hooks module
- **File**: `yolo-mcp-server/src/commands/install_hooks.rs` (new, 183 lines)
- **Commit**: `feat(commands): implement native install_hooks module`
- Git root via `Command::new("git")`. Creates pre-push hook, idempotent (skips if YOLO-managed), upgrades old symlinks, chmod +x. Removes symlink before write to avoid following.
- **Tests**: 5 unit tests (fresh install, already installed, non-yolo skipped, symlink upgrade, symlink non-yolo)

### Task 3: Implement clean_stale_teams and migrate_orphaned_state
- **Files**: `yolo-mcp-server/src/commands/clean_stale_teams.rs` (new, 232 lines), `yolo-mcp-server/src/commands/migrate_orphaned_state.rs` (new, 264 lines)
- **Commit**: `feat(commands): implement native clean_stale_teams and migrate_orphaned_state`
- clean_stale_teams: scans teams dirs, removes stale >2h via atomic mv, cleans paired tasks, UUID-based temp dir to avoid test collisions
- migrate_orphaned_state: finds latest archived STATE.md, extracts project-level sections (Decisions/Todos/Blockers/Codebase Profile), case-insensitive heading matching, idempotent
- **Tests**: 6 + 10 = 16 unit tests

### Task 4: Implement tmux_watchdog module
- **File**: `yolo-mcp-server/src/commands/tmux_watchdog.rs` (new, 263 lines)
- **Commit**: `feat(commands): implement native tmux_watchdog module`
- Polls tmux for detached clients, 2 consecutive empty polls triggers cleanup. Reads PIDs from `.agent-pids`, SIGTERM via libc, 3s wait, SIGKILL fallback. Direct tmux binary calls.
- **Tests**: 7 unit tests (signal alive, dead pids, no pid file, empty pid file, cleanup, empty session, nonexistent dir)

### Task 5: Replace session_start.rs shell-outs with native calls
- **File**: `yolo-mcp-server/src/commands/session_start.rs` (modified, +102/-84 lines)
- **Commit**: `refactor(commands): replace all session_start shell-outs with native Rust`
- Eliminated ALL `Command::new("bash")` calls:
  - Config migration -> `migrate_config::migrate_config()`
  - Orphaned state -> `migrate_orphaned_state::migrate_orphaned_state()`
  - Hook install -> `install_hooks::install_hooks()`
  - Stale teams -> `clean_stale_teams::clean_stale_teams()`
  - Watchdog -> `tmux_watchdog::spawn_watchdog()`
  - UID -> `libc::getuid()`
- Removed `#[cfg(not(tarpaulin_include))]` guards
- **Tests**: 4 new integration tests (native config migration, orphaned state, build_context, uid)

## Metrics
- **New files**: 5
- **New tests**: 41 (9 + 5 + 16 + 7 + 4)
- **Lines added**: ~1175
- **Lines removed**: ~84
- **Shell-outs eliminated**: 6 (3x bash, 2x id, 1x tmux-watchdog spawn)
- **Remaining shell calls**: `jq --version` (dependency check), `git` (direct binary, not bash)
