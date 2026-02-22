# Mode: Archive

**Guard:** Initialized, roadmap exists.
No roadmap: STOP "No milestones configured. Run `/yolo:vibe` to bootstrap."
No work (no SUMMARY.md files): STOP "Nothing to ship."

**Pre-gate audit (unless --skip-audit or --force):**
Run 6-point audit matrix:
1. Roadmap completeness: every phase has real goal (not TBD/empty)
2. Phase planning: every phase has >= 1 PLAN.md
3. Plan execution: every PLAN.md has SUMMARY.md
4. Execution status: every SUMMARY.md has `status: complete`
5. Verification: VERIFICATION.md files exist + PASS. Missing=WARN, failed=FAIL
6. Requirements coverage: req IDs in roadmap exist in REQUIREMENTS.md
FAIL -> STOP with remediation suggestions. WARN -> proceed with warnings.

**Steps:**
1. Resolve context: ACTIVE -> milestone-scoped paths. No ACTIVE -> SLUG="default", root paths.
2. Parse args: --tag=vN.N.N (custom tag), --no-tag (skip), --force (skip audit).
3. Compute summary: from ROADMAP (phases), SUMMARY.md files (tasks/commits/deviations), REQUIREMENTS.md (satisfied count).
4. **Rolling summary (conditional):** If `v3_rolling_summary=true` in config:
   ```bash
   yolo rolling-summary \
     .yolo-planning/phases .yolo-planning/ROLLING-CONTEXT.md 2>/dev/null || true
   ```
   Compiles final rolling context before artifacts move to milestones/. Fail-open.
   When `v3_rolling_summary=false`: skip.
5. Archive: `mkdir -p .yolo-planning/milestones/`. Move roadmap, state, phases to milestones/{SLUG}/. Write SHIPPED.md. Delete stale RESUME.md.
5b. **Persist project-level state:** After archiving, run:
   ```bash
   yolo persist-state \
     .yolo-planning/milestones/{SLUG}/STATE.md .yolo-planning/STATE.md "{PROJECT_NAME}"
   ```
   This extracts project-level sections (Todos, Decisions, Skills, Blockers, Codebase Profile) from the archived STATE.md and writes a fresh root STATE.md. Milestone-specific sections (Current Phase, Activity Log, Phase Status) stay in the archive only. Fail-open: if the script fails, warn but continue.
6. Planning commit boundary (conditional):
   ```bash
   "$HOME/.cargo/bin/yolo" planning-git commit-boundary "archive milestone {SLUG}" .yolo-planning/config.json
   ```
   Run this BEFORE branch merge/tag so shipped planning state is committed.
7. Git branch merge: if `milestone/{SLUG}` branch exists, merge --no-ff. Conflict -> abort, warn. No branch -> skip.
8. Git tag: unless --no-tag, `git tag -a {tag} -m "Shipped milestone: {name}"`. Default: `milestone/{SLUG}`.
9. Update ACTIVE: remaining milestones -> set ACTIVE to first. None -> remove ACTIVE.
10. Regenerate CLAUDE.md: update Active Context, remove shipped refs. Preserve non-YOLO content -- only replace YOLO-managed sections, keep user's own sections intact.
11. Present: Phase Banner with metrics (phases, tasks, commits, requirements, deviations), archive path, tag, branch status, memory status. Run `"$HOME/.cargo/bin/yolo" suggest-next vibe`.
