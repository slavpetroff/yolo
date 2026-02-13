# Frontend Department Protocol

Frontend team roster, escalation, conventions, and workflow. Read by frontend agents only.

## Agent Roster

| Agent | Role | Model | Tools | Produces | Token Budget |
|-------|------|-------|-------|----------|-------------|
| yolo-fe-architect | Frontend Architect | Opus | Read,Glob,Grep,Write,WebSearch,WebFetch | fe-architecture.toon | 5000 |
| yolo-fe-lead | Frontend Lead | Sonnet | Read,Glob,Grep,Write,Bash,WebFetch | plan.jsonl, orchestration | 3000 |
| yolo-fe-senior | Frontend Senior | Opus | Read,Glob,Grep,Write,Edit,Bash | enriched plan specs (spec+ts), code-review.jsonl | 4000 |
| yolo-fe-tester | Frontend Test Author | Sonnet | Read,Glob,Grep,Write,Bash | test files, test-plan.jsonl | 3000 |
| yolo-fe-dev | Frontend Developer | Sonnet | All | source code, summary.jsonl | 2000 |
| yolo-fe-qa | Frontend QA Lead | Sonnet | Read,Glob,Grep (read-only) | verification.jsonl | 2000 |
| yolo-fe-qa-code | Frontend QA Engineer | Sonnet | Read,Glob,Grep,Bash | qa-code.jsonl | 3000 |

Models shown are quality profile defaults. Actual models resolved via `resolve-agent-model.sh` from `config/model-profiles.json`.

## Team Structure & Escalation

Frontend follows standard company hierarchy with fe- prefixed agents. See @references/company-hierarchy.md ## Team Structure and ## Escalation Chain sections.

Frontend-specific escalation chain: FE Dev → FE Senior → FE Lead → FE Architect → Owner → User

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

Frontend agents write to frontend source directories (`src/components/`, `src/pages/`, `src/hooks/`, `src/styles/`, etc.) and `.yolo-planning/phases/`.
Frontend agents MUST NOT write to backend-only directories (`scripts/`, `agents/`, `hooks/`, `config/`) or design directories (`design/`, `wireframes/`) owned by other departments (enforced by `department-guard.sh` hook).
