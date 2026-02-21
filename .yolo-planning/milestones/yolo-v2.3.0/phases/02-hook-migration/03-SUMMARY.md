---
phase: 2
plan: 03
title: "Migrate validation hooks to native Rust"
status: complete
tasks_completed: 5
tasks_total: 5
---

## What Was Built

Migrated all 5 validation hook scripts from Bash to native Rust modules in `yolo-mcp-server/src/hooks/`:

1. **validate_summary** — PostToolUse handler checking SUMMARY.md structure (frontmatter, ## What Was Built, ## Files Modified). Non-blocking (exit 0).
2. **validate_frontmatter** — PostToolUse handler checking description field in YAML frontmatter. Detects block scalars (`|`/`>`), empty descriptions, and multi-line continuations. Non-blocking (exit 0).
3. **validate_contract** — Full contract validation with start mode (task range, SHA-256 hash integrity) and end mode (allowed_paths/forbidden_paths). Reads v3_contract_lite and v2_hard_contracts flags from config.json. Advisory (exit 0) or hard stop (exit 2).
4. **validate_message** — V2 typed protocol message validation against `config/schemas/message-schemas.json`. Checks envelope completeness, known type, payload fields, role authorization, receive-direction, and file references against active contract. Exit 0 when valid, exit 2 when invalid.
5. **validate_schema** — YAML frontmatter field validation for plan/summary/contract schema types. Gated by v3_schema_validation flag. Fail-open (always exit 0).

All modules are pure Rust with no shell-outs. Each provides a hook entry point function and comprehensive unit tests.

## Files Modified

- `yolo-mcp-server/src/hooks/validate_summary.rs` (new, 181 lines)
- `yolo-mcp-server/src/hooks/validate_frontmatter.rs` (new, 278 lines)
- `yolo-mcp-server/src/hooks/validate_contract.rs` (new, 444 lines)
- `yolo-mcp-server/src/hooks/validate_message.rs` (new, 514 lines)
- `yolo-mcp-server/src/hooks/validate_schema.rs` (new, 363 lines)
- `yolo-mcp-server/src/hooks/mod.rs` (updated — module declarations)
- `yolo-mcp-server/src/main.rs` (updated — added `pub mod hooks`)

## Test Results

- 76 validation-specific tests, all passing
- 293 total tests in cargo test, 0 failures (1 pre-existing flaky test in dev-02's log_event env var test)
- 5 commits, one per task
