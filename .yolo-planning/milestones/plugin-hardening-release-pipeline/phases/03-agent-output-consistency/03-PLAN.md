---
phase: "03"
plan: "03"
title: "SUMMARY naming enforcement in agent templates"
wave: 1
depends_on: []
must_haves:
  - "Dev agent template explicitly derives filename from PLAN.md frontmatter phase and plan fields"
  - "SKILL.md Step 3c matches the explicit derivation"
  - "Filename pattern is {phase-dir}/{PP}-{NN}-SUMMARY.md where PP=phase, NN=plan from frontmatter"
---

# Plan 03: SUMMARY naming enforcement in agent templates

Strengthen the dev agent template and execute-protocol SKILL.md to explicitly derive SUMMARY filename from PLAN.md frontmatter `phase` and `plan` fields, preventing naming mismatches.

## Task 1

**Files:** `agents/yolo-dev.md`

**What to do:**

1. In Stage 5 "Write SUMMARY.md" (line 42-45), replace the current implicit template reference with an explicit derivation rule. Change the paragraph to:

   > After completing ALL tasks in the current plan, read the PLAN.md frontmatter `phase` and `plan` fields. Derive the SUMMARY filename as `{phase-dir}/{phase}-{plan}-SUMMARY.md` (e.g., phase="03", plan="02" produces `03-02-SUMMARY.md`). Write this file using the template at `templates/SUMMARY.md`. Include YAML frontmatter with phase, plan, title, status, completed date, tasks_completed, tasks_total, commit_hashes, and deviations. Fill `## What Was Built`, `## Files Modified`, and `## Deviations` sections.

2. Keep the existing "This is mandatory" line unchanged.

## Task 2

**Files:** `skills/execute-protocol/SKILL.md` (at plugin root `/Users/slavpetroff/.claude/plugins/cache/yolo-marketplace/yolo/2.9.5/`)

**What to do:**

1. In Step 3c "SUMMARY.md verification gate" (around line 708), update the instruction to match the explicit derivation. Change:

   > After all tasks in a plan complete, the Dev agent MUST write `{phase-dir}/{NN-MM}-SUMMARY.md` using the template at `templates/SUMMARY.md`.

   To:

   > After all tasks in a plan complete, the Dev agent MUST read the PLAN.md frontmatter `phase` and `plan` fields, then write `{phase-dir}/{phase}-{plan}-SUMMARY.md` (e.g., phase="03", plan="02" produces `03-02-SUMMARY.md`) using the template at `templates/SUMMARY.md`.

2. In the gate checks list (around line 727), update check 1 from:

   > File exists at `{phase-dir}/{NN-MM}-SUMMARY.md`

   To:

   > File exists at `{phase-dir}/{phase}-{plan}-SUMMARY.md` (derived from PLAN.md frontmatter)

## Task 3

**Files:** `agents/yolo-dev.md`, `skills/execute-protocol/SKILL.md`

**What to do:**

1. Review both files to confirm the naming pattern is consistent: `{phase}-{plan}-SUMMARY.md` derived from PLAN.md frontmatter in both locations.
2. Verify no other references to the old `{NN-MM}-SUMMARY.md` pattern exist in either file that would conflict.

**Commit:** `fix(03-03): enforce explicit SUMMARY filename derivation from PLAN.md frontmatter`
