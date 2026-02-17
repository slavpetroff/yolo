# Review Ownership Patterns

Defines reviewer-to-artifact ownership mapping and ownership language templates. Referenced by all 16 reviewing agent prompts during review steps (5, 8, 9, 10).

Per D1: Ownership language applies to agents that review subordinate output. Non-reviewing agents (Dev, Tester, Scout, Critic, Debugger, Security) are excluded -- they are authors/producers, not reviewers.

## Ownership Language Templates

Each reviewer adopts personal ownership of their subordinate's output using this pattern:

> "This is my [subordinate role]'s [artifact]. I take ownership of its quality. I will review thoroughly, document reasoning for every finding, and escalate conflicts I cannot resolve."

### Per-Role Templates

| Reviewer | Reviews | Template | Step |
|----------|---------|----------|------|
| Senior | Dev implementation | "This is my dev's implementation. I own its quality." | 8 (Code Review) |
| Senior | Dev spec compliance | "This is my dev's work against my spec. I own completeness." | 8 |
| Lead | Senior enrichment | "This is my senior's spec enrichment. I own plan quality." | 5 (Design Review exit) |
| Lead | Plan execution | "This is my team's execution. I own delivery." | 11 (Sign-off) |
| Architect | Critique findings | "This is my critique analysis. I own every finding's disposition." | 3 (Architecture) |
| Architect | Architecture quality | "This is my architecture. I own technical decisions." | 3 |
| Owner | Department output | "This is my department's output. I own cross-dept quality." | 11 (Sign-off) |
| QA Lead | Team artifacts | "This is my team's output. I own verification thoroughness." | 9 (QA) |
| QA Code | Code quality | "This is my team's code. I own quality assessment accuracy." | 9 (QA) |

## Ownership Matrix (CODEOWNERS-style)

Machine-parseable mapping of agent to artifact type to review authority:

<!-- OWNERSHIP_MATRIX_START -->
{"agent":"yolo-senior","reviews":"code-review.jsonl","owns":"Dev implementation quality","step":8}
{"agent":"yolo-lead","reviews":"plan.jsonl enrichment","owns":"Plan and spec quality","step":5}
{"agent":"yolo-architect","reviews":"critique.jsonl disposition","owns":"Architecture decisions","step":3}
{"agent":"yolo-owner","reviews":"department_result","owns":"Cross-department quality","step":11}
{"agent":"yolo-qa","reviews":"verification.jsonl","owns":"Verification thoroughness","step":9}
{"agent":"yolo-qa-code","reviews":"qa-code.jsonl","owns":"Code quality assessment","step":9}
{"agent":"yolo-fe-senior","reviews":"code-review.jsonl","owns":"FE Dev implementation quality","step":8}
{"agent":"yolo-fe-lead","reviews":"plan.jsonl enrichment","owns":"FE plan and spec quality","step":5}
{"agent":"yolo-fe-architect","reviews":"critique.jsonl disposition","owns":"FE architecture decisions","step":3}
{"agent":"yolo-fe-qa","reviews":"verification.jsonl","owns":"FE verification thoroughness","step":9}
{"agent":"yolo-fe-qa-code","reviews":"qa-code.jsonl","owns":"FE code quality assessment","step":9}
{"agent":"yolo-ux-senior","reviews":"design-review.jsonl","owns":"UX Dev implementation quality","step":8}
{"agent":"yolo-ux-lead","reviews":"plan.jsonl enrichment","owns":"UX plan and spec quality","step":5}
{"agent":"yolo-ux-architect","reviews":"critique.jsonl disposition","owns":"UX architecture decisions","step":3}
{"agent":"yolo-ux-qa","reviews":"verification.jsonl","owns":"UX verification thoroughness","step":9}
{"agent":"yolo-ux-qa-code","reviews":"qa-code.jsonl","owns":"UX code quality assessment","step":9}
<!-- OWNERSHIP_MATRIX_END -->

## Responsibility Definition (per R8)

Ownership means:
1. **Must analyze**: Read subordinate output thoroughly, not skim
2. **Must document reasoning**: Every review finding includes rationale
3. **Must escalate conflicts**: When reviewer cannot resolve, escalate up chain with evidence
4. **No rubber-stamp approvals**: Auto-approve without review is prohibited

## Excluded Agents (10 of 26)

These agents produce output reviewed by others -- they are authors, not reviewers:
- Dev (yolo-dev, yolo-fe-dev, yolo-ux-dev) -- implements specs
- Tester (yolo-tester, yolo-fe-tester, yolo-ux-tester) -- writes tests per ts field
- Critic (yolo-critic) -- advisory findings, routes to Lead
- Scout (yolo-scout) -- research findings, advisory
- Debugger (yolo-debugger) -- investigation reports
- Security (yolo-security) -- audit findings, reports
