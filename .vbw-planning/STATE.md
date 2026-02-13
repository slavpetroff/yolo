# YOLO State

**Project:** YOLO (YOLO — Your Own Local Orchestrator)
**Milestone:** Company-Grade Engineering Workflow
**Current Phase:** Complete
**Status:** Milestone complete
**Started:** 2026-02-13
**Progress:** 100%

## Phase Status
- **Phase 1:** Complete — Company Hierarchy & Agent Teams
- **Phase 2:** Complete — Token-Optimized Artifacts
- **Phase 3:** Complete — Persistence & Crash Resilience
- **Phase 4:** Complete — Quality Loop & Remediation
- **Phase 5:** Complete — UX, Tooling & Community

## Key Decisions
| Decision | Date | Rationale |
|----------|------|-----------|
| Company hierarchy: Architect → Lead → Senior → Dev | 2026-02-13 | Mirrors real engineering org, each level distills scope for the next |
| JSONL with abbreviated keys for agent artifacts | 2026-02-13 | jq-parseable, 85-93% token savings vs Markdown, zero new deps |
| TOON for compiled context only | 2026-02-13 | Agents read TOON natively, no parser needed; scripts use jq for JSONL |
| Markdown only for user-facing files | 2026-02-13 | ROADMAP.md, PROJECT.md, CLAUDE.md — humans need readable formats |
| Dev as Junior — receives exact specs | 2026-02-13 | Senior enriches plans with spec field, Dev needs zero creative decisions |
| QA split: QA Lead (plan) + QA Code (code) | 2026-02-13 | Plan verification is separate concern from test/lint/coverage |
| Security audit as optional step (config toggle) | 2026-02-13 | Not all projects need security audit, but production ones do |
| Commit every artifact immediately | 2026-02-13 | Survives Claude Code exit, enables resume from any point |
| Senior → Opus in balanced profile | 2026-02-13 | Design review and code review need highest quality reasoning |
| 8-step workflow per phase | 2026-02-13 | Architecture → Plan → Design Review → Implement → Code Review → QA → Security → Sign-off |

## Recent Activity
- 2026-02-13: Created Company-Grade Engineering Workflow milestone (5 phases)
- 2026-02-13: Locked down architecture — company hierarchy, artifact formats, token budgets
- 2026-02-13: Created yolo-senior, yolo-qa-code, yolo-security agents
- 2026-02-13: Updated yolo-architect (R&D role), yolo-dev (Junior), yolo-qa (QA Lead)
- 2026-02-13: Rewrote execute-protocol.md with 8-step workflow
- 2026-02-13: Updated compile-context.sh for all 8 roles with TOON output
- 2026-02-13: Updated handoff-schemas.md with all new agent communication schemas
- 2026-02-13: Wired Architect into go.md Scope mode
- 2026-02-13: Rewrote yolo-lead.md as Tech Lead producing plan.jsonl
- 2026-02-13: Updated resolve-agent-model.sh for senior, qa-code, security (+ fixed jq hyphen bug)
- 2026-02-13: Fixed compile-context.sh local keyword bug in dev/debugger case blocks
- 2026-02-13: Updated 13 scripts for JSONL format detection (backward-compat with legacy MD)
- 2026-02-13: Updated go.md Plan, Execute, Archive, Discuss modes for JSONL references
- 2026-02-13: Updated conventions.json plan file naming to {NN-MM}.plan.jsonl
- 2026-02-13: Phase 1 verified complete — all 11 success criteria PASS
- 2026-02-13: Starting Phase 2 — Token-Optimized Artifacts
