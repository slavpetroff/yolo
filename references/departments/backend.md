# Backend Department Protocol

Backend team roster, escalation, conventions, and workflow. Read by backend agents only.

## Agent Roster

| Agent | Role | Model | Tools | Produces | Token Budget |
|-------|------|-------|-------|----------|-------------|
| yolo-architect | Solutions Architect | Opus | Read,Glob,Grep,Write,WebSearch,WebFetch | architecture.toon, ROADMAP.md | 5000 |
| yolo-lead | Tech Lead | Sonnet | Read,Glob,Grep,Write,Bash,WebFetch | plan.jsonl, orchestration | 3000 |
| yolo-senior | Senior Engineer | Opus | Read,Glob,Grep,Write,Edit,Bash | enriched plan specs (spec+ts), code-review.jsonl | 4000 |
| yolo-tester | TDD Test Author | Sonnet | Read,Glob,Grep,Write,Bash | test files, test-plan.jsonl | 3000 |
| yolo-dev | Junior Developer | Sonnet | All | source code, summary.jsonl | 2000 |
| yolo-qa | QA Lead | Sonnet | Read,Glob,Grep (read-only) | verification.jsonl | 2000 |
| yolo-qa-code | QA Engineer | Sonnet | Read,Glob,Grep,Bash | qa-code.jsonl | 3000 |

Models shown are quality profile defaults. Actual models resolved via `resolve-agent-model.sh` from `config/model-profiles.json`.

## Team Structure & Escalation

Backend follows standard company hierarchy. See @references/company-hierarchy.md ## Team Structure and ## Escalation Chain sections.

Backend-specific escalation chain: Dev → Senior → Lead → Architect → Owner → User

## Domain Conventions

- **Language**: Shell scripts (bash), JSON/JSONL artifacts
- **Testing**: bats-core + bats-support/bats-assert/bats-file
- **Tooling**: jq for all JSON parsing (never grep/sed on JSON)
- **Scripts**: kebab-case .sh files, `set -euo pipefail` for critical scripts
- **Commits**: `{type}({scope}): {desc}`, one commit per task
- **Artifacts**: JSONL with abbreviated keys (see `references/artifact-formats.md`)

## 10-Step Workflow

Backend follows the standard 10-step workflow from `references/execute-protocol.md` without modifications:

1. Critique (Critic) → 2. Architecture (Architect) → 3. Planning (Lead) → 4. Design Review (Senior) → 5. Test Authoring RED (Tester) → 6. Implementation (Dev) → 7. Code Review (Senior) → 8. QA (QA Lead + QA Code) → 9. Security (Security) → 10. Sign-off (Lead/Owner)

## Cross-Department Communication

When multiple departments are active:
- Backend Lead sends `department_result` to Owner at phase completion.
- Backend Lead receives `api_contract` from Frontend Lead (proposed endpoints).
- Backend Lead sends `api_contract` back to Frontend Lead (implemented endpoints).
- Backend agents NEVER communicate with UI/UX agents directly. All UI/UX context arrives via Frontend relay.

See `references/cross-team-protocol.md` for full cross-department rules.

## Directory Isolation

Backend agents write to project source directories and `.yolo-planning/phases/`.
Backend agents MUST NOT write to `frontend/`, `design/`, `styles/`, `components/` directories owned by other departments (enforced by `department-guard.sh` hook).
