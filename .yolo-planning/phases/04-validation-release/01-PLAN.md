---
phase: "04"
plan: "01"
title: "End-to-end test validation"
wave: 1
depends_on: []
must_haves:
  - "REQ-18: Full bats test suite passes with 0 failures"
  - "REQ-19: Full cargo test suite passes with 0 regressions"
  - "REQ-20: Execute protocol gates verified functional"
---

## Goal

Run the full test suites (bats + Rust) and verify all Phase 1-3 changes work correctly together.

## Task 1: Run full bats test suite

**Files:** None (read-only verification)

Run:
```bash
bats tests/unit/ tests/static/ tests/containment/ tests/integration/ tests/perf/
```

All tests must pass. Report total count and any failures.

## Task 2: Run full cargo test suite

**Files:** None (read-only verification)

Run:
```bash
cd yolo-mcp-server && cargo test
```

Report total pass count. Document any pre-existing failures (not regressions).

## Task 3: Verify execute protocol gates

**Files:** None (read-only verification)

Verify that:
1. `config/defaults.json` has `review_gate: "always"` and `qa_gate: "always"`
2. Execute protocol SKILL.md has Step 2b (review gate) and Step 3d (QA gate)
3. `request_human_approval` tool returns structured JSON with `status: "paused"`
4. Vision gate (Step 2c) documented in execute protocol
