---
description: Surface Claude's implicit assumptions about a phase before planning begins.
argument-hint: <phase-number>
allowed-tools: Read, Glob, Grep, Bash
---

# VBW Assumptions: $ARGUMENTS

## Context

Working directory: `!`pwd``

Current roadmap:
```
!`cat .planning/ROADMAP.md 2>/dev/null || echo "No roadmap found"`
```

Existing codebase signals:
```
!`ls package.json pyproject.toml Cargo.toml go.mod 2>/dev/null || echo "No detected project files"`
```

## Guard

1. **Not initialized:** If .planning/ doesn't exist, STOP: "Run /vbw:init first."
2. **Missing phase number:** If $ARGUMENTS doesn't include a phase number, STOP: "Usage: /vbw:assumptions <phase-number>"
3. **Phase not in roadmap:** If phase doesn't exist in ROADMAP.md, STOP: "Phase {N} not found."

## Purpose

Before planning a phase, Claude inevitably makes assumptions about scope, approach, technology, and user preferences. These assumptions are usually invisible -- they become embedded in plans without the user ever seeing or approving them. This command makes them explicit.

The user can then confirm, correct, or expand on each assumption before /vbw:plan runs.

## Steps

### Step 1: Load phase context

Read:
- ROADMAP.md phase details (goal, requirements, success criteria)
- REQUIREMENTS.md (full descriptions of mapped requirements)
- PROJECT.md (constraints, key decisions)
- STATE.md (accumulated decisions, concerns)
- Any existing CONTEXT.md for this phase (from /vbw:discuss)
- Codebase signals (package.json, existing code patterns)

### Step 2: Generate assumptions

Based on the loaded context, identify and categorize assumptions:

**Scope assumptions:** What is included/excluded that the requirements don't explicitly state.
- Example: "I assume AGNT-07 (compaction profiles) means per-agent instructions in the system prompt, not a separate configuration file."

**Technical assumptions:** Implementation approaches implied but not specified.
- Example: "I assume the effort parameter maps to Claude's reasoning_effort API parameter."

**Ordering assumptions:** How tasks should be sequenced.
- Example: "I assume effort profiles must be defined before agent system prompts, since agents reference them."

**Dependency assumptions:** What must exist from prior phases.
- Example: "I assume the PLAN.md template from Phase 1 is the correct output format."

**User preference assumptions:** Defaults chosen in absence of stated preference.
- Example: "I assume Balanced is the right default effort profile for this phase."

Present 5-10 assumptions, prioritized by impact (high-impact assumptions first).

### Step 3: Gather user feedback

For each assumption, ask: "Confirm, correct, or expand?"
- **Confirm**: Assumption is correct, proceed.
- **Correct**: User provides the right answer.
- **Expand**: Assumption is partially correct, user adds nuance.

### Step 4: Present summary

Present all assumptions with the user's feedback as a formatted summary. Group by status: confirmed, corrected, expanded.

This command does NOT write any files. The assumptions and user feedback exist only in the conversation. If the user wants formal persistence, suggest: "Run /vbw:discuss {N} to capture your preferences as a CONTEXT.md file that /vbw:plan will use."

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand.md:
- Numbered list for assumptions (not bullets -- order conveys priority)
- Checkmark for confirmed, cross for corrected, circle for expanded
- Arrow for Next Up
- No ANSI color codes
