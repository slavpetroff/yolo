# YOLO Company Alignment Audit Checklist

Reusable checklist comparing YOLO agent hierarchy against real company engineering processes. Run after each phase to verify alignment.

## Agent Roles (26 agents)

| # | Agent | Role Alignment | Review Owner | Status Reporting | Handoff | Change Mgmt |
|---|-------|---------------|-------------|-----------------|---------|-------------|
| 1 | yolo-architect | VP Eng / Solutions Architect | Required (per D1) | N/A | Required | N/A |
| 2 | yolo-lead | Tech Lead | Required (per D1) | Required (per D5) | N/A | N/A |
| 3 | yolo-senior | Senior Engineer | Required (per D1) | N/A | N/A | Required (per D4) |
| 4 | yolo-dev | Junior Developer | N/A (non-reviewing) | N/A | N/A | Required (per D4) |
| 5 | yolo-qa | QA Lead | Required (per D1) | N/A | N/A | N/A |
| 6 | yolo-qa-code | QA Code Engineer | Required (per D1) | N/A | N/A | N/A |
| 7 | yolo-tester | TDD Test Author | N/A (non-reviewing) | N/A | N/A | N/A |
| 8 | yolo-fe-architect | Frontend Architect | Required (per D1) | N/A | Required | N/A |
| 9 | yolo-fe-lead | Frontend Lead | Required (per D1) | Required (per D5) | N/A | N/A |
| 10 | yolo-fe-senior | Frontend Senior | Required (per D1) | N/A | N/A | Required (per D4) |
| 11 | yolo-fe-dev | Frontend Dev | N/A (non-reviewing) | N/A | N/A | Required (per D4) |
| 12 | yolo-fe-qa | Frontend QA Lead | Required (per D1) | N/A | N/A | N/A |
| 13 | yolo-fe-qa-code | Frontend QA Code | Required (per D1) | N/A | N/A | N/A |
| 14 | yolo-fe-tester | Frontend Tester | N/A (non-reviewing) | N/A | N/A | N/A |
| 15 | yolo-ux-architect | UX Architect | Required (per D1) | N/A | Required | N/A |
| 16 | yolo-ux-lead | UX Lead | Required (per D1) | Required (per D5) | N/A | N/A |
| 17 | yolo-ux-senior | UX Senior | Required (per D1) | N/A | N/A | Required (per D4) |
| 18 | yolo-ux-dev | UX Dev | N/A (non-reviewing) | N/A | N/A | Required (per D4) |
| 19 | yolo-ux-qa | UX QA Lead | Required (per D1) | N/A | N/A | N/A |
| 20 | yolo-ux-qa-code | UX QA Code | Required (per D1) | N/A | N/A | N/A |
| 21 | yolo-ux-tester | UX Tester | N/A (non-reviewing) | N/A | N/A | N/A |
| 22 | yolo-owner | Project Owner | Required (per D1) | N/A | N/A | N/A |
| 23 | yolo-critic | Brainstorm / Gap Analyst | N/A (non-reviewing) | N/A | N/A | N/A |
| 24 | yolo-scout | Research Analyst | N/A (non-reviewing) | N/A | N/A | N/A |
| 25 | yolo-debugger | Incident Responder | N/A (non-reviewing) | N/A | N/A | N/A |
| 26 | yolo-security | Security Engineer | N/A (non-reviewing) | N/A | N/A | N/A |

Checklist:
- [ ] All 16 reviewing agents have ## Review Ownership section (AG-001 through AG-016)
- [ ] All 3 Lead agents have status reporting instructions (AG-017, AG-018, AG-019)
- [ ] Architect references R&D handoff protocol (AG-020, AG-021, AG-022)
- [ ] Senior references change management loops (AG-023, AG-024, AG-025)
- [ ] Dev references collaborative revision process (AG-026, AG-027, AG-028)

## Workflow Steps (11 steps)

