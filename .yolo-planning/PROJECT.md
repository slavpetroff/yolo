# Workflow Validation & Rust Quality Audit

Validate that QA/Reviewer agents are properly configured and triggered, audit the Rust codebase for idiomatic best practices, and ensure human-in-the-loop is properly wired end-to-end.

**Core value:** Every quality mechanism (QA, review, HITL) must be properly wired, enforced, and production-ready — not just defined.

## Requirements

### Validated

### Active
- REQ-01: QA gate defaults must fire automatically (not just on_request)
- REQ-02: qa_skip_agents config must be enforced in execute protocol
- REQ-03: check-regression fixable_by must be consistent across protocol, CLI, and agent def
- REQ-04: Verdict parsing must fail-closed (not fail-open) on malformed agent output
- REQ-05: request_human_approval MCP tool must actually block execution (not stub)
- REQ-06: HITL Vision Gate must be platform-enforced, not honor-system
- REQ-07: Mutex::lock() in async code must not panic on poisoned mutex
- REQ-08: Regex compilation must use OnceLock statics for hot paths
- REQ-09: Duplicated frontmatter parser must be extracted to shared utility
- REQ-10: Config parsing must use typed YoloConfig struct consistently

### Out of Scope
- New agent types or workflow features
- Changes to the plugin's command interface
- UI/visual format changes
- New MCP tools beyond fixing request_human_approval

## Constraints
- Fixes must be backward-compatible (no breaking changes to config schema)
- Tests must pass after each phase
- Execute protocol changes must work with all effort levels
- Existing agent definitions remain functional as standalone subagent_types
- Rust changes must compile clean with `cargo clippy` and pass existing tests

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
