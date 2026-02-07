---
description: Audit the active milestone for shipping readiness -- checks phase completion, plan execution, and verification status.
argument-hint: [--fix]
allowed-tools: Read, Glob, Grep, Bash
---

# VBW Audit $ARGUMENTS

## Context

Working directory: `!`pwd``

Active milestone:
```
!`cat .planning/ACTIVE 2>/dev/null || echo "No active milestone (single-milestone mode)"`
```

Config:
```
!`cat .planning/config.json 2>/dev/null || echo "No config found"`
```

## Guard

1. **Not initialized:** If `.planning/` directory doesn't exist, STOP: "Run /vbw:init first."

2. **No milestones or roadmap:** If `.planning/ACTIVE` does not exist AND `.planning/ROADMAP.md` does not exist, STOP: "No milestones configured and no roadmap found. Run /vbw:init or /vbw:milestone first."

## Steps

### Step 1: Resolve milestone context

Determine which milestone to audit:

- If `.planning/ACTIVE` exists: read its content to get the active slug. Set:
  - ROADMAP_PATH = `.planning/{slug}/ROADMAP.md`
  - PHASES_DIR = `.planning/{slug}/phases/`
  - STATE_PATH = `.planning/{slug}/STATE.md`
  - MILESTONE_NAME = slug (used in report header)
- If `.planning/ACTIVE` does not exist (single-milestone mode): Set:
  - ROADMAP_PATH = `.planning/ROADMAP.md`
  - PHASES_DIR = `.planning/phases/`
  - STATE_PATH = `.planning/STATE.md`
  - MILESTONE_NAME = "default"

Verify ROADMAP_PATH exists. If not, STOP: "Roadmap not found at {ROADMAP_PATH}."

### Step 2: Run audit checks

Perform six checks against the active milestone. For each check, record: check name, status (PASS/WARN/FAIL), and evidence (file path or detail).

**Check 1: Roadmap completeness**
Parse ROADMAP_PATH. Every phase listed must have a goal or description -- not "TBD", "To be planned", or empty. A phase with a real goal = PASS for that phase. Any phase with a placeholder goal = FAIL.

**Check 2: Phase planning**
For each phase in the roadmap, check that at least one `*-PLAN.md` file exists in its phase directory under PHASES_DIR. Use Glob: `PHASES_DIR/{NN}-*/*-PLAN.md`. Every phase must have at least one plan file. Missing plans = FAIL.

**Check 3: Plan execution**
For each `*-PLAN.md` file found in Check 2, verify a corresponding `*-SUMMARY.md` exists (same prefix number). A PLAN without a SUMMARY means that plan was never executed. All plans must have summaries for PASS. Any missing = FAIL.

**Check 4: Execution status**
For each `*-SUMMARY.md` found, read its frontmatter. Check the `status` field. All must be "complete" for PASS. Any "partial" or "failed" status = FAIL.

**Check 5: Verification status**
Check for `VERIFICATION.md` files in phase directories under PHASES_DIR. If they exist, read their result field. All must be "PASS" for this check to PASS. Missing verifications = WARN (not required but recommended). Failed verifications = FAIL.

**Check 6: Requirements coverage**
If `.planning/REQUIREMENTS.md` exists at the project root, cross-reference the milestone's roadmap requirements (requirement IDs mentioned in phase details) against those defined in REQUIREMENTS.md. Flag any requirement IDs referenced in the roadmap that do not exist in REQUIREMENTS.md. All referenced requirements found = PASS. Unknown references = WARN.

### Step 3: Compute audit result

Determine the overall result from the six checks:

- **PASS:** All six checks are PASS (green light for shipping)
- **WARN:** No FAIL checks, but one or more WARN checks (non-critical issues -- missing verifications, unknown requirement references)
- **FAIL:** One or more checks are FAIL (critical issues -- incomplete plans, failed executions, placeholder goals)

### Step 4: Handle --fix flag

Parse $ARGUMENTS for the `--fix` flag.

If `--fix` is present and there are fixable issues, display command suggestions:

- Missing verifications (WARN): suggest `/vbw:qa {N}` for each unverified phase
- Incomplete plans (FAIL): suggest `/vbw:build {N}` for phases with unexecuted plans
- Placeholder goals (FAIL): suggest editing the roadmap manually
- Failed executions (FAIL): suggest re-running `/vbw:build {N}` for failed phases

Display suggestions only -- do not auto-fix. These are recommendations for the user.

If `--fix` is not present: skip this step.

### Step 5: Present audit report

Display the audit report using brand formatting from @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand.md:

```
╔═══════════════════════════════════════════╗
║  Milestone Audit: {MILESTONE_NAME}       ║
║  Result: {PASS|WARN|FAIL}                ║
╚═══════════════════════════════════════════╝

  Checks:
    {symbol} Roadmap completeness       {evidence}
    {symbol} Phase planning             {N}/{N} phases planned
    {symbol} Plan execution             {N}/{N} plans complete
    {symbol} Execution status           {N}/{N} summaries complete
    {symbol} Verification coverage      {N}/{M} phases verified
    {symbol} Requirements coverage      {N} requirements mapped

  {If PASS:}
  ➜ Next Up
    /vbw:ship -- Ship this milestone

  {If WARN:}
  ➜ Recommendations
    /vbw:qa {N} -- Verify Phase {N}

  {If FAIL:}
  ✗ Milestone is not ready to ship
    /vbw:build {N} -- Complete Phase {N}
```

Use ✓ for PASS checks, ⚠ for WARN checks, ✗ for FAIL checks.

If `--fix` was provided and suggestions were generated in Step 4, append them after the check list under a "Fix Suggestions:" heading.

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand.md for all visual formatting:
- Double-line box for the audit report header (Phase Banner template)
- Semantic symbols: ✓ PASS, ⚠ WARN, ✗ FAIL
- Metrics Block formatting for check results
- Next Up Block (template 7) for navigation based on result
- No ANSI color codes
- Lines under 80 characters inside boxes
