---
description: Gather phase context through structured questions before planning.
argument-hint: <phase-number>
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# VBW Discuss: $ARGUMENTS

## Context

Working directory: `!`pwd``

Current roadmap:
```
!`cat .planning/ROADMAP.md 2>/dev/null || echo "No roadmap found"`
```

Current state:
```
!`cat .planning/STATE.md 2>/dev/null || echo "No state found"`
```

## Guard

1. **Not initialized:** If .planning/ doesn't exist, STOP: "Run /vbw:init first."
2. **Missing phase number:** If $ARGUMENTS doesn't include a phase number, STOP: "Usage: /vbw:discuss <phase-number>"
3. **Phase not in roadmap:** If phase doesn't exist in ROADMAP.md, STOP: "Phase {N} not found."

## Purpose

The discuss command is a structured conversation between Claude and the user about an upcoming phase. It surfaces the user's vision, priorities, and constraints BEFORE the Lead agent plans. The output is a CONTEXT.md file that /vbw:plan reads as locked input.

This is NOT brainstorming. It is requirements clarification.

## Steps

### Step 1: Load phase details

Read from ROADMAP.md:
- Phase goal
- Phase requirements (IDs and descriptions from REQUIREMENTS.md)
- Phase success criteria
- Phase dependencies (what must be done first)

### Step 2: Structured questioning

Ask the user 3-5 questions specific to this phase. Tailor questions to the phase content, not generic.

**Question categories:**
- **Essential features:** "Of the {N} requirements in this phase, which are most critical to get right? Any you'd defer?"
- **Technical preferences:** "Do you have preferences for how {specific requirement} should be implemented?"
- **Boundaries:** "Are there approaches you want to avoid for this phase?"
- **Dependencies:** "Is there anything from prior phases that should influence how we approach this?"
- **Acceptance:** "What would make you confident this phase is done? Beyond the roadmap criteria?"

Adapt questions based on phase type:
- Agent/system phases: focus on behavior expectations, error handling preferences
- UI phases: focus on look/feel, interaction patterns, responsive requirements
- Integration phases: focus on service preferences, auth approach, error strategies
- Infrastructure phases: focus on hosting, scaling, security requirements

### Step 3: Synthesize into CONTEXT.md

After the user answers, synthesize responses into a structured CONTEXT.md file.

Write to: `.planning/phases/{phase-dir}/{phase}-CONTEXT.md`

Format:
```
# Phase {N} Context

## User Vision
{What the user wants this phase to achieve, in their words}

## Essential Features
{Prioritized list from user's answers}

## Technical Preferences
{Specific implementation preferences stated by user}

## Boundaries
{What to avoid, stated constraints}

## Acceptance Criteria (User)
{What "done" looks like beyond roadmap criteria}

## Decisions Made
{Any decisions locked during this discussion}
```

### Step 4: Confirm and next step

Show the user the CONTEXT.md summary. Ask for confirmation or corrections.

End with Next Up block: "Run /vbw:plan {N} to plan this phase with your context locked in."

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand.md:
- Single-line box for each question
- Checkmark for captured answers
- Arrow for Next Up
- No ANSI color codes
