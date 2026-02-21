---
phase: 2
plan: 01
title: "Rust hook dispatcher and core hook infrastructure"
wave: 1
depends_on: []
must_haves:
  - "`yolo hook <event>` dispatches all hook events via native Rust"
  - "hook-wrapper.sh is fully replaced by Rust dispatcher"
  - "SIGHUP cleanup, error logging, and graceful degradation handled in Rust"
  - "resolve-claude-dir.sh logic inlined as a Rust helper"
  - "All hook JSON parsing done via serde_json, not jq"
---

## Task 1: Create hooks module with HookDispatcher and shared types

**Files:** `yolo-mcp-server/src/hooks/mod.rs` (new), `yolo-mcp-server/src/hooks/dispatcher.rs` (new), `yolo-mcp-server/src/hooks/types.rs` (new)

**Acceptance:** `hooks::types` defines `HookEvent` enum (SessionStart, PreToolUse, PostToolUse, PreCompact, SubagentStart, SubagentStop, TeammateIdle, TaskCompleted, UserPromptSubmit, Notification, Stop) and `HookInput`/`HookOutput` structs with serde. `hooks::dispatcher::dispatch(event, stdin_json)` routes to the correct handler function. Error logging writes to `.yolo-planning/.hook-errors.log`. All handlers return `Result<(String, i32), String>` matching CLI pattern.

The dispatcher must:
1. Parse stdin JSON into `HookInput` (serde_json)
2. Match `HookEvent` to handler function (each handler will be added in subsequent plans)
3. On handler error: log to `.hook-errors.log` with timestamp, return exit 0 (graceful degradation)
4. On handler returning exit 2: pass through (intentional block for PreToolUse/UserPromptSubmit)
5. Never panic or crash the session

## Task 2: Implement resolve_claude_dir helper and shared utilities

**Files:** `yolo-mcp-server/src/hooks/utils.rs` (new)

**Acceptance:** `utils::resolve_claude_dir()` returns `PathBuf` using `CLAUDE_CONFIG_DIR` env var or `$HOME/.claude` fallback. `utils::resolve_plugin_cache()` returns the latest versioned plugin cache directory. `utils::log_hook_error(planning_dir, script_name, exit_code)` appends to `.hook-errors.log` with timestamp and trims to 50 entries. `utils::get_planning_dir()` walks up from cwd to find `.yolo-planning/`. `utils::normalize_agent_role(name)` strips prefixes (yolo-, yolo:, @) and maps to canonical role names (lead, dev, qa, scout, debugger, architect, docs).

All functions must be pure Rust using std::fs, std::env, std::path. No Command::new("bash").

## Task 3: Register `yolo hook <event>` CLI command in router

**Files:** `yolo-mcp-server/src/cli/router.rs`, `yolo-mcp-server/src/commands/mod.rs`

**Acceptance:** `yolo hook <event-name>` reads stdin, calls `hooks::dispatcher::dispatch()`, outputs result to stdout. Exit code matches handler return (0 for success/graceful-fail, 2 for intentional block). The router match arm handles `"hook"` with subcommand dispatch. Add `pub mod hooks;` to `src/lib.rs` or `src/main.rs` as appropriate.

## Task 4: Implement SIGHUP cleanup handler

**Files:** `yolo-mcp-server/src/hooks/sighup.rs` (new)

**Acceptance:** When `yolo hook` receives SIGHUP, it reads `.yolo-planning/.agent-pids`, sends SIGTERM to each PID, waits 3s, sends SIGKILL to survivors. Uses `nix` or `libc` crate for signal handling. Logs cleanup to `.hook-errors.log`. This replaces the SIGHUP trap in hook-wrapper.sh.

Implementation: Register signal handler via `ctrlc` or `signal-hook` crate. On SIGHUP:
1. Read `.yolo-planning/.agent-pids` line by line
2. Validate each line is numeric
3. Send SIGTERM via `kill(pid, SIGTERM)`
4. Sleep 3 seconds
5. Check if still alive, send SIGKILL
6. Exit 1

## Task 5: Add unit tests for dispatcher, utils, and signal handler

**Files:** `yolo-mcp-server/src/hooks/dispatcher.rs` (append tests), `yolo-mcp-server/src/hooks/utils.rs` (append tests)

**Acceptance:** Tests cover: event routing for all HookEvent variants, resolve_claude_dir with/without env var, normalize_agent_role for all known patterns (yolo-lead, @yolo:dev, team-dev-1, etc.), log_hook_error file trimming, graceful degradation on handler error. `cargo test` passes with 0 failures.
