# Mode: Assumptions

**Guard:** Initialized, phase exists in roadmap.
**Phase auto-detection:** Same as Discuss mode -- first phase without `*-CONTEXT.md`. All discussed: STOP "All phases discussed. Specify: `/yolo:vibe --discuss N`"

**Steps:**
1. Load context: ROADMAP.md, REQUIREMENTS.md, PROJECT.md, STATE.md, CONTEXT.md (if exists), codebase signals.
2. Generate 5-10 assumptions by impact: scope (included/excluded), technical (implied approaches), ordering (sequencing), dependency (prior phases), user preference (defaults without stated preference).
3. Gather feedback per assumption: "Confirm, correct, or expand?" Confirm=proceed, Correct=user provides answer, Expand=user adds nuance.
4. Present grouped by status (confirmed/corrected/expanded). This mode does NOT write files. For persistence: "Run `/yolo:vibe --discuss {N}` to capture as CONTEXT.md." Run `"$HOME/.cargo/bin/yolo" suggest-next vibe`.
