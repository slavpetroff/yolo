# QA Gate Help Text

Help text and display templates for QA-related configuration options. Referenced by `commands/config.md` Step 2.7 (QA Gates) and Settings Reference table.

Dependency: `references/qa-output-patterns.md` for output template cross-references.

## Config Display (metrics_block format)

Shown when user views current QA gate settings via /yolo:config or /yolo:status.

```
      QA Gates:
     Post-task: {enabled|disabled}
     Post-plan: {enabled|disabled}
    Post-phase: {enabled|disabled}
       Timeout: {N}s
     Threshold: {strict|lenient|off}
```

Example with defaults:
```
      QA Gates:
     Post-task: enabled
     Post-plan: enabled
    Post-phase: enabled
       Timeout: 30s (post-task) / 300s (post-plan, post-phase)
     Threshold: strict
```

## Config Option Help Text

Each option below maps to a key in the `qa_gates` object in config/defaults.json.

### qa_gates.post_task

**Type:** boolean
**Default:** `true`
**Description:** Run scoped tests after each Dev task commit during Step 7. When disabled, post-task gate is skipped entirely (exit 0, no result logged).
**Help text:** "Post-task gate runs unit tests matching modified files after each Dev commit. Disable to skip per-task testing (not recommended)."

### qa_gates.post_plan

**Type:** boolean
**Default:** `true`
**Description:** Run full test suite after all tasks in a plan complete. Blocks progression to next plan on failure.
**Help text:** "Post-plan gate runs the full test suite when a plan finishes. Disable to skip plan-level verification."

### qa_gates.post_phase

**Type:** boolean
**Default:** `true`
**Description:** Run full system verification before QA agent spawn in Step 9. Failure blocks QA agents (cost savings).
**Help text:** "Post-phase gate verifies all gates and tests before spawning QA agents. Disable to skip pre-QA verification."

### qa_gates.timeout_seconds

**Type:** positive integer
**Default:** `30` (post-task) / `300` (post-plan, post-phase)
**Description:** Maximum wall-clock time for gate execution. Gate result is WARN on timeout.
**Help text:** "Maximum seconds for gate execution. Post-task defaults to 30s. Post-plan and post-phase default to 300s."

### qa_gates.failure_threshold

**Type:** enum ("strict" | "lenient" | "off")
**Default:** `"strict"`
**Description:** Controls gate behavior on test failure. strict = any failure blocks. lenient = only critical failures block. off = log but never block.
**Help text:** "How strictly gates enforce test results. 'strict' blocks on any failure. 'lenient' blocks on critical failures only. 'off' logs results without blocking."

## Interactive Config Prompt (ask_user_question pattern)

Shown during /yolo:config Step 2.7 when user reaches QA Gates section.

```
Configure QA Gates. Pick one.
  (A) Enable all gates (recommended)
  (B) Post-plan and post-phase only (skip per-task)
  (C) Post-phase only (minimal)
  (D) Disable all gates
  (E) Custom configuration
```

If user picks (E), show individual toggles:

```
Post-task QA gate (tests after each commit)?
  (A) Enabled (default)
  (B) Disabled
```

(Repeat for post_plan, post_phase, then prompt for timeout and threshold.)

## Error Remediation Patterns

Each failure type follows the stop_message two-part pattern from brand-essentials.toon:
```
✗ {What went wrong}. {How to fix it}.
```

Gate scripts use these templates to generate actionable error output.

### Test Failures

When one or more tests fail during gate execution.

**Problem line:**
```
✗ {N} test(s) failed in {gate-name} gate.
```

**Detail lines** (one per failing test):
```
    {test-file}:{line} -- {test name}
      Expected: {expected value}
      Actual:   {actual value}
```

**Remediation line:**
```
➜ Review test output above. Fix the failing code or update the test expectation, then re-commit.
```

**Full example:**
```
✗ 2 test(s) failed in post-task gate.

    tests/unit/resolve-qa-config.bats:42 -- reads fallback from defaults.json
      Expected: 30
      Actual:   0
    tests/unit/resolve-qa-config.bats:58 -- handles missing config.json
      Expected: exit 0
      Actual:   exit 1

➜ Review test output above. Fix the failing code or update the test expectation, then re-commit.
```

### Lint Errors

When static analysis or lint checks fail (future extensibility).

**Problem line:**
```
✗ {N} lint error(s) found in {gate-name} gate.
```

**Detail lines** (one per error):
```
    {file}:{line}:{col} -- {rule-name}: {message}
```

**Remediation line:**
```
➜ Fix lint errors above. See rule documentation for guidance.
```

**Full example:**
```
✗ 1 lint error(s) found in post-plan gate.

    scripts/qa-gate-post-task.sh:15:3 -- SC2086: Double quote to prevent globbing and word splitting.

➜ Fix lint errors above. See rule documentation for guidance.
```

### Timeout

When gate execution exceeds qa_gates.timeout_seconds.

**Problem line:**
```
⚠ {gate-name} gate timed out after {N}s (limit: {M}s).
```

**Remediation line:**
```
➜ Increase timeout via qa_gates.timeout_seconds in /yolo:config, or reduce test scope.
```

