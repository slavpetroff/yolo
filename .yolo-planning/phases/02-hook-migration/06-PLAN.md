---
phase: 2
plan: 06
title: "Migrate compaction hooks, session-stop, and notification-log to native Rust"
wave: 1
depends_on: [1]
must_haves:
  - "compaction_instructions PreCompact handler returns agent-specific summarization priorities"
  - "post_compact SessionStart(compact) handler restores snapshot and provides re-read guidance"
  - "session_stop Stop handler logs session metrics and cleans up transient markers"
  - "notification_log Notification handler appends metadata to .notification-log.jsonl"
  - "All use serde_json for JSON — no jq, no Command::new(bash)"
---

## Task 1: Implement compaction_instructions PreCompact handler

**Files:** `yolo-mcp-server/src/hooks/compaction_instructions.rs` (new)

**Acceptance:** Extract `agent_name`/`agentName` and `matcher` from input JSON. Match agent name (contains "scout", "dev", "qa", "lead", "architect", "debugger") to role-specific priorities string. Add compaction trigger context (manual vs automatic). Write `.compaction-marker` with epoch timestamp. Save snapshot: if `.execution-state.json` exists, call `snapshot_resume::save()` (Plan 09) directly as Rust function. Return `hookSpecificOutput` JSON with priorities as `additionalContext`. Exit 0 always.

## Task 2: Implement post_compact SessionStart handler

**Files:** `yolo-mcp-server/src/hooks/post_compact.rs` (new)

**Acceptance:** SessionStart(compact) handler. Clean up `.cost-ledger.json` and `.compaction-marker`. Detect agent role from input text (grep for `yolo-lead`, `yolo-dev`, etc.). Map role to suggested re-read files list. Restore snapshot: call `snapshot_resume::restore()`, parse snapshot JSON for plan, status, commits, in-progress task, last completed task, next task. Build snapshot context string. Add teammate task recovery hint for non-unknown roles. Return `hookSpecificOutput` JSON with combined context. Exit 0 always.

## Task 3: Implement session_stop Stop handler

**Files:** `yolo-mcp-server/src/hooks/session_stop.rs` (new)

**Acceptance:** Stop handler. Guard: skip if `.yolo-planning/` doesn't exist. Extract session metrics from input JSON: `cost_usd`/`cost`, `duration_ms`/`duration`, `tokens_in`/`input_tokens`, `tokens_out`/`output_tokens`, `model`. Get branch via `Command::new("git").args(["rev-parse", "--abbrev-ref", "HEAD"])` (direct git, not bash). Build JSON line and append atomically to `.session-log.jsonl` (write to temp, then append). Persist cost summary from `.cost-ledger.json` if exists. Clean up transient markers: remove lock dir, `.active-agent`, `.active-agent-count`, `.agent-panes`, `.task-verify-seen`. Exit 0 always.

## Task 4: Implement notification_log Notification handler

**Files:** `yolo-mcp-server/src/hooks/notification_log.rs` (new)

**Acceptance:** Notification handler. Guard: skip if `.yolo-planning/` doesn't exist. Extract `notification_type`, `message`, `title` from input JSON. Build JSON line with timestamp, type, title, message. Append to `.notification-log.jsonl`. Exit 0 always. Simple and minimal.

## Task 5: Wire compaction/session/notification hooks into dispatcher and add tests

**Files:** `yolo-mcp-server/src/hooks/dispatcher.rs`, `yolo-mcp-server/src/hooks/mod.rs`, `yolo-mcp-server/src/hooks/compaction_instructions.rs` (append tests), `yolo-mcp-server/src/hooks/session_stop.rs` (append tests)

**Acceptance:** Dispatcher routes: `PreCompact` -> `compaction_instructions`, `SessionStart` (check for compact context) -> `post_compact` else `map_staleness` (Plan 10), `Stop` -> `session_stop`, `Notification` -> `notification_log`. Tests cover: role-specific priorities for each agent type, snapshot save/restore integration, session metrics logging with all fields, notification logging, cleanup of transient markers. `cargo test` passes.
