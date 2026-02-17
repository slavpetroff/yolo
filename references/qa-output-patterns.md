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

## Post-Phase Gate Output

Displayed before QA agent spawn (Step 9). Uses double-line box-drawing (critical_phase level per brand essentials). This is the highest-criticality gate -- failure blocks QA agent spawn entirely (cost savings: prevents expensive LLM agents from running on known-broken code).

### Pass State

Shows phase-level aggregate metrics in a double-line box.

```
╔════════════════════════════════════════╗
║ ✓ Post-phase QA: PASS                 ║
║                                        ║
║         Phase: {NN} {title}            ║
║         Plans: {N}/{M} complete        ║
║         Tests: {N} passed ({X.Xs})     ║
║         Gates: {N}/{M} passed          ║
╚════════════════════════════════════════╝

  ➜ Spawning QA agents for deep verification...
```

### Fail State

Uses double-line box for summary, then lists blocking gates with escalation path.

```
╔════════════════════════════════════════╗
║ ✗ Post-phase QA: FAIL                 ║
║                                        ║
║         Phase: {NN} {title}            ║
║         Plans: {N}/{M} complete        ║
║         Tests: {P} passed, {F} failed  ║
║         Gates: {N}/{M} passed          ║
╚════════════════════════════════════════╝

  Blocking gates:
    ✗ Post-plan {NN-MM}: {failure summary}
    ✗ Post-plan {NN-MM}: {failure summary}

  ✗ QA agent spawn blocked. Remediation required.
  ➜ Fix blocking gates. A remediation plan will be generated.
```

### Partial State

When some plans passed gate but others failed. Lists per-plan gate status.

```
╔════════════════════════════════════════╗
║ ⚠ Post-phase QA: PARTIAL              ║
║                                        ║
║         Phase: {NN} {title}            ║
║         Plans: {N}/{M} complete        ║
╚════════════════════════════════════════╝

  Plan gate results:
    ✓ {NN-MM} -- {plan title}
    ✗ {NN-MM} -- {plan title}: {failure reason}
    ○ {NN-MM} -- {plan title} (not executed)

  ➜ Remediate failing plan gates before QA agents can spawn.
```

### Symbol Usage (Post-Phase)
- `✓` (Success/complete) -- gate passed, plan gate passed
- `✗` (Failure/error) -- gate failed, plan gate failed, spawn blocked
- `⚠` (Warning) -- partial result
- `○` (Pending/neutral) -- plan gate not executed
- `➜` (Info/arrow) -- next step / remediation
- `--` (Separator) -- between plan ID and title
- Double-line box-drawing: `╔ ═ ╗ ║ ╚ ╝` (critical_phase level per brand essentials)

## QA Gate Status Lines

Transient status output displayed while a QA gate is executing. Follows agent_spawn pattern from brand-essentials.toon. Replaced by gate result output (above sections) when complete.

### Running State

Shown while gate is actively executing. Uses diamond (◆) in-progress indicator.

```
  ◆ Running {gate-name} gate... ({Xs})
```

Gate names:
- `post-task` -- after Dev task commit
- `post-plan` -- after plan summary
- `post-phase` -- before QA agent spawn

Examples:
```
  ◆ Running post-task gate... (2s)
  ◆ Running post-plan gate... (15s)
  ◆ Running post-phase gate... (45s)
```

### Complete State

Shown briefly when gate finishes, before detailed result output renders.

```
  ✓ {gate-name} gate complete ({X.Xs})
```

Example:
```
  ✓ post-task gate complete (2.3s)
```

### Failed State

Shown briefly when gate fails, before detailed failure output renders.

```
  ✗ {gate-name} gate failed ({X.Xs})
```

Example:
```
  ✗ post-plan gate failed (18.7s)
```

### Timeout State

Shown when gate exceeds configured timeout (qa_gates.timeout_seconds).

```
  ⚠ {gate-name} gate timed out ({Xs}/{Ys} limit)
```

Example:
```
  ⚠ post-task gate timed out (30s/30s limit)
```

### Symbol Usage (Status Lines)
- `◆` (In progress) -- gate actively running
- `✓` (Success/complete) -- gate finished successfully
- `✗` (Failure/error) -- gate finished with failure
- `⚠` (Warning) -- gate timed out

## Brand-Essentials Integration

Mapping between yolo-brand-essentials.toon symbols and QA gate states.

### Symbol-to-State Mapping

| Symbol | Unicode | Brand Meaning | QA Gate Usage |
|--------|---------|---------------|---------------|
| ✓ | U+2713 | Success/complete | Gate passed, test passed, task complete |
| ✗ | U+2717 | Failure/error | Gate failed, test failed, spawn blocked |
| ◆ | U+25C6 | In progress | Gate actively running |
| ○ | U+25CB | Pending/neutral | Task blocked, gate not executed |
| ⚠ | U+26A0 | Warning | Partial result, timeout, missing infrastructure |
| ➜ | U+279C | Info/arrow | Remediation suggestion, next step |
| -- | U+2014 | Separator | Between identifiers and descriptions |

### Box-Drawing Level Mapping

| Gate Level | Box Style | Brand Category | Rationale |
|------------|-----------|----------------|-----------|
| Post-task | Single-line (┌─┐│└┘) | standard_task | Task-level, low ceremony |
| Post-plan | Single-line (┌─┐│└┘) | standard_task | Plan-level, medium ceremony |
| Post-phase | Double-line (╔═╗║╚╝) | critical_phase | Phase-level, high ceremony |

Note: Post-task pass state uses no box (single-line output only) to minimize noise during rapid task execution.

## Quick-Reference Matrix

Lookup table: find the output template by gate level and result state.

| Gate Level | PASS | FAIL | PARTIAL | WARN |
|------------|------|------|---------|------|
| Post-task | Single line: `✓ Post-task QA: N tests passed (Xs)` | Multi-line: failures list + remediation | `⚠` no relevant tests | `⚠` missing infrastructure |
| Post-plan | Single-line box with metrics | Single-line box + blocking issues | Single-line box + per-task checklist | N/A |
| Post-phase | Double-line box with metrics | Double-line box + blocking gates | Double-line box + per-plan checklist | N/A |
| Status line | `✓ gate complete` | `✗ gate failed` | N/A | `⚠ gate timed out` |

## Rules

1. **No ANSI color codes** -- not rendered in Claude Code model output (brand rule 1)
2. **No Nerd Font glyphs** -- not universally available (brand rule 2)
3. **Content readable without box-drawing** -- degrade gracefully (brand rule 3)
4. **Lines under 80 chars inside boxes** -- visual consistency (brand rule 4)
5. **Consistent symbol usage** -- never use ✓ for failure or ✗ for success (brand rule 5)
6. **Two-part error messages** -- every failure output has problem + remediation (stop_message pattern)
7. **Metrics use left-padded labels** -- 14-char left-pad per metrics_block pattern
