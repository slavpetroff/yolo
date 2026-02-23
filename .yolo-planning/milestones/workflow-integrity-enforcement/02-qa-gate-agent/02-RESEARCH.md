# Phase 2 Research: QA Gate — Agent-Based Verification

## Findings

### Current State
- Execute protocol Step 3d (SKILL.md lines 677-800) runs 5 Rust CLI commands directly and parses their JSON output
- CLI commands: verify-plan-completion, commit-lint, diff-against-plan, validate-requirements, check-regression
- Each command returns JSON with `ok`, `checks[]`, and `fixable_by` fields
- QA feedback loop exists: categorize failures, spawn Dev for remediation, re-run failed checks
- The yolo-qa agent (`agents/yolo-qa.md`, 114 lines) is NEVER spawned — protocol runs CLI commands inline
- Step 3d heading says "(optional)" — same issue as Step 2b (fixed in Phase 1 for review gate)

### What Should Happen (Per Agent Definition)
- `agents/yolo-qa.md` defines a verification agent that:
  1. Reads SUMMARY.md files from completed plan directory
  2. Runs all 5 verification commands
  3. Analyzes command outputs and cross-references with codebase
  4. Produces structured QA REPORT with remediation classification
  5. Has delta re-run behavior for feedback loops (cycle > 1)
- Agent has proper tool restrictions: Read, Glob, Grep, Bash (no Edit/Write)
- Report format includes: passed, remediation_eligible, checks, hard_stop_reasons, dev_fixable_failures
- Agent classifies each failure with fixable_by routing

### The Gap
- Protocol runs CLI commands directly without agent interpretation
- No adversarial analysis — just mechanical pass/fail on command exit codes
- QA agent would add: cross-referencing SUMMARY claims with actual code, verifying must_haves have real evidence (not just keyword grep), detecting subtle issues like incomplete implementations
- Feedback loop Dev spawn doesn't get agent-quality remediation context

### Phase 1 Pattern to Follow
- Phase 1 established the two-stage pattern for Step 2b (review gate):
  1. CLI pre-check (fast, structural) → Stage 1
  2. Agent spawn (adversarial analysis) → Stage 2
  3. Agent's VERDICT becomes the gate verdict
  4. Fallback to CLI-only if agent spawn fails
  5. Feedback loop uses agent for re-review cycles
- Apply same pattern to Step 3d (QA gate)

### Config Context
- User's config: `qa_gate: "always"`, `qa_max_cycles: 3`
- Defaults: `qa_gate: "on_request"` — gate skipped unless explicitly enabled

## Relevant Patterns

### Files to Modify
1. `skills/execute-protocol/SKILL.md` — Step 3d section (lines 677-800)
   - Must add QA agent spawn after CLI commands run
   - CLI commands become data sources for the QA agent (not the verdict source)
   - Agent produces structured QA REPORT that drives the loop
2. `agents/yolo-qa.md` — May need updates for two-stage awareness and finding IDs
   - Add two-stage context note (same pattern as reviewer)
   - Add report format with finding IDs for delta tracking
   - Update checklist to focus on adversarial verification

### Existing QA Feedback Loop Infrastructure
- Remediation loop logic (lines 754-800) is complete: cycle tracking, Dev spawn, delta re-runs
- Execution state tracking with `qa_loops` in `.execution-state.json`
- Event logging: `qa_loop_start`, `qa_loop_cycle`, `qa_loop_end`
- fixable_by classification per check command
- Dev remediation context scoping table (lines 774-798)
- HARD STOP behavior for architect/manual failures

### Two-Stage QA Pattern
The fix should mirror the review gate pattern:
- CLI commands run first as data collectors
- QA agent receives all CLI output, analyzes adversarially
- Agent can escalate issues the CLI didn't catch (e.g., SUMMARY claims don't match actual code)
- Agent's REPORT becomes the loop driver
- Fallback to CLI-only aggregation if agent spawn fails

## Risks

1. **Token cost**: QA agent spawn adds ~25 turns per phase (once per phase, not per plan)
   - Mitigation: CLI pre-check filters obvious pass cases
2. **Report parsing**: Agent returns structured QA REPORT; protocol must parse reliably
   - Mitigation: Agent definition has structured format with pass/fail + fixable_by
3. **Dual classification**: Agent and CLI both produce fixable_by — which wins?
   - Decision: Agent can override CLI classification (agent has more context). Agent should include CLI output in its analysis.
4. **Backward compatibility**: Changing Step 3d must not break when QA agent is unavailable
   - Mitigation: Fall back to CLI-only aggregation if agent spawn fails

## Recommendations

1. Restructure Step 3d as two-stage: CLI commands (data collection) → agent adversarial verification
2. Fix Step 3d heading: remove "(optional)" label (same as review gate fix)
3. QA agent receives CLI command outputs as structured data in its prompt
4. Agent produces adversarial QA REPORT that can override CLI verdicts
5. Agent's REPORT drives the HARD STOP / remediation-eligible / pass decision
6. Feedback loop spawns QA agent for re-verification (not just re-running CLI commands)
7. Fallback to CLI-only aggregation if agent spawn fails
8. Update yolo-qa.md with two-stage context note and finding IDs
