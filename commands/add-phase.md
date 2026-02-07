---
description: Add a new phase to the end of the active milestone's roadmap.
argument-hint: <phase-name> [--goal="phase goal description"]
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# VBW Add-Phase: $ARGUMENTS

## Context

Working directory: `!`pwd``

Active milestone:
```
!`cat .planning/ACTIVE 2>/dev/null || echo "No active milestone (single-milestone mode)"`
```

Planning structure:
```
!`ls .planning/ 2>/dev/null || echo "Not initialized"`
```

## Guard

1. **Not initialized:** If `.planning/` directory doesn't exist, STOP: "Run /vbw:init first."

2. **Missing phase name:** If `$ARGUMENTS` doesn't include a phase name (first non-flag argument), STOP: "Usage: /vbw:add-phase <phase-name> [--goal=\"description\"]"

## Steps

### Step 1: Resolve milestone context

Determine which milestone's roadmap to modify:

1. Check if `.planning/ACTIVE` exists
2. If ACTIVE exists: read the slug, set:
   - `ROADMAP_PATH=.planning/{slug}/ROADMAP.md`
   - `PHASES_DIR=.planning/{slug}/phases`
   - `MILESTONE_NAME={slug}`
3. If ACTIVE does NOT exist (single-milestone mode): set:
   - `ROADMAP_PATH=.planning/ROADMAP.md`
   - `PHASES_DIR=.planning/phases`
   - `MILESTONE_NAME=default`
4. Read the resolved ROADMAP.md

### Step 2: Parse arguments

Extract from `$ARGUMENTS`:
- **Phase name:** First non-flag argument (everything before `--` flags)
- **--goal flag:** Optional, extract the quoted value after `--goal=`
- **Slug generation:** Lowercase the phase name, replace spaces with hyphens, strip special characters except hyphens
  - Example: "API Layer" becomes "api-layer"
  - Example: "Visual Feedback" becomes "visual-feedback"

### Step 3: Determine next phase number

Parse the existing ROADMAP.md to find the highest phase number:

1. Search for all `Phase {N}:` patterns in the roadmap
2. Find the maximum N value
3. Next phase number = maximum + 1
4. Format with zero-padding: 01, 02, ..., 09, 10, 11, etc.
5. If no phases exist, start at 01

### Step 4: Add phase to roadmap

Edit the resolved ROADMAP.md to append the new phase in three locations:

**4a. Phase list entry** (the `- [ ] **Phase N: Name**` entries):

```
- [ ] **Phase {N}: {phase-name}** - {goal or "To be planned"}
```

**4b. Phase Details section** (append after the last existing Phase Details section):

```markdown
### Phase {N}: {phase-name}
**Goal**: {goal from --goal flag, or "To be planned via /vbw:discuss"}
**Depends on**: Phase {N-1} ({previous phase name})
**Requirements**: TBD
**Success Criteria** (what must be TRUE):
  1. TBD -- define via /vbw:discuss or /vbw:plan
**Plans**: 0 plans

Plans:
- [ ] TBD -- created by /vbw:plan
```

**4c. Progress table** (add a new row at the end of the table):

```
| {N}. {phase-name} | 0/0 | Not started | - |
```

### Step 5: Create phase directory

Create the phase directory for the new phase:

```bash
mkdir -p {PHASES_DIR}/{NN}-{slug}/
```

Where `{NN}` is the zero-padded phase number and `{slug}` is the generated slug.

### Step 6: Present summary

Display using brand formatting:

```
╔═══════════════════════════════════════════╗
║  Phase Added: {phase-name}                ║
║  Phase {N} of {total}                     ║
╚═══════════════════════════════════════════╝

  Milestone: {MILESTONE_NAME}
  Position:  Phase {N} (appended to end)
  Goal:      {goal or "To be planned"}

  ✓ Updated {ROADMAP_PATH}
  ✓ Created {PHASES_DIR}/{NN}-{slug}/

➜ Next Up
  /vbw:discuss {N} -- Define this phase's scope
  /vbw:plan {N} -- Plan this phase directly
```

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand.md for all visual formatting:
- Use the **Phase Banner** template (double-line box) for the phase added banner
- Use the **Metrics Block** template for milestone/position/goal display
- Use the **File Checklist** template for the created/updated files list (✓ prefix)
- Use the **Next Up Block** template for navigation (➜ header, indented commands with --)
- No ANSI color codes
- Keep lines under 80 characters inside boxes
