---
plan: 01
title: "Rust hook dispatcher and core hook infrastructure"
status: complete
commits: 3
tests_added: 32
tests_total: 273
---

## What Was Built

Native Rust hook dispatcher replacing `hook-wrapper.sh` and `resolve-claude-dir.sh`:

- **hooks/types.rs** — `HookEvent` enum (11 variants: SessionStart, PreToolUse, PostToolUse, PreCompact, SubagentStart, SubagentStop, TeammateIdle, TaskCompleted, UserPromptSubmit, Notification, Stop), `HookInput`/`HookOutput` structs with serde serialization, flexible CLI argument parsing (PascalCase, kebab-case, snake_case)
- **hooks/dispatcher.rs** — `dispatch()` routes events to handler stubs with graceful degradation (errors logged, exit 0 returned), `dispatch_from_cli()` for CLI integration, never panics
- **hooks/utils.rs** — `resolve_claude_dir()` (CLAUDE_CONFIG_DIR env or $HOME/.claude fallback), `resolve_plugin_cache()` (version-sorted directory scan), `log_hook_error()` (append + 50-line trim to 30), `get_planning_dir()` (walk-up directory search), `normalize_agent_role()` (strips yolo-/yolo:/@/team- prefixes, numeric suffixes, maps aliases)
- **hooks/sighup.rs** — signal-hook based SIGHUP handler, reads `.agent-pids`, sends SIGTERM, 3s grace period, SIGKILL survivors
- **CLI route** — `yolo hook <event-name>` reads stdin JSON, dispatches, returns exit code (0 success, 2 block)

## Files Modified

- `yolo-mcp-server/src/hooks/types.rs` (new)
- `yolo-mcp-server/src/hooks/dispatcher.rs` (new)
- `yolo-mcp-server/src/hooks/utils.rs` (new)
- `yolo-mcp-server/src/hooks/sighup.rs` (new)
- `yolo-mcp-server/src/hooks/mod.rs` (modified — added 4 pub mod declarations)
- `yolo-mcp-server/src/cli/router.rs` (modified — added "hook" match arm with stdin read + SIGHUP handler)
- `yolo-mcp-server/Cargo.toml` (modified — added signal-hook and libc deps)

## Test Results

32 tests passing across 4 modules:
- dispatcher: 7 tests (all events routing, bad JSON graceful, CLI dispatch)
- types: 4 tests (arg parsing, serde roundtrip, constructors)
- utils: 12 tests (claude dir resolution, agent role normalization, log trimming, planning dir walk-up)
- sighup: 5 tests (no PID file, empty PIDs, invalid PIDs, nonexistent PIDs, flag registration)

## Commits

1. `a5dc283` feat(hooks): add HookDispatcher with shared types and event routing
2. `89d4465` feat(hooks): implement resolve_claude_dir helper and shared utilities
3. `a0edb9f` feat(hooks): implement SIGHUP cleanup handler for agent PID termination

Router registration was absorbed into dev-02's commit `35d3f9b` (shared file edit).

## Deviations

- Tests embedded in source files per Rust convention rather than separate test files — no separate "tests-only" commit needed
- `Cargo.toml` and `router.rs` changes were co-committed with dev-02's router registration since both agents modified the same files concurrently
