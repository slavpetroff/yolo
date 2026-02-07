---
description: Complete and archive the active milestone -- archive state, tag repository, clear milestone workspace.
argument-hint: [--tag=vN.N.N] [--no-tag] [--force]
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# VBW Ship $ARGUMENTS

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

Git status:
```
!`git status --short 2>/dev/null || echo "Not a git repository"`
```

## Guard

1. **Not initialized:** If `.planning/` directory doesn't exist, STOP: "Run /vbw:init first."

2. **No milestones or roadmap:** If `.planning/ACTIVE` does not exist AND `.planning/ROADMAP.md` does not exist, STOP: "No milestones configured and no roadmap found. Run /vbw:init or /vbw:milestone first."

3. **Audit not passed:** If `--force` is NOT present in $ARGUMENTS, run the same audit logic as /vbw:audit (checks 1-6 from audit.md). If the audit result is FAIL, STOP: "Milestone audit failed. Run /vbw:audit for details, or use --force to ship anyway."

4. **No completed work:** If the milestone has no phase directories or no SUMMARY.md files (no completed work), STOP: "Nothing to ship. Add and complete phases first."

## Steps

### Step 1: Resolve milestone context

Determine which milestone to ship:

- If `.planning/ACTIVE` exists: read its content to get the active slug. Set:
  - SLUG = content of ACTIVE file
  - MILESTONE_DIR = `.planning/{SLUG}/`
  - ROADMAP_PATH = `.planning/{SLUG}/ROADMAP.md`
  - PHASES_DIR = `.planning/{SLUG}/phases/`
  - STATE_PATH = `.planning/{SLUG}/STATE.md`
- If `.planning/ACTIVE` does not exist (single-milestone mode): Set:
  - SLUG = "default"
  - MILESTONE_DIR = `.planning/` (the root planning directory acts as the milestone)
  - ROADMAP_PATH = `.planning/ROADMAP.md`
  - PHASES_DIR = `.planning/phases/`
  - STATE_PATH = `.planning/STATE.md`

Read the ROADMAP_PATH to extract the milestone name from its title heading.

### Step 2: Parse arguments

Extract flags from $ARGUMENTS:

- **--tag=vN.N.N**: Custom git tag value (e.g., `--tag=v1.0.0`, `--tag=v2.3.1`). Extract the value after `=`.
- **--no-tag**: Skip git tagging entirely. Boolean flag.
- **--force**: Skip the audit requirement in Guard step 3. Boolean flag.

These flags are all optional and can be combined (e.g., `--force --no-tag`).

### Step 3: Compute milestone summary

Gather statistics from the milestone's artifacts:

**From ROADMAP_PATH:**
- Total phases listed
- Phase names and IDs

**From PHASES_DIR (using Glob for `*-SUMMARY.md` files):**
- Total phases completed (count phase directories with at least one SUMMARY.md)
- Total tasks completed (sum task counts from each SUMMARY.md frontmatter)
- Total commits (sum commit counts from each SUMMARY.md frontmatter, if available)
- Total deviations (sum deviation counts from each SUMMARY.md)

**From REQUIREMENTS.md (if exists):**
- Total requirements defined
- Requirements satisfied (count requirement IDs that appear in completed SUMMARY.md files)

Store all metrics for the ship confirmation display.

### Step 4: Archive milestone

Move the milestone to the archive directory:

1. Create the archive directory: `mkdir -p .planning/milestones/`

2. **If multi-milestone mode** (ACTIVE file exists, SLUG is not "default" in single-milestone context):
   Move the entire milestone directory to the archive:
   `mv .planning/{SLUG}/ .planning/milestones/{SLUG}/`

3. **If single-milestone mode** (no ACTIVE file):
   Create archive directory and copy milestone-scoped files:
   `mkdir -p .planning/milestones/{SLUG}/`
   Move: ROADMAP.md, STATE.md, phases/ to `.planning/milestones/{SLUG}/`
   Keep shared files (PROJECT.md, config.json, REQUIREMENTS.md, codebase/) in place.

4. Write a SHIPPED.md file to the archived directory:

