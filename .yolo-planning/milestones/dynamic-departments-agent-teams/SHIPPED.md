# Shipped: Dynamic Departments & Agent Teams

**Shipped:** 2026-02-16
**Duration:** 1 day
**Tag:** milestone/dynamic-departments-agent-teams

## Summary

| Metric | Value |
|--------|-------|
| Phases | 3 |
| Plans | 11 |
| Tasks | 38 |
| Commits | 49 |
| Tests | 209 |
| Deviations | 3 |
| Requirements | 7/7 covered |

## Phases

### Phase 1: Project Type Detection & Persona Templates
- 4 plans, 13 tasks, 16 commits, 63 tests
- REQ-01, REQ-02, REQ-07
- Key: detect-stack.sh classification, generate-department-toons.sh, project-types.json

### Phase 2: Agent Teams Integration
- 3 plans, 11 tasks, 15 commits, 71 tests
- REQ-03
- Key: File-based coordination (no Teammate API), dept-orchestrate.sh, sentinel gates

### Phase 3: Token Optimization & Context Packages
- 4 plans, 14 tasks, 18 commits, 75 tests
- REQ-04, REQ-05, REQ-06
- Key: validate-plan.sh, validate-gates.sh, 9 reference packages, tool-permissions.json

## Key Decisions
- Parallel indexed arrays for bash 3.2 compat
- File-based coordination over Teammate API (reliability)
- Hand-authored reference packages over awk extraction (robustness)
- Soft tool enforcement via compiled context (no runtime YAML injection)
- Two-layer TOON model (static + generated)

## Deviations
1. Phase 1: generate-department-toons.sh uses parameter expansion instead of eval for safety
2. Phase 2: company-hierarchy.md literal "spawnTeam/SendMessage" removed for test compat
3. Phase 3: validate-gates.sh uses global vars instead of local for bash 3.2 compat
