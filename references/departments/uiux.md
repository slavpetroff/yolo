# UI/UX Department Protocol

UI/UX team roster, escalation, conventions, and workflow. Read by UI/UX agents only.

## Agent Roster

| Agent | Role | Model | Tools | Produces | Token Budget |
|-------|------|-------|-------|----------|-------------|
| yolo-ux-architect | UX Architect | Opus | Read,Glob,Grep,Write,WebSearch,WebFetch | ux-architecture.toon | 5000 |
| yolo-ux-lead | UX Lead | Sonnet | Read,Glob,Grep,Write,Bash,WebFetch | plan.jsonl, orchestration | 3000 |
| yolo-ux-senior | UX Senior | Opus | Read,Glob,Grep,Write,Edit,Bash | enriched plan specs (spec+ts), design-review.jsonl | 4000 |
| yolo-ux-tester | UX Test Author | Sonnet | Read,Glob,Grep,Write,Bash | usability specs, test-plan.jsonl | 3000 |
| yolo-ux-dev | UX Designer/Developer | Sonnet | All | design tokens, component specs, wireframes | 2000 |
| yolo-ux-qa | UX QA Lead | Sonnet | Read,Glob,Grep (read-only) | verification.jsonl | 2000 |
| yolo-ux-qa-code | UX QA Engineer | Sonnet | Read,Glob,Grep,Bash | qa-code.jsonl | 3000 |

Models shown are quality profile defaults. Actual models resolved via `resolve-agent-model.sh` from `config/model-profiles.json`.

## Team Structure

| Team | Agents | Active During |
|------|--------|--------------|
| Planning | UX Architect, UX Lead | Architecture, Planning |
| Execution | UX Senior, UX Tester, UX Dev, Debugger (on-call) | Design Review, Test Authoring (RED), Implementation |
| Quality | UX QA Lead, UX QA Code, UX Senior (escalation) | Design Review, QA |

## Escalation Chain (STRICT — NO LEVEL SKIPPING)

```
UX Dev → UX Senior → UX Lead → UX Architect → Owner → User
```

| Agent | Escalates to | Trigger |
|-------|-------------|---------|
| UX Dev | UX Senior | Spec unclear, design token conflict, 2 task failures |
| UX Senior | UX Lead | Can't resolve Dev blocker, design system conflict, review cycle 2 fail |
| UX Lead | UX Architect | Can't resolve Senior escalation, IA problem, cross-phase issue |
| UX Architect | Owner (or User if no Owner) | Design-level decision needed, scope change required |
| UX Tester | UX Senior | Usability spec unclear, accessibility test ambiguity |
| UX QA Lead | UX Lead | Design system violations, FAIL result |
| UX QA Code | UX Lead | Token validation failures, style consistency issues |

**Rules:**
1. Each agent escalates ONLY to their direct report-to. No skipping.
2. UX Dev NEVER contacts UX Lead, UX Architect, or User.
3. UX QA/Tester NEVER contact UX Architect. Findings route through UX Lead.
4. Only UX Architect escalates to Owner/User.

## Domain Conventions

- **Focus**: Information architecture, design system strategy, user flows, accessibility
- **Design system**: Design tokens (colors, typography, spacing, breakpoints) as JSONL
- **Components**: Component specs with states, interactions, responsive breakpoints
- **Accessibility**: WCAG 2.1 AA minimum, screen reader testing, color contrast
- **User flows**: Journey maps, navigation structure, error states, loading states
- **Testing**: Usability checklists, accessibility audits, design token validation
- **Commits**: `{type}({scope}): {desc}`, one commit per task
- **Artifacts**: JSONL with abbreviated keys (see `references/artifact-formats.md`)

## 10-Step Workflow

UI/UX follows the standard 10-step workflow with these domain specializations:

1. **Critique** (Shared Critic) — Includes UX heuristic evaluation, accessibility review
2. **Architecture** (UX Architect) — Information architecture, design system strategy, user flow structure
3. **Planning** (UX Lead) — Design task decomposition, component spec breakdown
4. **Design Review** (UX Senior) — Enriches with exact design token values, interaction specs, responsive rules
5. **Test Authoring RED** (UX Tester) — Usability test specs, accessibility checklists, design compliance criteria
6. **Implementation** (UX Dev) — Design tokens, component specs, wireframes, user flow docs
7. **Code Review** (UX Senior) — Design system consistency, accessibility compliance, spec completeness
8. **QA** (UX QA Lead + UX QA Code) — Design system compliance, consistency audit, A11y lint
9. **Security** (Shared Security) — PII in design artifacts, data exposure in mockups
10. **Sign-off** (UX Lead/Owner) — Department result to Owner + handoff artifacts to Frontend

## Cross-Department Communication

UI/UX runs FIRST in the multi-department workflow. Produces handoff artifacts consumed by Frontend:

**Produces for Frontend (via handoff):**
- `design-tokens.jsonl` — Colors, typography, spacing, breakpoints
- `component-specs.jsonl` — Component layout, behavior, interactions, states
- `user-flows.jsonl` — User journey maps, navigation structure
- `design-handoff.jsonl` — Summary with acceptance criteria and status

**Indirect Backend influence:**
- Data model implications (what data the UI needs) — relayed via Frontend Lead
- API contract suggestions (endpoints, response shapes) — relayed via Frontend Lead

**Reports to Owner:**
- UX Lead sends `department_result` at phase completion

UI/UX agents NEVER communicate with Backend agents directly. All backend context arrives via Frontend relay.

See `references/cross-team-protocol.md` for full cross-department rules.

## Handoff Gate

UI/UX must complete BEFORE Frontend and Backend can start (when all departments are active):
- `design-handoff.jsonl` must exist with `status: "complete"`
- All component specs must have `status: "ready"`
- Design tokens must be committed

## Directory Isolation

UI/UX agents write to design directories (`design/`, `wireframes/`, `design-tokens/`) and `.yolo-planning/phases/`.
UI/UX agents MUST NOT write to source code directories (`src/`, `scripts/`, `agents/`, `hooks/`, `config/`) owned by other departments (enforced by `department-guard.sh` hook).
