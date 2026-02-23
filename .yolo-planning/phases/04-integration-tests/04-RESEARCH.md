# Phase 4 Research: Integration Tests & Validation

## Test Infrastructure
- 72 bats test files in flat `tests/` directory
- `test_helper.bash` provides: `setup_temp_dir`, `teardown_temp_dir`, `create_test_config`, `$YOLO_BIN`, `$PROJECT_ROOT`
- Three test patterns: A) static grep on source files, B) CLI binary with temp dir, C) event log with config override

## Testing Gaps (6 areas)

### Gap 1: Reviewer agent spawn in Step 2b
- `agent-routing.bats` tests Architect spawn but NOT Reviewer spawn
- Need: grep for `subagent_type: "yolo:yolo-reviewer"` (appears 2x in SKILL.md: initial + re-review)
- Need: grep for `Stage 2 — Reviewer agent spawn` section header

### Gap 2: QA agent spawn in Step 3d
- `agent-routing.bats` tests Dev spawn but NOT QA agent spawn
- Need: grep for `subagent_type: "yolo:yolo-qa"` (appears 3x: initial + re-verification + table)
- Need: grep for `Stage 2 -- QA agent spawn` section header
- Need: grep for `Fast-path optimization: If ALL 5 CLI commands pass`

### Gap 3: ARCHITECTURE.md in execution family compiled context
- Rust unit tests confirm at source level, no bats integration test
- Need: CLI compile-context test asserting dev/qa output contains "Architecture overview"
- Pattern: tier-cache.bats style with temp dir

### Gap 4: Step-ordering tracking in SKILL.md
- Zero tests for any of the 6 `steps_completed` tracking blocks
- Need: grep for each `steps_completed += ["step_X"]` (6 step IDs)
- Need: grep for `"steps_completed": []` in schema

### Gap 5: Step 5 validation gate
- Need: grep for `REQUIRED_STEPS=` and the jq subtraction formula
- Need: grep for `Step ordering violation` and `Step ordering verified`

### Gap 6: Feedback loop text verification
- Need: grep for review_gate and qa_gate activation instructions
- Need: grep for delegation reminders (`Role reminder:`)

## Existing Relevant Files
- `tests/agent-routing.bats` — extend with reviewer/QA agent spawn tests
- `tests/tier-cache.bats` — extend with execution family ARCHITECTURE.md test
- `tests/review-loop.bats` — reference for review gate patterns
- `tests/qa-loop.bats` — reference for QA gate patterns
