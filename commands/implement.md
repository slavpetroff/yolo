---
name: implement
description: "The one command. Detects project state and routes to bootstrap, scoping, planning, execution, or completion."
argument-hint: "[phase-number] [--effort turbo|fast|balanced|thorough] [--skip-qa]"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, WebFetch
disable-model-invocation: true
---

# VBW Implement: $ARGUMENTS

## Context

Working directory: `!`pwd``

Project existence:
```
!`head -20 .vbw-planning/PROJECT.md 2>/dev/null || echo "NO_PROJECT"`
```

Phase directories:
```
!`ls .vbw-planning/phases/ 2>/dev/null || echo "NO_PHASES"`
```

Active milestone:
```
!`cat .vbw-planning/ACTIVE 2>/dev/null || echo "NO_ACTIVE_MILESTONE"`
```

Config:
```
!`cat .vbw-planning/config.json 2>/dev/null || echo "No config found"`
```

Codebase map staleness:
```
!`if [ -f .vbw-planning/codebase/META.md ]; then head -5 .vbw-planning/codebase/META.md; else echo "No codebase map"; fi`
```

Project files (brownfield detection):
```
!`ls package.json pyproject.toml Cargo.toml go.mod *.sln Gemfile build.gradle pom.xml 2>/dev/null || echo "No detected project files"`
```

Existing state:
```
!`ls -la .vbw-planning 2>/dev/null || echo "No .vbw-planning directory"`
```

## State Detection

Evaluate project state in this order. The FIRST matching condition determines the route.

| # | Condition | Route |
|---|-----------|-------|
| 1 | `.vbw-planning/` does not exist | Run /vbw:init first (preserve existing guard) |
| 2 | `.vbw-planning/PROJECT.md` does not exist OR contains template placeholder `{project-description}` | State 1: Bootstrap |
| 3 | No phase directories exist in the resolved phases path (empty or missing) | State 2: Scoping |
| 4 | Phase directories exist and at least one has no `*-PLAN.md` files OR has plans without matching `*-SUMMARY.md` | State 3-4: Plan + Execute (existing behavior) |
| 5 | All phase directories have all plans with matching `*-SUMMARY.md` files | State 5: Completion |

For conditions 3-5, resolve the phases directory first:
- If `.vbw-planning/ACTIVE` exists, read its contents for the milestone slug and use `.vbw-planning/{slug}/phases/`
- Otherwise use `.vbw-planning/phases/`