**Full example:**
```
⚠ post-task gate timed out after 30s (limit: 30s).

➜ Increase timeout via qa_gates.timeout_seconds in /yolo:config, or reduce test scope.
```

### Missing Test Coverage

When gate detects files modified by a task that have no corresponding test files.

**Problem line:**
```
⚠ {N} modified file(s) have no test coverage.
```

**Detail lines** (one per uncovered file, using file_checklist pattern):
```
    ○ {file-path} -- no matching test file
```

**Remediation line:**
```
➜ Consider adding tests for uncovered files. This is a warning, not a blocking failure.
```

**Full example:**
```
⚠ 2 modified file(s) have no test coverage.

    ○ scripts/format-gate-result.sh -- no matching test file
    ○ scripts/resolve-qa-config.sh -- no matching test file

➜ Consider adding tests for uncovered files. This is a warning, not a blocking failure.
```

### Symbol Usage (Remediation)
- `✗` (Failure/error) -- blocking problem line
- `⚠` (Warning) -- non-blocking problem line (timeout, missing coverage)
- `○` (Pending/neutral) -- uncovered file in checklist
- `➜` (Info/arrow) -- remediation action
- `--` (Separator) -- between identifier and description

## Gate Progression Messaging

Messages displayed during gate-level transitions in the 11-step workflow. Shows the user where they are in the gate cascade.

### Post-Task to Post-Plan Transition

Displayed after the last task in a plan completes its post-task gate. Signals escalation to plan-level verification.

```
  ✓ All {N} task gates passed for plan {NN-MM}.
  ➜ Running post-plan gate...
```

Example:
```
  ✓ All 5 task gates passed for plan 04-06.
  ➜ Running post-plan gate...
```

### Post-Plan to Next Plan Transition

Displayed after post-plan gate passes and execution moves to the next plan in the wave.

```
  ✓ Plan {NN-MM} gate passed. Proceeding to plan {NN-MM}.
```

Example:
```
  ✓ Plan 04-06 gate passed. Proceeding to plan 04-07.
```

### Post-Plan to Post-Phase Transition

Displayed after the last plan in the phase completes its post-plan gate. Signals escalation to phase-level verification.

```
  ✓ All {N} plan gates passed for phase {NN}.
  ➜ Running post-phase gate...
```

Example:
```
  ✓ All 10 plan gates passed for phase 04.
  ➜ Running post-phase gate...
```

### Post-Phase to QA Agent Transition

Displayed after post-phase gate passes and QA agents are about to spawn.

```
  ✓ Post-phase gate passed.
  ➜ Spawning QA agents for deep verification...
```

### Cumulative Progress Display

Shown at each gate transition to give the user a sense of overall progress. Uses progress_bars format from brand essentials.

```
  Gate progress:
    Post-task:  ██████████ 100% ({N}/{M} tasks)
    Post-plan:  █████░░░░░  50% ({N}/{M} plans)
    Post-phase: ░░░░░░░░░░   0% (pending)
```

Progress bar width: always 10 chars per brand-essentials.toon progress_bars specification.

### Symbol Usage (Progression)
- `✓` (Success/complete) -- gate level passed
- `➜` (Info/arrow) -- next action / transition
- `█` (Filled block) -- progress bar filled
- `░` (Empty block) -- progress bar empty

## Gate Skip/Override Messaging

Warning messages displayed when QA gates are bypassed. Every skip must show the consequence so users make informed decisions.

### Config-Disabled Gate

When a gate is disabled via qa_gates config (e.g., `qa_gates.post_task: false`).

```
  ⚠ Post-task QA gate disabled via config. Tests will not run after task commits.
```

Shown once at the start of Step 7 execution, not repeated per task.

### --yolo Flag Override

When user passes --yolo flag to /yolo:go, ALL gates are skipped.

```
  ⚠ All QA gates skipped (--yolo flag). No automated testing during execution.

  Consequences:
    ○ Post-task gate: skipped -- test regressions may go undetected per task
    ○ Post-plan gate: skipped -- plan may progress with failing tests
    ○ Post-phase gate: skipped -- QA agents will run without pre-verification
```

### failure_threshold Override

When qa_gates.failure_threshold is set to "off" (log-only, never block).

```
  ⚠ QA gate threshold set to 'off'. Gate failures will be logged but will not block execution.
```

When set to "lenient" (only critical failures block).

```
  ⚠ QA gate threshold set to 'lenient'. Only critical test failures will block execution.
```

### Individual Gate Skip During Execution

When a specific gate is skipped at runtime (e.g., disabled between tasks).

```
  ○ {gate-name} gate: skipped (disabled)
```

This replaces the normal gate status line. It is logged in .qa-gate-results.jsonl with `r:"SKIP"` for audit trail.

### Re-enable Warning

Shown when user re-enables a previously disabled gate.

```
  ✓ {gate-name} gate re-enabled. Gate will run on next trigger.
  ⚠ Prior skipped gates were not retroactively executed. Consider running /yolo:qa to verify.
```

### Cross-References
- Output patterns: `references/qa-output-patterns.md` for gate result templates
- Config options: this file, Config Option Help Text section above
- Gate integration: `references/qa-gate-integration.md` (plan 04-08) for full skip/override logic
