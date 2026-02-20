---
phase: 2
plan: 17
title: "Update hooks.json to use native Rust dispatcher and retire hook-wrapper.sh"
wave: 3
depends_on: [1, 3, 4, 5, 6, 7]
must_haves:
  - "hooks.json updated to call `yolo hook <event>` instead of hook-wrapper.sh for ALL hook events"
  - "hook-wrapper.sh marked as deprecated with forwarding stub"
  - "All hook events route through native Rust dispatcher"
  - "cargo test passes with full hook coverage"
  - "End-to-end integration test: yolo hook <event> with mock stdin produces correct output"
---

## Task 1: Update hooks.json to use native Rust dispatcher

**Files:** `hooks.json`

**Acceptance:** Replace all hook entries that invoke `hook-wrapper.sh <script>` or direct bash scripts with `yolo hook <event-name>`. Hook event mapping: `PreToolUse` (security-filter -> yolo hook PreToolUse), `PostToolUse` (validate-summary, validate-frontmatter, skill-hook-dispatch -> yolo hook PostToolUse), `SubagentStart` (agent-start, agent-health start -> yolo hook SubagentStart), `SubagentStop` (agent-stop, agent-health stop -> yolo hook SubagentStop), `TeammateIdle` (agent-health idle -> yolo hook TeammateIdle), `PreCompact` (compaction-instructions -> yolo hook PreCompact), `SessionStart` (post-compact, map-staleness -> yolo hook SessionStart), `UserPromptSubmit` (prompt-preflight -> yolo hook UserPromptSubmit), `Stop` (session-stop -> yolo hook Stop), `Notification` (notification-log -> yolo hook Notification), `TaskCompleted` (blocker-notify -> yolo hook TaskCompleted). Each entry uses `command: "yolo"` with `args: ["hook", "<event>"]`, reads stdin, outputs JSON.

## Task 2: Create hook-wrapper.sh deprecation stub

**Files:** `scripts/hook-wrapper.sh`

**Acceptance:** Replace hook-wrapper.sh contents with a forwarding stub that: (1) logs deprecation warning to `.hook-errors.log`, (2) resolves the event name from $1 (the script name maps to an event), (3) forwards to `yolo hook <event>` piping stdin, (4) passes through exit code. This ensures any external callers or cached older hooks.json still work during transition. Add comment: `# DEPRECATED: This script forwards to native Rust dispatcher. Remove in v3.0.`

## Task 3: Add end-to-end integration tests for hook dispatcher

**Files:** `yolo-mcp-server/src/hooks/dispatcher.rs` (append tests)

**Acceptance:** Integration tests that exercise the full dispatch path for each hook event: (1) PreToolUse with sensitive file -> exit 2, (2) PreToolUse with safe file -> exit 0, (3) PostToolUse with SUMMARY.md -> validation output, (4) SubagentStart with yolo-dev -> agent start output, (5) SubagentStop -> decrement output, (6) PreCompact with dev agent -> priorities output, (7) SessionStart compact -> re-read guidance, (8) UserPromptSubmit with /yolo:vibe -> session marker, (9) Stop -> session log entry, (10) Notification -> log entry, (11) TaskCompleted -> blocker check. Each test constructs mock input JSON, calls `dispatch()`, and verifies output structure and exit code.

## Task 4: Verify no remaining Command::new("bash") in hook paths

**Files:** `yolo-mcp-server/src/hooks/mod.rs` (append verification test)

**Acceptance:** Add a static analysis test that uses `include_str!` or `std::fs::read_to_string` to read all `src/hooks/*.rs` files and assert none contain `Command::new("bash")` (except skill_hook_dispatch.rs which legitimately invokes user-defined skill scripts). This prevents regression. Also verify that `src/commands/session_start.rs` and `src/commands/hard_gate.rs` no longer contain `Command::new("bash")`.

## Task 5: Final cleanup and documentation

**Files:** `yolo-mcp-server/src/hooks/mod.rs`, `yolo-mcp-server/Cargo.toml`

**Acceptance:** Verify all hook modules are declared in `mod.rs`. Verify all required crate dependencies are in `Cargo.toml` (sha2, uuid, signal-hook or nix, serde, serde_json — most already present). Run `cargo test` — all tests pass with 0 failures. Run `cargo clippy` — no warnings in hooks/ modules. Update module-level doc comments in `hooks/mod.rs` listing all supported hook events and their handlers.
