---
name: qa
description: Run deep verification on completed phase work via Lead-dispatched QA hierarchy.
argument-hint: [phase-number] [--tier=quick|standard|deep] [--effort=thorough|balanced|fast|turbo]
allowed-tools: Read, Write, Bash, Glob, Grep
disable-model-invocation: true
---

# YOLO QA: $ARGUMENTS

## Context

Working directory: `!`pwd``

Current state:
```
!`head -40 .yolo-planning/STATE.md 2>/dev/null || echo "No state found"`
```

Config: Pre-injected by SessionStart hook. Override with --effort flag.

Phase directories:
```
!`ls .yolo-planning/phases/ 2>/dev/null || echo "No phases directory"`
```

Phase state:
```
!`bash ${CLAUDE_PLUGIN_ROOT}/scripts/phase-detect.sh 2>/dev/null || echo "phase_detect_error=true"`
```

## Guard

- Guard: no .yolo-planning/ -> STOP "YOLO is not set up yet. Run /yolo:init to get started."
- **Auto-detect phase** (no explicit number): Phase detection is pre-computed in Context above. Use `next_phase` and `next_phase_slug` for the target phase. To find the first phase needing QA: scan phase dirs for first with `*-SUMMARY.md` but no `*-VERIFICATION.md` (phase-detect.sh provides the base phase state; QA-specific detection requires this additional check). Found: announce "Auto-detected Phase {N} ({slug})". All verified: STOP "All phases verified. Specify: `/yolo:qa N`"
- Phase not built (no SUMMARYs): STOP "Phase {N} has no completed plans. Run /yolo:go first."

Note: Continuous verification handled by hooks. This command is for deep, on-demand verification only.

## Steps

1. **Resolve tier:** Priority: --tier flag > --effort flag > config default > Standard. Effort mapping: turbo=skip (exit "QA skipped in turbo mode"), fast=quick, balanced=standard, thorough=deep. Read `${CLAUDE_PLUGIN_ROOT}/references/effort-profile-{profile}.md`. Context overrides: >15 requirements or last phase before ship -> Deep.
2. **Resolve milestone:** If .yolo-planning/ACTIVE exists, use milestone-scoped paths.
3. **Spawn Lead:**
- Resolve models (lead, qa, qa-code) via `resolve-agent-model.sh` with config.json + model-profiles.json. Abort on failure.
- Display: `◆ Spawning Lead (${LEAD_MODEL}) for QA dispatch...`
- Spawn yolo-lead as subagent via Task tool. **Add `model: "${LEAD_MODEL}"` parameter.**
```
QA dispatch coordinator. Phase: {N}. Tier: {tier}. QA model: ${QA_MODEL}. QA-Code model: ${QA_CODE_MODEL}.
Plans: {paths to plan.jsonl files}. Summaries: {paths to summary.jsonl files}.
Phase success criteria: {from ROADMAP.md}. Convention baseline: .yolo-planning/codebase/CONVENTIONS.md (if exists).
Verification protocol: ${CLAUDE_PLUGIN_ROOT}/references/verification-protocol.md.
(1) Dispatch QA Lead (yolo-qa, model: QA_MODEL): plan-level verification -- must_haves, done criteria, requirement traceability. Provide plan.jsonl + summary.jsonl + .ctx-qa.toon context. QA Lead returns qa_result schema.
(2) Dispatch QA Code (yolo-qa-code, model: QA_CODE_MODEL): code-level verification -- tests, lint, coverage, regression, patterns. Provide summary.jsonl (file list) + test-plan.jsonl + .ctx-qa-code.toon context. QA Code returns qa_code_result schema.
(3) Synthesize: combine qa_result + qa_code_result into unified verdict: PASS (both pass), PARTIAL (one partial), FAIL (any fail).
(4) Write {phase-dir}/{phase}-VERIFICATION.md with frontmatter: phase, tier, result, passed, failed, total, date. Body: combined QA output.
(5) Remediation (if FAIL or PARTIAL with critical findings): spawn yolo-senior (resolve model first) to re-spec failing items; Senior spawns yolo-dev to fix; then re-dispatch QA for verification. Max 2 remediation cycles. After 2nd fail: escalate to Architect via escalation schema.
(6) Return: unified result, path to VERIFICATION.md.
```
4. **Present:** Per @${CLAUDE_PLUGIN_ROOT}/references/yolo-brand-essentials.toon -- single-line box:
```
┌──────────────────────────────────────────┐
│  Phase {N}: {name} -- Verified           │
└──────────────────────────────────────────┘

  Tier:     {quick|standard|deep}
  Result:   {✓ PASS | ✗ FAIL | ◆ PARTIAL}
  Checks:   {passed}/{total}
  Failed:   {list or "None"}

  Report:   {path to VERIFICATION.md}

```
Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/suggest-next.sh qa {result}` and display.

## Escalation and Remediation

- QA Lead -> Lead: QA Lead reports plan-level findings via qa_result schema. QA Lead NEVER contacts Architect or user.
- QA Code -> Lead: QA Code reports code-level findings via qa_code_result schema. QA Code NEVER modifies source code.
- Lead synthesis: Lead combines both QA reports into unified PASS/FAIL/PARTIAL verdict.
- Remediation chain (FAIL/PARTIAL with critical): Lead assigns Senior to re-spec failing items -> Senior spawns Dev to fix -> Lead re-dispatches QA to verify fix. Max 2 cycles.
- Escalation on 3rd failure: Lead escalates to Architect via escalation schema for design re-evaluation.
- No QA agent contacts Architect directly. All findings route through Lead.

## Output Format

Per @${CLAUDE_PLUGIN_ROOT}/references/yolo-brand-essentials.toon -- single-line box, ✓/✗/◆ symbols, Next Up, no ANSI.