| Step | Name | Agent | Handoff In | Handoff Out | Gate | Status |
|------|------|-------|-----------|-------------|------|--------|
| 1 | Critique | Critic | Phase dir | critique.jsonl | Entry: dir exists | Gap: No standalone R&D handoff protocol (WF-001) |
| 2 | Research | Scout | critique.jsonl (critical/major) | research.jsonl | Entry: critique.jsonl OR step 1 skipped | Gap: Part of unformalized R&D pipeline (WF-001) |
| 3 | Architecture | Architect | research.jsonl + critique.jsonl | architecture.toon | Entry: research.jsonl OR step 2 skipped | Gap: No stage-gate checklist for architecture.toon (WF-002) |
| 4 | Planning | Lead | architecture.toon | plan.jsonl | Entry: architecture.toon OR step 3 skipped | Gap: Missing status reporting (WF-004) |
| 5 | Design Review | Senior | plan.jsonl + architecture.toon | enriched plan.jsonl (spec+ts) | Entry: plan.jsonl exists | OK |
| 6 | Test Authoring | Tester | enriched plan.jsonl (ts fields) | test-plan.jsonl + test files | Entry: enriched plan.jsonl with spec | OK |
| 7 | Implementation | Dev | enriched plan.jsonl + test files | code + summary.jsonl | Entry: plan.jsonl + test-plan.jsonl (if step 6 ran) | Gap: Missing change management formalization (WF-003) |
| 8 | Code Review | Senior | git diff + plan + tests | code-review.jsonl | Entry: summary.jsonl | Gap: Missing Minor/Major classification (WF-003) |
| 9 | QA | QA Lead + Code | plan + summary + artifacts | verification.jsonl + qa-code.jsonl | Entry: code-review.jsonl approved | Gap: Feedback loop content underspecified (WF-005) |
| 10 | Security | Security | summary.jsonl (file list) | security-audit.jsonl | Entry: verification.jsonl OR step 9 skipped | OK |
| 11 | Sign-off | Lead | all artifacts | execution-state.json + ROADMAP.md | Entry: security-audit.jsonl OR step 10 skipped | OK |

Checklist:
- [x] Zero stale step-count references across codebase -- all updated to 11-step (WF-006 through WF-026: fixed in 03-04/T1)
- [ ] R&D handoff protocol exists (references/rnd-handoff-protocol.md) (WF-001)
- [ ] Architect->Lead stage-gate documented (WF-002)
- [ ] Change management section in execute-protocol.md (WF-003)
- [ ] Status reporting protocol referenced (WF-004)

## Escalation Paths

| Chain | Path | Evidence Req | Feedback Loop |
|-------|------|-------------|---------------|
| Single-dept | Dev > Senior > Lead > Architect > User | Yes (rule 7 in company-hierarchy.md) | Resolution flows down as artifacts |
| Multi-dept | Dept Dev > ... > Dept Architect > Owner > User | Yes | Owner pushes corrected context down |
| QA Remediation | QA Code > Lead > Senior > Dev (3-level) | Yes (gaps.jsonl) | Dev fixes, QA re-verifies (max 2 cycles) |
| Code Review | Senior > Dev (2-cycle max) | Yes (code-review.jsonl) | Dev fixes per exact instructions |

Checklist:
- [ ] Every agent documents exact escalation target (EC-004)
- [ ] Escalation includes evidence requirement (EC-004)
- [ ] Feedback loop documented for each escalation path (EC-003, EC-005)

## Communication Patterns

Checklist:
- [ ] Cross-dept communication goes through Leads only (documented in cross-team-protocol.md)
- [ ] All cross-dept data passes through handoff artifacts (documented in cross-team-protocol.md)
- [ ] Backend-UI/UX isolation absolute (documented in cross-team-protocol.md)
- [ ] Status reporting protocol in cross-team-protocol.md (EC-001: missing)
- [ ] All handoff schemas in handoff-schemas.md (EC-002: missing phase_progress schema)
- [ ] Owner feedback loop formalized in cross-team-protocol.md (EC-006: missing)

## Review Cycles

Checklist:
- [ ] Senior: 2-cycle max documented with escalation (AG-029, AG-030, AG-031)
- [ ] Minor/Major classification documented (AG-023, AG-024, AG-025)
- [ ] QA remediation chain (3-level) documented (EC-005: feedback content underspecified)
- [ ] Metric collection hooks defined for Phase 4

## Change Management

Checklist:
- [ ] Senior-Dev revision cycle collaborative (not gatekeeping) (AG-023 through AG-028)
- [ ] Minor changes auto-approve after cycle 1 if nits only (WF-003)
- [ ] Major changes escalate after cycle 2 (WF-003)
- [ ] Phase 4 extensibility hooks at metric collection points
