# Backend Department Protocol

Backend team roster, escalation, conventions, and workflow. Read by backend agents only.

## Agent Roster

| Agent | Role | Model | Tools | Produces | Token Budget |
|-------|------|-------|-------|----------|-------------|
| vbw-architect | Solutions Architect | Opus | Read,Glob,Grep,Write,WebSearch,WebFetch | architecture.toon, ROADMAP.md | 5000 |
| vbw-lead | Tech Lead | Sonnet | Read,Glob,Grep,Write,Bash,WebFetch | plan.jsonl, orchestration | 3000 |
| vbw-senior | Senior Engineer | Opus | Read,Glob,Grep,Write,Edit,Bash | enriched plan specs (spec+ts), code-review.jsonl | 4000 |
| vbw-tester | TDD Test Author | Sonnet | Read,Glob,Grep,Write,Bash | test files, test-plan.jsonl | 3000 |
| vbw-dev | Junior Developer | Sonnet | All | source code, summary.jsonl | 2000 |
| vbw-qa | QA Lead | Sonnet | Read,Glob,Grep (read-only) | verification.jsonl | 2000 |
| vbw-qa-code | QA Engineer | Sonnet | Read,Glob,Grep,Bash | qa-code.jsonl | 3000 |

Models shown are quality profile defaults. Actual models resolved via `resolve-agent-model.sh` from `config/model-profiles.json`.

## Team Structure

| Team | Agents | Active During |
|------|--------|--------------|
| Planning | Architect, Lead | Critique, Scope, Research, Plan |
| Execution | Senior, Tester, Dev, Debugger (on-call) | Design Review, Test Authoring (RED), Implementation |
| Quality | QA Lead, QA Code, Senior (escalation) | Code Review, QA, Security |

## Escalation Chain (STRICT — NO LEVEL SKIPPING)

```
Dev → Senior → Lead → Architect → Owner → User
```

| Agent | Escalates to | Trigger |
|-------|-------------|---------|
| Dev | Senior | Blocker, spec unclear, 2 task failures, architectural issue |
| Senior | Lead | Can't resolve Dev blocker, design conflict, code review cycle 2 fail |
| Lead | Architect | Can't resolve Senior escalation, design problem, cross-phase issue |
| Architect | Owner (or User if no Owner) | Design-level decision needed, scope change required |
| Tester | Senior | `ts` field unclear, tests pass unexpectedly |
| QA Lead | Lead | Verification findings, FAIL result |
| QA Code | Lead | Critical/major findings, FAIL result |

**Rules:**
1. Each agent escalates ONLY to their direct report-to. No skipping.
2. Dev NEVER contacts Lead, Architect, or User. Senior is Dev's single contact.
3. QA/Tester NEVER contact Architect. Findings route through Lead.
4. Only Architect escalates to Owner/User.

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

Backend agents write to project source directories and `.vbw-planning/phases/`.
Backend agents MUST NOT write to `frontend/`, `design/`, `styles/`, `components/` directories owned by other departments (enforced by `department-guard.sh` hook).
