# Frontend Department Protocol

Frontend team roster, escalation, conventions, and workflow. Read by frontend agents only.

## Agent Roster

| Agent | Role | Model | Tools | Produces | Token Budget |
|-------|------|-------|-------|----------|-------------|
| vbw-fe-architect | Frontend Architect | Opus | Read,Glob,Grep,Write,WebSearch,WebFetch | fe-architecture.toon | 5000 |
| vbw-fe-lead | Frontend Lead | Sonnet | Read,Glob,Grep,Write,Bash,WebFetch | plan.jsonl, orchestration | 3000 |
| vbw-fe-senior | Frontend Senior | Opus | Read,Glob,Grep,Write,Edit,Bash | enriched plan specs (spec+ts), code-review.jsonl | 4000 |
| vbw-fe-tester | Frontend Test Author | Sonnet | Read,Glob,Grep,Write,Bash | test files, test-plan.jsonl | 3000 |
| vbw-fe-dev | Frontend Developer | Sonnet | All | source code, summary.jsonl | 2000 |
| vbw-fe-qa | Frontend QA Lead | Sonnet | Read,Glob,Grep (read-only) | verification.jsonl | 2000 |
| vbw-fe-qa-code | Frontend QA Engineer | Sonnet | Read,Glob,Grep,Bash | qa-code.jsonl | 3000 |

Models shown are quality profile defaults. Actual models resolved via `resolve-agent-model.sh` from `config/model-profiles.json`.

## Team Structure

| Team | Agents | Active During |
|------|--------|--------------|
| Planning | FE Architect, FE Lead | Architecture, Planning |
| Execution | FE Senior, FE Tester, FE Dev, Debugger (on-call) | Design Review, Test Authoring (RED), Implementation |
| Quality | FE QA Lead, FE QA Code, FE Senior (escalation) | Code Review, QA |

## Escalation Chain (STRICT — NO LEVEL SKIPPING)

```
FE Dev → FE Senior → FE Lead → FE Architect → Owner → User
```

| Agent | Escalates to | Trigger |
|-------|-------------|---------|
| FE Dev | FE Senior | Blocker, spec unclear, 2 task failures, architectural issue |
| FE Senior | FE Lead | Can't resolve Dev blocker, design conflict, code review cycle 2 fail |
| FE Lead | FE Architect | Can't resolve Senior escalation, design problem, cross-phase issue |
| FE Architect | Owner (or User if no Owner) | Design-level decision needed, scope change required |
| FE Tester | FE Senior | `ts` field unclear, tests pass unexpectedly |
| FE QA Lead | FE Lead | Verification findings, FAIL result |
| FE QA Code | FE Lead | Critical/major findings, FAIL result |

**Rules:**
1. Each agent escalates ONLY to their direct report-to. No skipping.
2. FE Dev NEVER contacts FE Lead, FE Architect, or User.
3. FE QA/Tester NEVER contact FE Architect. Findings route through FE Lead.
4. Only FE Architect escalates to Owner/User.

## Domain Conventions

- **Focus**: Component architecture, state management, routing, UI rendering
- **Testing**: Component tests (vitest/jest + testing-library), E2E specs (playwright), visual regression
- **Tooling**: TypeScript, React/Vue/Svelte (per project), CSS-in-JS or Tailwind
- **Accessibility**: WCAG 2.1 AA minimum, aria attributes, keyboard navigation
- **Performance**: Bundle size monitoring, code splitting, lazy loading
- **Design tokens**: Consumed from UI/UX `design-tokens.jsonl` handoff
- **Commits**: `{type}({scope}): {desc}`, one commit per task
- **Artifacts**: JSONL with abbreviated keys (see `references/artifact-formats.md`)

## 10-Step Workflow

Frontend follows the standard 10-step workflow with these domain specializations:

1. **Critique** (Shared Critic) — Includes component architecture review
2. **Architecture** (FE Architect) — Component hierarchy, state management strategy, routing
3. **Planning** (FE Lead) — Component breakdown, page decomposition
4. **Design Review** (FE Senior) — Enriches with component specs, prop types, state shapes
5. **Test Authoring RED** (FE Tester) — Component tests, interaction tests, E2E specs
6. **Implementation** (FE Dev) — Component code, styles, state logic, API integration
7. **Code Review** (FE Senior) — Accessibility, performance, design compliance
8. **QA** (FE QA Lead + FE QA Code) — Design compliance, UX verification, accessibility audit, bundle size
9. **Security** (Shared Security) — XSS prevention, CSP compliance, auth token handling
10. **Sign-off** (FE Lead/Owner) — Department result to Owner

## Cross-Department Communication

Frontend has the broadest communication scope across departments:

**Receives from UI/UX (via handoff):**
- `design-tokens.jsonl` — Colors, typography, spacing, breakpoints
- `component-specs.jsonl` — Component layout, behavior, interactions, states
- `user-flows.jsonl` — User journey maps, navigation structure
- `design-handoff.jsonl` — Summary with acceptance criteria

**Communicates with Backend:**
- FE Lead sends `api_contract` to Backend Lead (proposed endpoints, request/response schemas)
- FE Lead receives `api_contract` from Backend Lead (implemented endpoints)

**Reports to Owner:**
- FE Lead sends `department_result` at phase completion

Frontend agents NEVER bypass FE Lead for cross-department communication.

See `references/cross-team-protocol.md` for full cross-department rules.

## Directory Isolation

Frontend agents write to frontend source directories (`src/components/`, `src/pages/`, `src/hooks/`, `src/styles/`, etc.) and `.vbw-planning/phases/`.
Frontend agents MUST NOT write to backend-only directories (`scripts/`, `agents/`, `hooks/`, `config/`) or design directories (`design/`, `wireframes/`) owned by other departments (enforced by `department-guard.sh` hook).
