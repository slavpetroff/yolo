# YOLO Codebase Patterns

Recurring patterns identified across the codebase.

## Architectural Patterns

### 1. Hook Wrapper (DXP-01)
All 19+ hooks route through `hook-wrapper.sh` for graceful degradation. Script errors are logged (not fatal). Exit 2 = intentional block (JSON deny format).

**Files:** hooks/hooks.json, scripts/hook-wrapper.sh

### 2. Plugin Cache Resolution
`ls | sort -V | tail -1` pattern. Never glob expansion. Cache stored in `/tmp/yolo-vdir-$(id -u)` for per-session reuse.

**Files:** scripts/hook-wrapper.sh, scripts/session-start.sh

### 3. Progressive Context Narrowing
Lower agents receive less context. Dev sees only `spec` field. Senior sees plan + architecture. Lead sees architecture + ROADMAP. Per-agent field filtering via `filter-agent-context.sh` (11 roles x 10 artifact types).

**Files:** references/execute-protocol.md, scripts/compile-context.sh, scripts/filter-agent-context.sh, references/agent-field-map.md

### 4. Commit-Every-Artifact
Every persistent artifact committed immediately. Enables crash recovery -- resume from any point.

**Files:** references/execute-protocol.md (exit gates), references/company-hierarchy.md

### 5. Verification Gate Protocol
Entry/exit gates on every step. Entry: verify predecessor artifact. Exit: update .execution-state.json, commit. Skip: record reason, advance.

**Files:** references/execute-protocol.md, scripts/validate-gates.sh

### 6. Dual Spawn Strategy
Task tool (default) and Teammate API (experimental) as interchangeable transport layers. Same schemas, escalation chains, and artifact formats in both modes.

**Files:** references/teammate-api-patterns.md, scripts/resolve-team-mode.sh

### 7. Fallback Cascade
3 tiers: Teammate API -> Task tool -> Error. Per-department isolation. Circuit breaker: 2 failures = open state, probe after 5 minutes. Health tracking via SendMessage response patterns.

**Files:** references/teammate-api-patterns.md ## Fallback Cascade, agents/yolo-lead.md

### 8. Dynamic Persona Adaptation
Project type detected via weighted signals. Department conventions injected into TOON templates. Tool permissions adjusted per project type per role.

**Files:** config/project-types.json, scripts/detect-stack.sh, scripts/generate-department-toons.sh, scripts/resolve-tool-permissions.sh

### 9. On-Demand Agent Registration
In teammate mode, agents registered at workflow step boundaries (not all at once). Core specialists at team creation. Tester at step 6. QA at step 9. Security at step 10 (backend only).

**Files:** references/teammate-api-patterns.md ## Registering Teammates

### 10. Summary Ownership Split
task mode: Dev writes summary.jsonl. teammate mode: Lead aggregates task_complete messages and writes. Exactly one writer per plan in both modes.

**Files:** references/execute-protocol.md ## Step 7, agents/yolo-dev.md, agents/yolo-lead.md

### 11. QA Gate Cascade (NEW in 0.2.2)
Three-level script-only validation: post-task (30s, scoped) -> post-plan (300s, full) -> post-phase (300s, full + gates). Gates run BEFORE expensive agent spawns. Fail-open on infrastructure missing. Results persisted to .qa-gate-results.jsonl via flock-based serialization.

**Files:** scripts/qa-gate-post-task.sh, scripts/qa-gate-post-plan.sh, scripts/qa-gate-post-phase.sh, references/qa-gate-integration.md

### 12. Review Ownership (NEW in 0.2.2)
16 reviewing agents adopt personal ownership language for subordinate output. Ownership matrix maps agent -> artifact -> review authority -> step. Non-reviewing agents excluded.

**Files:** references/review-ownership-patterns.md, agents/yolo-senior.md, agents/yolo-lead.md, agents/yolo-architect.md

### 13. Hard Enforcement Hooks (NEW in 0.2.2)
block-plan-mode.sh uses JSON `{"permissionDecision":"deny"}` format to hard-block EnterPlanMode/ExitPlanMode at the hook level. Distinct from fail-open hooks.

**Files:** scripts/block-plan-mode.sh, hooks/hooks.json

### 14. Escalation Round-Trip (NEW in Phase 5)
Bidirectional escalation: Dev->Senior->Lead->Architect->User (upward) and User->go.md->Owner->Lead->Senior->Dev (downward). Each level transforms the message. Timeout auto-escalation via check-escalation-timeout.sh (configurable, default 300s). State tracked in .execution-state.json escalations array. Two new schemas (escalation_resolution, escalation_timeout_warning) bring total from 27 to 29.

