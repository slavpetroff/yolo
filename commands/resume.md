---
name: resume
description: Restore project context from .vbw-planning/ state.
argument-hint:
allowed-tools: Read, Bash, Glob
---

# VBW Resume

## Context

Working directory: `!`pwd``

Active milestone:
```
!`cat .vbw-planning/ACTIVE 2>/dev/null || echo "No active milestone (single-milestone mode)"`
```

## Guard

1. **Not initialized:** Follow the Initialization Guard in `${CLAUDE_PLUGIN_ROOT}/references/shared-patterns.md`.
2. **No roadmap:** If ROADMAP.md doesn't exist at resolved path, STOP: "No roadmap found. Run /vbw:implement to set up your project."

## Steps

### Step 1: Resolve paths

If .vbw-planning/ACTIVE exists: use milestone-scoped STATE_PATH, PHASES_DIR, ROADMAP_PATH, PROJECT_PATH.
Otherwise: use .vbw-planning/ defaults.

### Step 2: Read ground truth

Read the following files (skip any that don't exist):

1. **PROJECT.md** → project name, core value
2. **STATE.md** → accumulated decisions, todos, blockers, last activity
3. **ROADMAP.md** → phase structure, completion status
4. **Glob `*-PLAN.md`** in PHASES_DIR → list of plans per phase
5. **Glob `*-SUMMARY.md`** in PHASES_DIR → completed plans per phase
6. **`.execution-state.json`** (if exists) → detect interrupted builds
7. **Most recent SUMMARY.md** (by filename sort) → context on last completed work
8. **RESUME.md** (if exists) → bonus session notes from /vbw:pause (optional, not required)

### Step 3: Compute progress

For each phase in ROADMAP.md:
- Count total PLAN.md files in phase directory
- Count matching SUMMARY.md files
- Determine: not started (0 plans), planned (plans, no summaries), in progress (some summaries), complete (all summaries)

Identify current phase = first phase that is not complete.

### Step 4: Detect interrupted builds

If `.vbw-planning/.execution-state.json` exists:
1. Read the execution state JSON
2. If status is "running" but ALL plans have SUMMARY.md: build completed since last session
3. If status is "running" and some plans lack SUMMARY.md: build was interrupted
4. If status is not "running": no active build

### Step 5: Present context restoration dashboard

```
╔═══════════════════════════════════════════╗
║  Context Restored                         ║
║  {project name}                           ║
╚═══════════════════════════════════════════╝

  Core Value: {from PROJECT.md}

  Phase:    {N} - {name}
  Progress: {completed}/{total} plans
  Overall:  {phases_done}/{phases_total} phases
            {progress bar} {percent}%

  {If decisions in STATE.md:}
  Key Decisions:
    • {decision 1}
    • {decision 2}

  {If todos in STATE.md:}
  Pending Todos:
    • {todo 1}

  {If blockers in STATE.md:}
  ⚠ Blockers:
    • {blocker 1}

  {If most recent SUMMARY.md exists:}
  Last Completed:
    {plan title from most recent SUMMARY.md}

  {If build completed since last session:}
  ✓ Build completed ({total} plans done)

  {If build was interrupted:}
  ⚠ Build interrupted ({done}/{total} plans complete)

  {If RESUME.md exists and has session notes:}
  Session Notes: {notes from RESUME.md}

➜ Next Up
  {If build completed: "/vbw:qa {N} -- Verify the completed build"}
  {If build interrupted: "/vbw:execute {N} -- Resume the interrupted build"}
  {If current phase has no plans: "/vbw:implement -- Plan and execute next phase"}
  {If current phase planned but not started: "/vbw:execute {N} -- Execute the planned phase"}
  {If all phases complete: "/vbw:archive -- Close out completed work"}
  {Otherwise: "/vbw:implement -- Continue where you left off"}
```

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md:
- Double-line box for restore header
- Metrics Block for position and status
- ⚠ for warnings (blockers, interrupted builds)
- ✓ for completions
- ➜ for Next Up block
- No ANSI color codes