```markdown
# Shipped: {milestone-name}

**Ship date:** {YYYY-MM-DD}
**Archive path:** .planning/milestones/{SLUG}/

## Summary

- Phases completed: {completed}/{total}
- Tasks completed: {count}
- Commits: {count}
- Requirements satisfied: {satisfied}/{total}
- Deviations: {count}
- Git tag: {tag-name or "none"}
```

### Step 5: Git tagging

**If `--no-tag` is NOT set:**

1. Determine the tag name:
   - If `--tag=value` was provided: use that value as the tag name
   - Otherwise: use `milestone/{SLUG}` as the default tag name

2. Create an annotated git tag:
   `git tag -a {tag-name} -m "Shipped milestone: {milestone-name}"`

3. Display: `✓ Tagged: {tag-name}`

**If `--no-tag` IS set:**
- Display: `○ Git tag skipped`

### Step 6: Update ACTIVE pointer

After archiving, update the ACTIVE file:

1. Check if other milestone directories still exist:
   Look for `.planning/*/ROADMAP.md` files, excluding `.planning/milestones/` (the archive directory).

2. **If other milestones exist:**
   Set ACTIVE to the first remaining milestone slug (alphabetical order).
   Write that slug to `.planning/ACTIVE`.
   Display: `Active milestone switched to: {next-slug}`

3. **If NO other milestones exist:**
   Remove the `.planning/ACTIVE` file entirely.
   Display: `Single-milestone mode restored.`

### Step 7: Clear milestone-scoped state and memory cleanup (MEMO-06)

The milestone directory was moved to .planning/milestones/ in Step 4. The archive IS the cleanup for milestone artifacts.

**Memory cleanup:**

1. **Delete RESUME.md:** If a RESUME.md file exists in the archived milestone directory (.planning/milestones/{slug}/RESUME.md) or at .planning/RESUME.md (single-milestone mode), delete it. Session state from a shipped milestone is stale.

2. **Preserve patterns:** .planning/patterns/PATTERNS.md is project-scoped (not milestone-scoped). Do NOT move or delete it during archival. Patterns persist across milestones per MLST-09.

3. **Regenerate CLAUDE.md:** If CLAUDE.md exists at the project root, regenerate it following @${CLAUDE_PLUGIN_ROOT}/references/memory-protocol.md:
   - Update Active Context to reflect the new state:
     - If another milestone is now active (Step 6 set a new ACTIVE): show that milestone's position
     - If no milestones remain: show "No active milestone" and suggest /vbw:milestone
   - Remove references to the shipped milestone from Key Decisions (keep only project-level decisions)
   - Keep Learned Patterns section (patterns persist)
   - Update the "Next action" suggestion appropriately

   If CLAUDE.md does not exist, skip regeneration.

### Step 8: Present ship confirmation

Display the ship confirmation using the Ship Confirmation template (template 6) from @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand.md:

```
╔═══════════════════════════════════════════╗
║  Shipped: {milestone-name}               ║
╚═══════════════════════════════════════════╝

  Phases:       {completed}/{total}
  Tasks:        {count}
  Commits:      {count}
  Requirements: {satisfied}/{total}
  Deviations:   {count}

  Archive: .planning/milestones/{SLUG}/
  Tag:     {tag-name or "none"}

  Memory:
    ✓ Patterns preserved (.planning/patterns/)
    ✓ CLAUDE.md updated
    ✓ Session resume cleared

  {If other milestones exist:}
  Active milestone switched to: {next-milestone}

  {If no milestones remain:}
  No active milestones. Single-milestone mode restored.

➜ Next Up
  /vbw:milestone <name> -- Start a new milestone
  /vbw:status -- View project overview
```

Use Metrics Block formatting for the statistics. Use Next Up Block for navigation.

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand.md for all visual formatting:
- Ship Confirmation template (template 6) for the main output
- Metrics Block (template 9) for the statistics section
- Next Up Block (template 7) for navigation
- File Checklist (template 8) for archive confirmation
- No ANSI color codes
- Lines under 80 characters inside boxes
