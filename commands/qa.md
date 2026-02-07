---
description: Run standalone verification on completed phase work using the QA agent.
argument-hint: <phase-number> [--tier=quick|standard|deep] [--effort=thorough|balanced|fast|turbo]
allowed-tools: Read, Write, Bash, Glob, Grep
---

# VBW QA: $ARGUMENTS

## Context

Working directory: `!`pwd``

Current state:
```
!`cat .planning/STATE.md 2>/dev/null || echo "No state found"`
```

Current effort setting:
```
!`cat .planning/config.json 2>/dev/null || echo "No config found"`
```

Phase directory contents:
```
!`ls .planning/phases/ 2>/dev/null || echo "No phases directory"`
```

## Guard

1. **Not initialized:** If .planning/ directory doesn't exist, STOP: "Run /vbw:init first."
2. **Missing phase number:** If $ARGUMENTS doesn't include a phase number (integer), STOP: "Usage: /vbw:qa <phase-number> [--tier=quick|standard|deep] [--effort=thorough|balanced|fast|turbo]"
3. **Phase not built:** If no SUMMARY.md files exist in the phase directory (`.planning/phases/{phase-dir}/`), STOP: "Phase {N} has no completed plans. QA verifies completed work -- run /vbw:build {N} first."

## Steps

### Step 1: Parse arguments

Extract arguments from $ARGUMENTS:

- **Phase number** (required): integer identifying which phase to verify (e.g., `3` matches `.planning/phases/03-*`)
- **--tier** (optional): explicit tier override -- `quick`, `standard`, or `deep`. Takes precedence over effort-based selection.
- **--effort** (optional): effort override -- `thorough`, `balanced`, `fast`, `turbo`. Maps to QA tier via effort-profiles.md.

**Tier resolution (in priority order):**

1. If `--tier` is provided, use that tier directly
2. If `--effort` is provided, map to tier using the auto-selection heuristic from `${CLAUDE_PLUGIN_ROOT}/references/verification-protocol.md`:

   | Effort | QA Tier |
   |--------|---------|
   | turbo | No QA (display "QA skipped in turbo mode" and exit) |
   | fast | Quick |
   | balanced | Standard |
   | thorough | Deep |

3. If neither `--tier` nor `--effort` is provided, use the default effort from `.planning/config.json` mapped via the table above. If no config exists, default to Standard tier.

**Context overrides (applied after effort-based selection):**

- Read the phase section from ROADMAP.md and count requirement IDs. If >15 requirements, override to Deep tier.
- If this is the last phase before ship (final unchecked phase in ROADMAP.md), override to Deep tier.

Store the resolved `ACTIVE_TIER` for use in QA spawning.

### Step 2: Resolve milestone context

If `.planning/ACTIVE` exists (multi-milestone mode):
- Set ACTIVE_SLUG to the content of `.planning/ACTIVE`
- Set ROADMAP_PATH to `.planning/{ACTIVE_SLUG}/ROADMAP.md`
- Set PHASES_DIR to `.planning/{ACTIVE_SLUG}/phases/`

If `.planning/ACTIVE` does NOT exist (single-milestone mode):
- Set ROADMAP_PATH to `.planning/ROADMAP.md`
- Set PHASES_DIR to `.planning/phases/`

Use the resolved paths for all subsequent steps.

### Step 3: Gather verification context

Collect all inputs the QA agent needs:

1. **Plan files:** Use Glob to find all `*-PLAN.md` files in `{PHASES_DIR}/{phase-dir}/`
2. **Summary files:** Use Glob to find all `*-SUMMARY.md` files in `{PHASES_DIR}/{phase-dir}/`
3. **Phase requirements:** Read the phase section from ROADMAP_PATH -- extract success criteria and requirement IDs
4. **Convention baseline:** Check if `.planning/codebase/CONVENTIONS.md` exists. If so, note its path for QA reference.
5. **Active tier:** The tier resolved in Step 1

Read each PLAN.md and SUMMARY.md file to have their content available for passing to the QA agent.

### Step 4: Spawn QA agent

Use the Task tool spawning protocol:

1. Read `${CLAUDE_PLUGIN_ROOT}/agents/vbw-qa.md` using the Read tool
2. Extract the body content (everything after the closing `---` of the YAML frontmatter)
3. Use the **Task tool** to spawn the QA agent:
   - `prompt`: The extracted body content of vbw-qa.md (this becomes the subagent's system prompt)
   - `description`: Include all gathered context:
     - Phase number and phase directory path
     - Full content of each PLAN.md file in the phase
     - Full content of each SUMMARY.md file in the phase
     - Phase success criteria from ROADMAP.md
     - The active tier: "Verification tier: {ACTIVE_TIER}"
     - Convention file path (if CONVENTIONS.md exists): "Convention baseline: {path}"
     - Reference instruction: "Reference ${CLAUDE_PLUGIN_ROOT}/references/verification-protocol.md for tier definitions and verification methodology."
     - Output instruction: "Return verification findings as structured text following the Output Format defined in your protocol. Do not write any files."

### Step 5: Persist results

QA returns structured text findings (QA is read-only per Phase 2 decision). This command persists the results:

1. Parse the QA output to extract:
   - Result (PASS/FAIL/PARTIAL) from the Summary section
   - Check counts (passed, failed, total)

2. Write the VERIFICATION.md file to `{PHASES_DIR}/{phase-dir}/{phase}-VERIFICATION.md` with:
   - YAML frontmatter:
     ```yaml
     ---
     phase: {phase-id}
     tier: {ACTIVE_TIER}
     result: {PASS|FAIL|PARTIAL}
     passed: {N}
     failed: {N}
     total: {N}
     date: {YYYY-MM-DD}
     ---
     ```
   - QA output text as the document body

### Step 6: Present verification summary

Display using brand formatting from `${CLAUDE_PLUGIN_ROOT}/references/vbw-brand.md`:

```
┌──────────────────────────────────────────┐
│  Phase {N}: {name} -- Verified           │
└──────────────────────────────────────────┘

  Tier:     {quick|standard|deep}
  Result:   {PASS|PARTIAL|FAIL}
  Checks:   {passed}/{total}
  Failed:   {list or "None"}

  Report:   .planning/phases/{dir}/{phase}-VERIFICATION.md

➜ Next Up
  /vbw:build {N+1} -- Build the next phase (if PASS)
  /vbw:fix "{issue}" -- Fix a failing check (if FAIL/PARTIAL)
```

Use single-line box for the phase banner (sub-phase level operation per vbw-brand.md).

Use semantic symbols in the Result line:
- ✓ for PASS
- ✗ for FAIL
- ◆ for PARTIAL

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand.md for all visual formatting:
- Single-line box for the verification banner (sub-phase level operation)
- Metrics Block formatting for tier/result/checks display
- Semantic symbols: ✓ PASS, ✗ FAIL, ◆ PARTIAL
- Next Up Block (template 7) for suggested next actions
- No ANSI color codes
- Lines under 80 characters inside boxes
