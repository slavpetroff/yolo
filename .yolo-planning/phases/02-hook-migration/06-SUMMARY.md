---
plan: "06"
phase: 2
title: "Migrate compaction hooks, session-stop, and notification-log to native Rust"
agent: dev-06
status: completed
tasks_completed: 5
tasks_total: 5
commits: 5
deviations: 0
---

## What Was Built

Migrated 4 bash hook scripts to native Rust handlers, eliminating all shell-outs:

1. **compaction_instructions.rs** -- PreCompact handler that extracts agent role, maps to role-specific compaction priorities (dev/qa/lead/architect/scout/debugger), writes `.compaction-marker` with timestamp, saves agent state snapshot, and returns `hookSpecificOutput` with priorities. Replaces `scripts/compaction-instructions.sh`.

2. **post_compact.rs** -- SessionStart(compact) handler that cleans up stale `.cost-ledger.json` and `.compaction-marker`, detects agent role from input context, maps role to re-read file suggestions, restores latest snapshot with task resume hints (in-progress task, last completed, next task), and returns re-read guidance. Replaces `scripts/post-compact.sh`.

3. **session_stop.rs** -- Stop handler that extracts session metrics (cost, duration, tokens, model), gets git branch via `Command::new("git")`, appends to `.session-log.jsonl`, persists cost summary from `.cost-ledger.json`, and cleans up transient agent markers. Replaces `scripts/session-stop.sh`.

4. **notification_log.rs** -- Notification handler that extracts notification_type/message/title and appends to `.notification-log.jsonl`. Replaces `scripts/notification-log.sh`.

5. **Dispatcher wiring** -- Replaced 4 stub routes with real handlers: PreCompact -> compaction_instructions, SessionStart(compact) -> post_compact, Stop -> session_stop, Notification -> notification_log. Added `value_to_hook_output` adapter for `(Value, i32)` -> `HookOutput` conversion.

## Files Modified

- `yolo-mcp-server/src/hooks/compaction_instructions.rs` (new, 268 lines)
- `yolo-mcp-server/src/hooks/post_compact.rs` (new, 485 lines)
- `yolo-mcp-server/src/hooks/session_stop.rs` (new, 306 lines)
- `yolo-mcp-server/src/hooks/notification_log.rs` (new, 149 lines)
- `yolo-mcp-server/src/hooks/dispatcher.rs` (modified, wired 4 routes + 8 new tests)
- `yolo-mcp-server/src/hooks/mod.rs` (modified, added 4 module declarations)

## Test Results

62 tests across all 4 new modules + dispatcher integration tests. All pass.
- compaction_instructions: 11 tests (role priorities, agent name parsing, output structure)
- post_compact: 14 tests (role detection, re-read files, plan parsing, snapshot restore)
- session_stop: 11 tests (metric extraction, JSONL append, cost summary, cleanup)
- notification_log: 5 tests (missing fields, entry format, defaults)
- dispatcher: 8 new tests (pre_compact priorities, notification/stop exit 0, session_start compact vs non-compact)
