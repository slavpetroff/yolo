---
phase: 2
plan: 07
title: "Migrate skill-hook-dispatch, blocker-notify, and implement missing hooks"
wave: 2
depends_on: [1, 2]
must_haves:
  - "skill_hook_dispatch reads config.json skill_hooks and invokes matching skill scripts"
  - "blocker_notify scans task files for cleared blockers on TaskCompleted"
  - "All handlers return hookSpecificOutput JSON matching Claude Code hook protocol"
---

## Task 1: Implement skill_hook_dispatch handler

**Files:** `yolo-mcp-server/src/hooks/skill_hook_dispatch.rs` (new)

**Acceptance:** Takes event_type as context from dispatcher. Extract `tool_name` from input JSON. Walk up from cwd to find `.yolo-planning/config.json`. Read `skill_hooks` map from config (format: `{"skill-name": {"event": "PostToolUse", "tools": "Write|Edit"}}`). For each skill hook: check event type match, check tool name matches regex pattern. Find skill script in plugin cache: resolve latest versioned dir under `~/.claude/plugins/cache/yolo-marketplace/yolo/*/scripts/{skill-name}-hook.sh` using `std::fs::read_dir` + version sorting. Invoke matched script via `Command::new("bash").arg(script_path)` piping input on stdin. This is the ONE exception where bash is acceptable (executing user-defined skill scripts). Exit 0 always.

## Task 2: Implement blocker_notify TaskCompleted handler

**Files:** `yolo-mcp-server/src/hooks/blocker_notify.rs` (new)

**Acceptance:** Guard: skip if `.yolo-planning/` doesn't exist or no `jq`-equivalent parsing possible. Extract completed `task_id` from input JSON. Resolve CLAUDE_DIR via `utils::resolve_claude_dir()`. Find team task directories under `{CLAUDE_DIR}/tasks/*/`. For each task JSON file: skip completed/deleted status, check if `blockedBy` array contains completed task_id, check if ALL other blockers are also completed (read each blocker's status). If fully unblocked: collect task subject, owner, and file ID. Output `hookSpecificOutput` JSON with `BLOCKER CLEARED:` advisory listing unblocked tasks. Exit 0 always.

## Task 3: Wire skill-hook and blocker-notify into dispatcher

**Files:** `yolo-mcp-server/src/hooks/dispatcher.rs`, `yolo-mcp-server/src/hooks/mod.rs`

**Acceptance:** Dispatcher routes: `PostToolUse` -> validation hooks (Plan 03) then `skill_hook_dispatch`, `TaskCompleted` -> `blocker_notify`. Module declarations added.

## Task 4: Add tests for skill_hook_dispatch and blocker_notify

**Files:** `yolo-mcp-server/src/hooks/skill_hook_dispatch.rs` (append tests), `yolo-mcp-server/src/hooks/blocker_notify.rs` (append tests)

**Acceptance:** Tests cover: skill hook matching by event type and tool name regex, no match when event type differs, no match when tool name doesn't match pattern, blocker detection with single blocker, blocker detection with multiple blockers (some still pending), no unblocked tasks when all blockers remain pending. `cargo test` passes.
