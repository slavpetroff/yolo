# YOLO Codebase Index

Cross-referenced index of key findings from all mapping documents.

## Quick Reference

| Metric | Value |
|--------|-------|
| Version | 0.2.2 |
| Source files | 364 |
| Scripts | 69 |
| Agents | 26 (4 departments) |
| Commands | 20 |
| Test files | 99 |
| Test cases | 1919 |
| Hooks | 19+ |
| Handoff schemas | 29 |
| Reference docs | 35+ |
| Workflow steps | 11 |
| ADRs | 5 |

## Key Entry Points

| File | Purpose |
|------|---------|
| commands/go.md | Master dispatcher -- all lifecycle modes |
| commands/init.md | Project bootstrap |
| commands/config.md | Config editor (UPDATED: qa_gates section) |
| scripts/session-start.sh | Session initialization, config migration |
| scripts/compile-context.sh | Role-specific .ctx-{role}.toon generation |
| scripts/filter-agent-context.sh | Per-agent JSONL field filtering |
| scripts/phase-detect.sh | State machine -- current phase/step detection |
| scripts/detect-stack.sh | Project type classification + skill mapping |
| scripts/resolve-team-mode.sh | Task vs Teammate spawn strategy resolution |
| scripts/qa-gate-post-task.sh | Post-task QA gate (NEW) |
| scripts/qa-gate-post-plan.sh | Post-plan QA gate (NEW) |
| scripts/qa-gate-post-phase.sh | Post-phase QA gate (NEW) |
| scripts/check-escalation-timeout.sh | Escalation timeout detection (NEW) |
| tests/integration/escalation-round-trip.bats | Escalation round-trip integration test (NEW) |
| hooks/hooks.json | 19+ quality gate hooks |
| scripts/hook-wrapper.sh | Universal hook wrapper (DXP-01) |
| scripts/block-plan-mode.sh | Hard enforcement for EnterPlanMode (NEW) |
| config/project-types.json | Dynamic persona type definitions |
| references/execute-protocol.md | 11-step workflow canonical definition |
| references/teammate-api-patterns.md | Teammate API coordination patterns |
| references/qa-gate-integration.md | QA gate protocol (NEW) |
| references/review-ownership-patterns.md | Reviewer ownership matrix (NEW) |

## Architecture Summary

- 26 agents across 4 departments (Backend, Frontend, UI/UX, Shared)
- 11-step deterministic workflow per phase: Critique -> Research -> Architecture -> Planning -> Design Review -> Tests -> Implement -> Code Review -> QA -> Security -> Sign-off
- Hierarchical escalation: Dev -> Senior -> Lead -> Architect -> Owner -> User
- Dual spawn strategy: Task tool (default) or Teammate API (parallel, experimental)
- Context progressive narrowing: lower agents see less context
- Artifact formats: Markdown (user), JSONL (agent), TOON (compiled context)
- Dynamic personas: project type detection adapts agent behavior (7 types)
- Reference packages: pre-compiled role context in references/packages/{role}.toon
- QA gates: three-level script-only validation (post-task, post-plan, post-phase)
- Review ownership: 16 reviewing agents adopt personal ownership of subordinate output

## Document Cross-References

| Document | Key Findings |
|----------|-------------|
| STACK.md | Bash+jq core, 19+ hooks, 3 model profiles, Teammate API, QA gate system, test-summary.sh |
| DEPENDENCIES.md | 69 scripts (+7), 26 agents, 20 commands, 35+ references (+5), 3-tier fallback cascade |
| ARCHITECTURE.md | 11-step workflow, dual spawn, QA gates, review ownership, per-agent field filtering |
| STRUCTURE.md | 69 scripts, 26 agents, 20 commands, 99 test files/1919 tests, qa_gates config |
| CONVENTIONS.md | QA gate patterns, review ownership rules, JSON deny format, flock-based serialization |
| TESTING.md | 99 BATS files, 6 categories, QA gate tests, review ownership static tests |
| CONCERNS.md | QA gate risks, review ownership enforcement, flock serialization, gate output formatting gap |

## What Changed (0.2.1 -> 0.2.2)

| Area | Before | After | Delta |
|------|--------|-------|-------|
| Scripts | 62 | 69 | +7 (QA gates: post-task, post-plan, post-phase, qa-gate, validate-gates, resolve-qa-config, format-gate-result, block-plan-mode) |
| References | 29+ | 35+ | +5 (qa-gate-integration, qa-output-patterns, qa-help-text, review-ownership-patterns, rnd-handoff-protocol) |
| Tests | 99 files / 1919 cases | 99+ files / 1919+ cases | +QA gate tests, review ownership tests, gate cascade integration |
| Config | defaults.json | +qa_gates, +approval_gates | New config objects for gate control |
| Hooks | 19 | 19+ | +block-plan-mode.sh (PreToolUse), qa-gate.sh updated for result logging |
| Handoff schemas | 27 | 29 | +2 (escalation_resolution, escalation_timeout_warning) |

**Major additions:**
- QA Gate System (3-level continuous validation: post-task, post-plan, post-phase)
- Review Ownership Patterns (16 reviewing agents with personal ownership language)
- Hard plan-mode enforcement (block-plan-mode.sh as PreToolUse hook)
- QA gate result persistence (.qa-gate-results.jsonl, flock-serialized)
- Config validation expansion (qa_gates schema, approval_gates)
- Gate output patterns (qa-output-patterns.md, qa-help-text.md)
- Teammate API shutdown protocol refinement (deadline handling, verification checklist)
- Escalation Round-Trip (bidirectional Dev<->User path with timeout auto-escalation)

## Validation Notes

- **11-step workflow:** Canonical source is execute-protocol.md. All 11 steps confirmed.
- **Agent count:** 26 agents confirmed. 16 reviewing + 10 non-reviewing.
- **Script count:** 69 scripts total (was 62 in 0.2.1). New scripts for QA gates and enforcement.
- **Reference count:** 35+ files (was 29+ in 0.2.1). 5 new documentation files.
- **STRUCTURE.md canonical** for file paths and counts; ARCHITECTURE.md canonical for workflow and hierarchy.
- **QA gate tests** added to both unit/ and integration/ categories. Static test validates review ownership.

---