**Files:** references/execute-protocol.md, commands/go.md, agents/yolo-lead.md, agents/yolo-senior.md, agents/yolo-dev.md, agents/yolo-owner.md, agents/yolo-architect.md, references/company-hierarchy.md, references/handoff-schemas.md, config/defaults.json, scripts/check-escalation-timeout.sh

## Naming Patterns

| Category | Pattern | Example |
|----------|---------|---------|
| Scripts | kebab-case.sh | validate-commit.sh |
| Agents | yolo-{role}.md / yolo-{dept}-{role}.md | yolo-lead.md, yolo-fe-dev.md |
| Commands | kebab-case.md | go.md, config.md |
| Phases | {NN}-{slug}/ | 01-auth/ |
| Plans | {NN-MM}.plan.jsonl | 01-01.plan.jsonl |
| Summaries | {NN-MM}.summary.jsonl | 01-01.summary.jsonl |
| QA gate results | .qa-gate-results.jsonl | (per phase, append-only) |
| Context | .ctx-{role}.toon | .ctx-lead.toon |
| Ref packages | {role}.toon | architect.toon |
| Dept templates | {dept}.toon.tmpl | backend.toon.tmpl |
| Dept status | .dept-status-{dept}.json | .dept-status-backend.json |
| Handoff sentinel | .handoff-{gate-name} | .handoff-ux-complete |
| Commits | {type}({scope}): {desc} | feat(auth): add JWT middleware |

## Quality Patterns

### 1. JSONL Abbreviated Keys
85-93% token savings. Plan header: p/n/t/w/d/obj/eff/fm/mh. Tasks: id/tp/a/f/spec/ts/done/td. QA gate results: gl/r/plan/task/tst/dur/f/dt/tm.

### 2. TOON Format
Token-optimized notation. Compiled context not committed (regenerated). Reference packages committed and pre-compiled.

### 3. Fail-Closed Security, Fail-Open Features
security-filter.sh: fails closed. file-guard.sh: fails open. block-plan-mode.sh: fails closed. QA gates: fail open. Security never accidentally bypassed; features degrade gracefully.

### 4. Single-Line YAML Descriptions
Mandatory for all agent and command frontmatter. Enforced by validate-frontmatter.sh.

### 5. Test Categories (6 Layers)
static (conventions) -> unit (per-script) -> containment (isolation) -> integration (E2E) -> behavioral (teammate API) -> performance (benchmarks)

### 6. Serialized Commits
flock-based locking via git-commit-serialized.sh for parallel Dev execution. Prevents index.lock conflicts. QA gate results also flock-serialized.

### 7. Config-Driven Gate Control (NEW in 0.2.2)
qa_gates object in config: post_task, post_plan, post_phase booleans + timeout_seconds + failure_threshold enum. resolve-qa-config.sh merges project config with defaults. Null-safe jq checks.

## Dependency Patterns

### 1. Zero External Dependencies
bash + jq + git + curl. No npm/pip/cargo. Enforced by CONTRIBUTING.md.

### 2. Config-Driven Behavior
defaults.json, model-profiles.json, project-types.json, tool-permissions.json all read at runtime. qa_gates config controls gate behavior.

### 3. Version Sync (3 files)
VERSION, plugin.json, marketplace.json. Automated by bump-version.sh. Enforced by pre-push hook.

### 4. File-Based Cross-Department Coordination
Cross-team communication always file-based (even in teammate mode). Handoff sentinels, dept-status files, api-contracts.jsonl. dept-gate.sh validates all gates.

## Concern Patterns

### 1. Critical Enforcement Rules
Never bypass /yolo:go. EnterPlanMode prohibited (hard hook enforcement). No ad-hoc agents. Department isolation at hook level.

### 2. Graceful Degradation
Hooks fail-open (log, exit 0). Exception: security + plan-mode (fail-closed). Teammate API falls back to Task tool. QA gates fail-open on infrastructure missing.

### 3. Experimental API Risk
Teammate API depends on env var. Mitigated by fallback cascade, circuit breaker, per-department isolation.

### 4. QA Gate System Risk (NEW in 0.2.2)
Three levels add failure modes. Flock contention in parallel Dev. Scoped mode may miss regressions. Mitigated by fail-open default, exponential backoff, full suite at post-plan level.

---
