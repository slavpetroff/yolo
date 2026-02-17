# QA Gate Output Patterns

Output templates for all QA gate levels (post-task, post-plan, post-phase) across all states (pass, fail, partial, warn). All output uses symbols from yolo-brand-essentials.toon. No ANSI color codes.

Reference: `references/yolo-brand-essentials.toon` for canonical symbol definitions.

## Post-Task Gate Output

Displayed after each Dev task commit during Step 7 execution. Uses single-line box-drawing (standard_task level per brand essentials) when box is needed.

### Pass State

Minimal single-line output. Shows test count and wall-clock duration.

```
  ✓ Post-task QA: {N} tests passed ({X.Xs})
```

Example:
```
  ✓ Post-task QA: 12 tests passed (2.3s)
```

### Fail State

Uses stop_message two-part pattern: problem description + remediation action. Lists each failing test with file:line reference.

```
  ✗ Post-task QA: {N} of {M} tests failed ({X.Xs})

  Failures:
    ✗ {test-file}:{line} -- {test name}: {failure reason}
    ✗ {test-file}:{line} -- {test name}: {failure reason}

  ➜ Fix failing tests, then re-commit to re-trigger gate.
```

Example:
```
  ✗ Post-task QA: 2 of 14 tests failed (3.1s)

  Failures:
    ✗ tests/unit/resolve-qa-config.bats:42 -- reads fallback from defaults.json: expected 30 got 0
    ✗ tests/unit/resolve-qa-config.bats:58 -- handles missing config.json: command exited with status 1

  ➜ Fix failing tests, then re-commit to re-trigger gate.
```

### Partial State (Warn)

When test infrastructure exists but no tests match the modified files (--scope found zero relevant tests).

```
  ⚠ Post-task QA: no relevant tests for modified files ({X.Xs})

  Modified: {file1}, {file2}

  ➜ Consider adding tests for these files.
```

### Warn State (Missing Infrastructure)

When test runner (bats) or test-summary.sh is not found. Gate passes with warning per fail-open design (architecture.toon C5).

```
  ⚠ Post-task QA: test infrastructure not found, skipping

  ➜ Install bats or verify test-summary.sh exists.
```

### Symbol Usage (Post-Task)
- `✓` (Success/complete) -- all tests passed
- `✗` (Failure/error) -- test failures, each failing test line
- `⚠` (Warning) -- no relevant tests or missing infrastructure
- `➜` (Info/arrow) -- remediation suggestion (next step)
- `--` (Separator) -- between test name and failure reason

## Post-Plan Gate Output

Displayed after all tasks in a plan complete and summary.jsonl is written (Step 7 post-plan). Uses single-line box-drawing for the summary box.

### Pass State

Shows plan-level metrics in a single-line box using metrics_block format (left-padded labels to 14 chars).

```
┌────────────────────────────────────────┐
│ ✓ Post-plan QA: PASS                  │
│                                        │
│          Plan: {NN-MM} {title}         │
│         Tasks: {N}/{M} complete        │
│         Tests: {N} passed ({X.Xs})     │
│     Must-have: {N}/{M} verified        │
└────────────────────────────────────────┘
```

### Fail State

Uses single-line box for summary, then stop_message pattern for each blocking issue.

```
┌────────────────────────────────────────┐
│ ✗ Post-plan QA: FAIL                  │
│                                        │
│          Plan: {NN-MM} {title}         │
│         Tasks: {N}/{M} complete        │
│         Tests: {P} passed, {F} failed  │
│     Must-have: {N}/{M} verified        │
└────────────────────────────────────────┘

  Blocking issues:
    ✗ {issue description} -- {plan-task reference}
    ✗ {issue description} -- {plan-task reference}

  ➜ Fix blocking issues. Plan progression halted until gate passes.
```

### Partial State

When some tasks passed gate but others need remediation. Shows per-task status using file_checklist pattern.

```
┌────────────────────────────────────────┐
│ ⚠ Post-plan QA: PARTIAL               │
│                                        │
│          Plan: {NN-MM} {title}         │
│         Tasks: {N}/{M} complete        │
└────────────────────────────────────────┘

  Task results:
    ✓ T1 -- {task action summary}
    ✓ T2 -- {task action summary}
    ✗ T3 -- {task action summary}: {failure reason}
    ○ T4 -- {task action summary} (blocked by T3)

  ➜ Remediate failing tasks. Senior will re-spec failed items.
```

### Symbol Usage (Post-Plan)
- `✓` (Success/complete) -- gate passed, task passed
- `✗` (Failure/error) -- gate failed, task failed, blocking issue
- `⚠` (Warning) -- partial result
- `○` (Pending/neutral) -- task blocked/not yet run
- `➜` (Info/arrow) -- remediation next step
- `--` (Separator) -- between task ID and description, between issue and reference
- Single-line box-drawing: `┌ ─ ┐ │ └ ┘` (standard_task level per brand essentials)
