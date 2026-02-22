# Mode: Scope

**Guard:** PROJECT.md exists but `phase_count=0`.

**Steps:**
1. Load context: PROJECT.md, REQUIREMENTS.md. If `.yolo-planning/codebase/META.md` exists, read ARCHITECTURE.md and CONCERNS.md (whichever exist) from `.yolo-planning/codebase/`.
2. If $ARGUMENTS (excl. flags) provided, use as scope. Else ask: "What do you want to build?" Show uncovered requirements as suggestions.
3. Decompose into 3-5 phases (name, goal, success criteria). Each independently plannable. Map REQ-IDs.
4. Write ROADMAP.md. Create `.yolo-planning/phases/{NN}-{slug}/` dirs.
5. Update STATE.md: Phase 1, status "Pending planning". Do NOT write next-action suggestions (e.g. "Run /yolo:vibe --plan 1") into the Todos section -- those are ephemeral display output from suggest-next, not persistent state.
6. Display "Scoping complete. {N} phases created." STOP -- do not auto-continue to planning.
