---
phase: "03"
plan: "05"
title: "Clippy cleanup and full test verification"
wave: 3
depends_on: [1, 2, 3, 4]
must_haves:
  - "REQ-15: cargo clippy passes with zero warnings"
  - "REQ-16: cargo test passes with zero failures"
  - "REQ-17: No regressions in existing functionality"
---

## Goal

Final verification pass: run `cargo clippy` and `cargo test` across the entire `yolo-mcp-server` crate. Fix any warnings or failures introduced by Plans 01-04.

## Task 1: Run cargo clippy and fix warnings

**Files:** Any file in `yolo-mcp-server/src/` that produces clippy warnings

Run:
```bash
cd yolo-mcp-server && cargo clippy --all-targets -- -D warnings 2>&1
```

Common warnings to expect after the OnceLock migration:
- Unused imports (old `use regex::Regex;` if now using function-scoped access)
- Dead code warnings if local frontmatter functions were not fully removed
- Clippy lint `unnecessary_unwrap` or `map_err_ignore` from the mutex changes

Fix each warning. Do NOT suppress with `#[allow(...)]` unless there is a specific documented reason.

## Task 2: Run full cargo test suite

**Files:** None (read-only verification)

Run:
```bash
cd yolo-mcp-server && cargo test 2>&1
```

All tests must pass. Pay special attention to:
- `telemetry::db::tests` — mutex error propagation must not break test assertions
- `mcp::tools::tests` — poison recovery must not change lock/unlock semantics
- `hooks::security_filter::tests` — OnceLock regex must match identically
- `commands::tier_context::tests` — filter_completed_phases regex must match identically
- `commands::generate_contract::tests` — frontmatter + regex changes must be compatible
- `commands::verify_plan_completion::tests` — frontmatter + regex changes
- `commands::phase_detect::tests` — YoloConfig migration output must match manual parsing
- `commands::parse_frontmatter::tests` — if internal delegation changed
- `commands::list_todos::tests` — date regex OnceLock must match identically

## Task 3: Fix any test failures

**Files:** Whichever files have failing tests

If any test fails:
1. Read the test failure output
2. Identify whether the failure is in the production code change or a test expectation
3. Fix the production code to match expected behavior (do NOT change test expectations unless the test was wrong)

Commit only after both clippy and tests pass clean.
