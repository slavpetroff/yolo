# Mode: Phase Mutation (Add / Insert / Remove)

## Add Phase

**Guard:** Initialized. Requires phase name in $ARGUMENTS.
Missing name: STOP "Usage: `/yolo:vibe --add <phase-name>`"

**Steps:**
1. Resolve context: ACTIVE -> milestone-scoped paths, otherwise defaults.
2. **Codebase context:** If `.yolo-planning/codebase/META.md` exists, read ARCHITECTURE.md and CONCERNS.md (whichever exist) from `.yolo-planning/codebase/`. Use this to inform phase goal scoping and identify relevant modules/services.
3. Parse args: phase name (first non-flag arg), --goal (optional), slug (lowercase hyphenated).
4. Next number: highest in ROADMAP.md + 1, zero-padded.
5. Create dir: `mkdir -p {PHASES_DIR}/{NN}-{slug}/`
6. **Problem research (conditional):** If $ARGUMENTS contain a problem description (bug report, feature request, multi-sentence intent) rather than just a bare phase name:
   - Research the problem directly in the codebase using your tools.
   - Use your findings to write an informed phase goal and success criteria in ROADMAP.md. Write these structured findings to `{phase-dir}/{NN}-RESEARCH.md`.
   - On failure: log warning, write phase goal from $ARGUMENTS alone. Do not block.
   - **This eliminates duplicate research** -- Plan mode step 3 checks for existing RESEARCH.md and skips research if found.
   - **Subagent isolation:** For broad codebase exploration (3+ queries), use the Task tool with an Explore subagent to keep the orchestrator's context focused on phase scoping.
7. Update ROADMAP.md: append phase list entry, append Phase Details section (using research findings if available), add progress row.
8. Present: Phase Banner with milestone, position, goal. Checklist for roadmap update + dir creation. Next Up: `/yolo:vibe --discuss` or `/yolo:vibe --plan`.

## Insert Phase

**Guard:** Initialized. Requires position + name.
Missing args: STOP "Usage: `/yolo:vibe --insert <position> <phase-name>`"
Invalid position (out of range 1 to max+1): STOP with valid range.
Inserting before completed phase: WARN + confirm.

**Steps:**
1. Resolve context: ACTIVE -> milestone-scoped paths, otherwise defaults.
2. **Codebase context:** If `.yolo-planning/codebase/META.md` exists, read ARCHITECTURE.md and CONCERNS.md (whichever exist) from `.yolo-planning/codebase/`. Use this to inform phase goal scoping and identify relevant modules/services.
3. Parse args: position (int), phase name, --goal (optional), slug (lowercase hyphenated).
4. Identify renumbering: all phases >= position shift up by 1.
5. Renumber dirs in REVERSE order: rename dir {NN}-{slug} -> {NN+1}-{slug}, rename internal PLAN/SUMMARY files, update `phase:` frontmatter, update `depends_on` references.
6. Create dir: `mkdir -p {PHASES_DIR}/{NN}-{slug}/`
7. **Problem research (conditional):** Same as Add Phase step 6 -- if $ARGUMENTS contain a problem description, research the codebase directly. The **orchestrator** writes `{phase-dir}/{NN}-RESEARCH.md`. This prevents Plan mode from duplicating the research.
8. Update ROADMAP.md: insert new phase entry + details at position (using research findings if available), renumber subsequent entries/headers/cross-refs, update progress table.
9. Present: Phase Banner with renumber count, phase changes, file checklist, Next Up.

## Remove Phase

**Guard:** Initialized. Requires phase number.
Missing number: STOP "Usage: `/yolo:vibe --remove <phase-number>`"
Not found: STOP "Phase {N} not found."
Has work (PLAN.md or SUMMARY.md): STOP "Phase {N} has artifacts. Remove plans first."
Completed ([x] in roadmap): STOP "Cannot remove completed Phase {N}."

**Steps:**
1. Resolve context: ACTIVE -> milestone-scoped paths, otherwise defaults.
2. Parse args: extract phase number, validate, look up name/slug.
3. Confirm: display phase details, ask confirmation. Not confirmed -> STOP.
4. Remove dir: `rm -rf {PHASES_DIR}/{NN}-{slug}/`
5. Renumber FORWARD: for each phase > removed: rename dir {NN} -> {NN-1}, rename internal files, update frontmatter, update depends_on.
6. Update ROADMAP.md: remove phase entry + details, renumber subsequent, update deps, update progress table.
7. Present: Phase Banner with renumber count, phase changes, file checklist, Next Up.
