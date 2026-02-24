---
phase: "01"
plan: "04"
title: "Verdict parsing fails closed"
wave: 1
depends_on: []
must_haves:
  - "REQ-04: Reviewer verdict parse failure triggers STOP not conditional"
  - "REQ-04: QA report parse failure triggers STOP not fallback to CLI"
---

# Plan 04: Verdict parsing fails closed

## Goal

Both verdict parsing blocks in the execute protocol are currently fail-open:
- **Reviewer** (SKILL.md lines 137, 149-152): When the reviewer agent output can't be parsed, the fallback is `AGENT_VERDICT="conditional"` with a warning finding. This allows execution to proceed with a potentially broken review.
- **QA** (SKILL.md lines 825, 838-840): When the QA agent output can't be parsed, the fallback uses CLI results unchanged with a warning. This silently drops the agent's (possibly critical) findings.

Both must fail closed: on parse failure, STOP with a clear error message instead of silently continuing.

## Tasks

### Task 1: Change Reviewer verdict parse failure to STOP

**File:** `skills/execute-protocol/SKILL.md`

**What to change:**
Replace the fail-open fallback in the Reviewer verdict parsing section (around lines 137, 149-153).

Current code (lines 149-153):
```bash
if [ -z "$AGENT_VERDICT" ]; then
  AGENT_VERDICT="conditional"
  CURRENT_FINDINGS='[{"id":"parse-fail","severity":"medium","file":"","title":"Unparseable reviewer verdict","description":"Reviewer agent did not produce a structured verdict. Treating as conditional.","suggestion":"Review agent output manually."}]'
fi
```

Replace with:
```bash
if [ -z "$AGENT_VERDICT" ]; then
  echo "✗ Reviewer verdict parse failure — agent output did not contain a valid VERDICT line."
  echo "  Raw output (last 20 lines):"
  echo "$AGENT_OUTPUT" | tail -20
  echo ""
  echo "  Action: Check reviewer agent definition or re-run with --review"
  VERDICT="reject"
  # STOP — do not proceed to execution. Fail-closed on unparseable verdict.
  # Log the parse failure for diagnostics
  "$HOME/.cargo/bin/yolo" log-event review_parse_failure {phase} plan={NN-MM} 2>/dev/null || true
  # Enter the reject handling path (which will either loop or stop at max cycles)
fi
```

Also update the prose description on line 137 from:
```
- If parsing fails (agent didn't follow format): treat as `conditional` with a warning finding about unparseable verdict
```
To:
```
- If parsing fails (agent didn't follow format): treat as `reject` and STOP — fail-closed on unparseable verdict
```

**Why:** A reviewer that produces garbage output should not result in "conditional" (which allows execution to proceed). It should be treated as a reject, which triggers the review feedback loop or stops at max cycles. This is fail-closed behavior.

### Task 2: Change QA report parse failure to STOP

**File:** `skills/execute-protocol/SKILL.md`

**What to change:**
Replace the fail-open fallback in the QA report parsing section (around lines 825, 838-841).

Current code (lines 825):
```
- If parsing fails (agent didn't follow format): treat as if agent returned CLI results unchanged, with a warning about unparseable report
```

Replace with:
```
- If parsing fails (agent didn't follow format): STOP with error — fail-closed on unparseable QA report. Do not silently fall back to CLI results, as the agent may have found critical issues that would be lost.
```

Current code (lines 838-841):
```bash
if [ -z "$AGENT_PASSED" ]; then
  echo "Warning: QA agent report unparseable — using CLI results"
  QA_REPORT="$CLI_QA_REPORT"
fi
```

Replace with:
```bash
if [ -z "$AGENT_PASSED" ]; then
  echo "✗ QA report parse failure — agent output did not contain a valid 'passed:' field."
  echo "  Raw output (last 20 lines):"
  echo "$AGENT_OUTPUT" | tail -20
  echo ""
  echo "  Action: Check QA agent definition or re-run with --qa"
  # Fail-closed: treat unparseable report as a failure
  QA_REPORT='{"passed": false, "remediation_eligible": false, "checks": [{"name": "qa-parse-failure", "status": "fail", "fixable_by": "manual", "evidence": "QA agent output could not be parsed. Human review required."}]}'
  # Log the parse failure for diagnostics
  "$HOME/.cargo/bin/yolo" log-event qa_parse_failure {phase} plan={NN-MM} 2>/dev/null || true
fi
```

**Why:** Silently falling back to CLI results when the QA agent can't be parsed loses any critical findings the agent may have discovered. The fail-closed approach treats parse failure as a `fixable_by: "manual"` HARD STOP, which forces human review of the agent's raw output.

### Task 3: Add protocol-level test for fail-closed verdict parsing

**File:** `tests/unit/verdict-parse-failclosed.bats` (new file)

**What to change:**
Create a test file that:
1. Greps `skills/execute-protocol/SKILL.md` for the reviewer parse failure block and asserts it does NOT contain `conditional` as the fallback verdict
2. Greps `skills/execute-protocol/SKILL.md` for the reviewer parse failure block and asserts it contains `reject` as the fallback
3. Greps `skills/execute-protocol/SKILL.md` for the QA parse failure block and asserts it does NOT contain `"using CLI results"` as the fallback
4. Greps `skills/execute-protocol/SKILL.md` for the QA parse failure block and asserts it contains `"passed": false` in the fallback report
5. Verifies both parse failure paths log an event (`review_parse_failure` and `qa_parse_failure`)

**Why:** Prevents regression where someone re-introduces fail-open behavior in verdict parsing.
