# YOLO Execution Protocol

Loaded on demand by /yolo:go Execute mode. Not a user-facing command.

Implements the 10-step company-grade engineering workflow. See `references/company-hierarchy.md` for full hierarchy and `references/artifact-formats.md` for JSONL schemas.

## Owner-First Communication Rule

**No agent in the execution chain communicates directly with the user.** All user interaction flows through go.md (which acts as the Owner proxy). If any agent encounters an issue requiring user input, it escalates UP the chain (Dev → Senior → Lead → Owner/go.md → User). The user never hears from a Dev, Senior, QA, or Lead agent directly.

## Pre-Execution

1. **Parse arguments:** Phase number (auto-detect if omitted), --effort, --skip-qa, --skip-security, --plan=NN.
2. **Run execute guards:**
   - Not initialized: STOP "Run /yolo:init first."
   - No plans in phase dir: STOP "Phase {N} has no plans. Run `/yolo:go --plan {N}` first."
   - All plans have summary.jsonl: cautious/standard → WARN + confirm; confident/pure-yolo → warn + continue.
3. **Resolve models for all agents:**
   ```bash
   for role in critic architect lead senior tester dev qa qa-code security; do
     eval "${role^^}_MODEL=\$(bash \${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-model.sh $role .yolo-planning/config.json \${CLAUDE_PLUGIN_ROOT}/config/model-profiles.json)"
   done
   ```

### Context Scoping Protocol (MANDATORY)

Each agent receives ONLY what it needs. Context flows down the hierarchy with progressive scoping — lower agents see less, not more. This prevents context bleed and ensures clean delegation.

When spawning each agent via Task tool, include ONLY the listed inputs. Do NOT pass extra context "for reference."

| Step | Agent | Receives (include in Task prompt) | NEVER pass |
|------|-------|----------------------------------|-----------|
| 1 | Critic | reqs.jsonl, PROJECT.md, codebase/, research.jsonl, dept CONTEXT (if multi-dept) | plans, code-review, QA artifacts |
| 2 | Architect | reqs.jsonl, codebase/, research.jsonl, critique.jsonl, dept CONTEXT | implementation code, QA artifacts |
| 3 | Lead | architecture.toon, reqs.jsonl, ROADMAP, prior summaries | critique.jsonl directly (addressed in architecture), QA artifacts |
| 4 | Senior (Review) | plan.jsonl, architecture.toon, codebase patterns | full CONTEXT, ROADMAP, other dept artifacts |
| 5 | Tester | enriched plan.jsonl (tasks with `ts`), codebase patterns | architecture.toon, CONTEXT, critique.jsonl |
| 6 | Dev | enriched plan.jsonl (`spec` + `ts` fields), test files | architecture.toon, CONTEXT, critique.jsonl, ROADMAP |
| 7 | Senior (Review) | plan.jsonl, git diff, test-plan.jsonl | CONTEXT, ROADMAP |
| 8 | QA | plan.jsonl, summary.jsonl, .ctx-qa.toon | CONTEXT, architecture.toon |
| 9 | Security | summary.jsonl (file list), .ctx-security.toon | CONTEXT, plans |

**Key principle:** Dev receives the enriched `spec` field as its COMPLETE instruction set. If spec is unclear, Dev escalates to Senior — never reads more context files.

**Escalation context flow:** When an agent escalates UP, the receiving agent has broader context to resolve. When resolution pushes back DOWN, it comes as an updated artifact (amended spec, architecture addendum), not as raw context files.

### Step 1: Critique / Brainstorm (Critic Agent)

**Guard:** Skip if `--effort=turbo` or critique.jsonl already exists in phase directory.

1. Compile context: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/compile-context.sh {phase} critic {phases_dir}`
2. Spawn yolo-critic with Task tool:
   - model: "${CRITIC_MODEL}"
   - Provide: reqs.jsonl (or REQUIREMENTS.md), PROJECT.md, codebase/ mapping, research.jsonl (if exists)
   - Include compiled context: `{phase-dir}/.ctx-critic.toon`
   - Effort: if `--effort=fast`, instruct Critic to limit to `critical` findings only
3. Display: `◆ Spawning Critic (${CRITIC_MODEL})...` → `✓ Critique complete`
4. Critic returns findings via SendMessage (Critic has no Write tool).
5. Write critique.jsonl from Critic's findings to phase directory.
6. Commit: `docs({phase}): critique and gap analysis`
7. **User gate (balanced/thorough effort):** Display critique summary. If critical findings exist, AskUserQuestion "Address these before architecture?" Options: "Proceed (Architect will address)" / "Pause to discuss".

### Step 2: Architecture (Architect Agent)

**Guard:** Skip if architecture.toon already exists in phase directory.

1. Compile context: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/compile-context.sh {phase} architect {phases_dir}`
2. Spawn yolo-architect with Task tool:
   - model: "${ARCHITECT_MODEL}"
   - Provide: reqs.jsonl (or REQUIREMENTS.md), codebase/ mapping, research.jsonl (if exists), critique.jsonl (if exists)
   - Include compiled context: `{phase-dir}/.ctx-architect.toon`
3. Display: `◆ Spawning Architect (${ARCHITECT_MODEL})...` → `✓ Architecture complete`
4. Verify: architecture.toon exists in phase directory.
5. Architect addresses critique.jsonl findings (updates `st` field) and commits: `docs({phase}): architecture design`

### Step 3: Load Plans and Detect Resume State

1. Glob `*.plan.jsonl` in phase dir. Read each plan header (line 1, parse with jq).
2. Check existing summary.jsonl files (complete plans).
3. `git log --oneline -20` for committed tasks (crash recovery).
4. Build remaining plans list. If `--plan=NN`, filter to that plan.
5. Partially-complete plans: note resume-from task number.
6. **Crash recovery:** If `.yolo-planning/.execution-state.json` exists with `"status": "running"`, reconcile plan statuses with summary.jsonl state.
7. **Write execution state** to `.yolo-planning/.execution-state.json`:
   ```json
   {
     "phase": N, "phase_name": "{slug}", "status": "running",
     "started_at": "{ISO 8601}", "step": "planning", "wave": 1, "total_waves": N,
     "plans": [{"id": "NN-MM", "title": "...", "wave": W, "status": "pending|complete"}]
   }
   ```
   Commit: `chore(state): execution state phase {N}`
8. **Cross-phase deps:** For each plan with `xd` (cross_phase_deps):
   - Verify referenced plan's summary.jsonl exists with `s: complete`
   - If artifact path specified, verify file exists
   - Unsatisfied → STOP with fix instructions
   - All satisfied: `✓ Cross-phase dependencies verified`

### Step 4: Design Review (Senior Agent)

**Delegation directive:** You are the Lead. NEVER implement tasks yourself.

1. Update execution state: `"step": "design_review"`
2. Compile context: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/compile-context.sh {phase} senior {phases_dir}`
3. For each plan.jsonl without enriched specs (tasks missing `spec` field):
   - Spawn yolo-senior with Task tool:
     - model: "${SENIOR_MODEL}"
     - Mode: "design_review"
     - Provide: plan.jsonl path, architecture.toon path, critique.jsonl path (if exists), compiled context
   - Display: `◆ Spawning Senior for design review ({plan})...`
4. Senior reads plan, researches codebase, enriches each task with `spec` field AND `ts` (test_spec) field.
5. Senior commits enriched plan: `docs({phase}): enrich plan {NN-MM} specs`
6. Verify: all tasks in plan.jsonl have non-empty `spec` field. Tasks with testable logic should have `ts` field.

### Step 5: Test Authoring — RED Phase (Tester Agent)

**Guard:** Skip if `--effort=turbo` or no tasks have `ts` fields in any plan.jsonl.

1. Update execution state: `"step": "test_authoring"`
2. Compile context: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/compile-context.sh {phase} tester {phases_dir} {plan_path}`
3. For each plan.jsonl with tasks that have `ts` fields:
   - Spawn yolo-tester with Task tool:
     - model: "${TESTER_MODEL}"
     - Provide: enriched plan.jsonl path, compiled context
   - Display: `◆ Spawning Tester (${TESTER_MODEL}) for RED phase ({plan})...`
4. Tester writes failing test files per `ts` specifications.
5. Tester verifies ALL tests FAIL (RED confirmation).
6. Tester produces test-plan.jsonl and commits: `test({phase}): RED phase tests for plan {NN-MM}`
7. Verify: test-plan.jsonl exists with `red: true` for all entries.
8. Display: `✓ RED phase complete — {N} test files, {M} test cases (all failing)`

### Step 6: Implementation (Dev Agents)

1. Update execution state: `"step": "implementation"`
2. Compile context: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/compile-context.sh {phase} dev {phases_dir} {plan_path}`
3. For each uncompleted plan, TaskCreate:
   ```
   subject: "Execute {NN-MM}: {plan-title}"
   description: |
     Execute all tasks in {PLAN_PATH}.
     Effort: {DEV_EFFORT}. Working directory: {pwd}.
     Phase context: {phase-dir}/.ctx-dev.toon (if compiled)
     TDD: test-plan.jsonl exists — verify RED before implementing, verify GREEN after.
     {If resuming: "Resume from Task {N}. Tasks 1-{N-1} already committed."}
   activeForm: "Executing {NN-MM}"
   ```
   **CRITICAL:** Pass `model: "${DEV_MODEL}"` to Task tool.
4. Wire dependencies via TaskUpdate: `addBlockedBy` from plan `d` (depends_on) field.
5. Spawn Dev teammates and assign tasks.
6. Display: `◆ Spawning Dev (${DEV_MODEL})...`

**Dev TDD protocol:**
- Before each task with `ts`: run tests, verify FAIL (RED). If tests pass → escalate to Senior.
- After implementing: run tests, verify PASS (GREEN). If fail after 3 attempts → escalate to Senior.

**Dev escalation chain:** Dev → Senior (not Lead). If Dev sends `dev_blocker`, route to Senior.

**Summary verification gate (mandatory):**
When Dev reports completion:
1. Verify `{phase_dir}/{plan_id}.summary.jsonl` exists with valid JSONL.
2. If missing: message Dev to write it. If unavailable: write from git log.
3. Only after verification: mark plan `"complete"` in .execution-state.json.

### Step 7: Code Review (Senior Agent)

1. Update execution state: `"step": "code_review"`
2. For each completed plan:
   - Spawn yolo-senior with Task tool:
     - model: "${SENIOR_MODEL}"
     - Mode: "code_review"
     - Provide: plan.jsonl path, git diff of plan commits, test-plan.jsonl (if exists)
   - Display: `◆ Spawning Senior for code review ({plan})...`
3. Senior reviews code, produces code-review.jsonl.
4. Senior checks TDD compliance: test files exist, tests pass, `tdd` field in verdict.
5. If `r: "changes_requested"`:
   - Senior sends exact fix instructions to Dev via `code_review_changes` schema.
   - Dev fixes per Senior's instructions exactly — no creative interpretation.
   - Dev recommits, Senior re-reviews (cycle 2).
   - After cycle 2 still failing → Senior escalates to Lead.
   - Lead decides: accept with known issues OR escalate to Architect for design change.
6. If `r: "approve"`:
   - If `config.approval_gates.code_review` is true → pause, display review summary, AskUserQuestion "Proceed to QA?" Options: "Proceed" / "Review changes".
   - Otherwise → proceed to Step 8.
7. Senior commits: `docs({phase}): code review {NN-MM}`
8. Verify: code-review.jsonl exists with `r: "approve"`.

### Step 8: QA (QA Lead + QA Code)

If `--skip-qa` or turbo: `○ QA skipped ({reason})`

1. Update execution state: `"step": "qa"`
2. **Tier resolution:** turbo=skip, fast=quick, balanced=standard, thorough=deep.
3. Compile context:
   - `bash ${CLAUDE_PLUGIN_ROOT}/scripts/compile-context.sh {phase} qa {phases_dir}`
   - `bash ${CLAUDE_PLUGIN_ROOT}/scripts/compile-context.sh {phase} qa-code {phases_dir}`

**QA Lead (plan-level):**
4. Spawn yolo-qa:
   - model: "${QA_MODEL}"
   - Provide: plan.jsonl files, summary.jsonl files, compiled context
   - Tier: {tier}
5. QA Lead produces verification.jsonl. Commits: `docs({phase}): verification results`

**QA Code (code-level):**
6. Spawn yolo-qa-code:
   - model: "${QA_CODE_MODEL}"
   - Provide: summary.jsonl (for file list), test-plan.jsonl (for TDD compliance), compiled context
   - Tier: {tier}
7. QA Code runs TDD compliance (Phase 0), tests, lint, patterns. Produces qa-code.jsonl. Commits: `docs({phase}): code quality review`

**Result handling:**
- Both PASS → Manual QA (if enabled) → Step 9 (or Step 10 if security disabled)
- QA Lead FAIL → remediation plan → Lead assigns → Senior re-specs → Dev fixes → re-verify (max 2 cycles)
- QA Code PARTIAL/FAIL → **remediation loop:**
  1. QA Code writes `gaps.jsonl` with `st: "open"` entries (critical/major findings).
  2. Lead assigns gaps to Dev (via Senior re-spec if needed).
  3. Dev reads gaps.jsonl, fixes each `st: "open"` gap, marks `st: "fixed"` with commit hash.
  4. QA Code re-verifies (re-run Phase 0-3 checks on modified files).
  5. Max 2 remediation cycles. After cycle 2:
     - Still FAIL → Lead escalates to Senior for architectural review.
     - 3rd failure → Lead escalates to Architect to re-evaluate design.
- If `config.approval_gates.qa_fail` is true: pause for user approval before remediation.

**Manual QA (config-controlled):**

If `config.approval_gates.manual_qa` is true AND effort is NOT turbo/fast AND `--skip-qa` not set:

8. **Present manual test checklist** to user:
   - Extract from plan.jsonl `mh.tr` (truths/invariants) — human-testable assertions
   - Extract from plan.jsonl task `done` fields — done criteria per task
   - Present as numbered checklist: `MQ-1: {test description}` etc.
9. **User marks results**: AskUserQuestion for each test group (pass/fail + notes).
10. **Record results** in `manual-qa.jsonl`:
    ```jsonl
    {"r":"PASS|FAIL|PARTIAL","tests":[{"id":"MQ-1","desc":"Login flow works","r":"pass","notes":""}],"dt":"YYYY-MM-DD"}
    ```
    Commit: `docs({phase}): manual QA results`
11. **Escalation on failure** (ALL routed through Lead):
    - Critical failure → Lead escalates to Architect for design re-evaluation
    - Major/minor failure → Lead assigns to Senior for re-spec → Dev fixes
    - After fix → re-run manual QA for failed items only
12. If all PASS (automated + manual) → proceed to Step 9.

### Step 9: Security Audit (optional)

If `--skip-security` or config `security_audit` != true: `○ Security audit skipped`

1. Update execution state: `"step": "security"`
2. Compile context: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/compile-context.sh {phase} security {phases_dir}`
3. Spawn yolo-security:
   - model: "${SECURITY_MODEL}"
   - Provide: summary.jsonl (file list), compiled context
4. Security produces security-audit.jsonl. Commits: `docs({phase}): security audit`
5. If `r: "FAIL"`: **HARD STOP**. Display findings. Only user `--force` overrides.
6. If `r: "WARN"`:
   - Display warnings.
   - If `config.approval_gates.security_warn` is true: pause for user approval.
   - Otherwise: continue.
7. If `r: "PASS"`: continue.

### Step 10: Sign-off (Lead)

1. Update execution state: `"step": "signoff"`
2. Review all artifacts:
   - critique.jsonl: all findings addressed or deferred?
   - code-review.jsonl: all approved? TDD compliance?
   - verification.jsonl: PASS or PARTIAL (with accepted gaps)?
   - qa-code.jsonl: PASS? TDD coverage?
   - security-audit.jsonl: PASS or WARN?
3. Decision:
   - All good → SHIP (mark phase complete)
   - Issues remain → HOLD (generate remediation instructions)
4. **Shutdown teammates:** Send shutdown to each, wait for approval, clean up.
5. **Update state:**
   - .execution-state.json: `"status": "complete"`, `"step": "signoff"`
   - ROADMAP.md: mark phase complete
   - Commit: `chore(state): phase {N} complete`
6. Display per `@${CLAUDE_PLUGIN_ROOT}/references/yolo-brand-essentials.toon`:
   ```
   ╔═══════════════════════════════════════════════╗
   ║  Phase {N}: {name} — Built                    ║
   ╚═══════════════════════════════════════════════╝

     Plan Results:
       ✓ Plan 01: {title}  /  ✗ Plan 03: {title} (failed)

     Metrics:
       Plans: {completed}/{total}  Effort: {profile}
       Code Review: {approve/changes}  QA: {PASS|PARTIAL|FAIL}
       TDD: {red_green|green_only|no_tests}
       Security: {PASS|WARN|FAIL|skipped}

     Deviations: {count}
   ```
7. Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/suggest-next.sh execute {qa-result}`

## Execution State Transitions

| Step | state.step | Commits |
|------|-----------|---------|
| Critique | critique | critique.jsonl |
| Architecture | architecture | architecture.toon |
| Load Plans | planning | .execution-state.json |
| Design Review | design_review | enriched plan.jsonl |
| Test Authoring | test_authoring | test files + test-plan.jsonl |
| Implementation | implementation | source code + summary.jsonl |
| Code Review | code_review | code-review.jsonl |
| QA | qa | verification.jsonl + qa-code.jsonl |
| Security | security | security-audit.jsonl |
| Sign-off | signoff | state.json + ROADMAP.md |

Each transition commits .execution-state.json so resume works on exit.

## Multi-Department Execution

**Detection:** Check `multi_dept` from resolve-departments.sh output (pre-computed in go.md context).
- If `multi_dept=false`: SKIP this section entirely. The standard 10-step above is sufficient.
- If `multi_dept=true`: Follow the multi-department flow below.

**Protocol files (MUST Read when multi_dept=true):**
- `references/multi-dept-protocol.md` — Full dispatch sequence, department tracking, Owner review
- `references/cross-team-protocol.md` — Handoff gates, communication rules, workflow modes

### Multi-Department Pre-Execution

In addition to standard pre-execution (resolve models for Steps 1-10 above):

1. **Resolve models for all active department agents:**
   ```bash
   # Owner (always for multi-dept)
   OWNER_MODEL=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-model.sh owner .yolo-planning/config.json ${CLAUDE_PLUGIN_ROOT}/config/model-profiles.json)

   # Frontend agents (if fe_active=true)
   if [[ "$fe_active" == "true" ]]; then
     for role in architect lead senior tester dev qa qa-code; do
       eval "FE_${role^^}_MODEL=\$(bash \${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-model.sh fe-$role .yolo-planning/config.json \${CLAUDE_PLUGIN_ROOT}/config/model-profiles.json)"
     done
   fi

   # UI/UX agents (if ux_active=true)
   if [[ "$ux_active" == "true" ]]; then
     for role in architect lead senior tester dev qa qa-code; do
       eval "UX_${role^^}_MODEL=\$(bash \${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-model.sh ux-$role .yolo-planning/config.json \${CLAUDE_PLUGIN_ROOT}/config/model-profiles.json)"
     done
   fi
   ```

2. **Validate department readiness:**
   - If `fe_active=true`: verify all 7 `yolo-fe-*.md` agent files exist
   - If `ux_active=true`: verify all 7 `yolo-ux-*.md` agent files exist
   - Verify `references/departments/{dept}.md` for each active department
   - Verify `references/cross-team-protocol.md` exists

### Multi-Department Dispatch Flow

Follow `workflow` variable and `leads_to_spawn` from resolve-departments.sh:

**Step 0a: Owner Context Gathering + Splitting** (if `{phase}-CONTEXT-backend.md` does NOT exist)
The Owner is the SOLE point of contact with the user — no department lead talks to user directly.
1. go.md acts as Owner proxy: run questionnaire via AskUserQuestion (2-3 rounds: vision, dept-specific, gaps/features/constraints). Keep asking until ZERO ambiguity.
2. Split into department-specific context files (NO bleed): `{phase}-CONTEXT-backend.md`, `{phase}-CONTEXT-uiux.md`, `{phase}-CONTEXT-frontend.md`. Each contains ONLY that department's concerns.
3. If department context files already exist (from Plan Mode): skip to Step 0b.
4. Display: `◆ Owner gathering context...` → `✓ Context gathered — split into dept briefs`

**Step 0b: Owner Critique Review** (balanced/thorough effort only)
1. Run shared Critic (Step 1 above) as normal.
2. Spawn yolo-owner (model: "${OWNER_MODEL}") with `owner_review` mode.
3. Input: critique.jsonl, reqs.jsonl, department config, CONTEXT.md.
4. Owner determines department priorities and dispatch order.
5. Display: `◆ Spawning Owner for critique review...` → `✓ Owner review complete`

**Steps 1-10: Per-Department Execution**

Each active department runs the SAME 10-step workflow above, using department-prefixed agents:
- Backend: yolo-critic, yolo-architect, yolo-lead, yolo-senior, yolo-tester, yolo-dev, yolo-qa, yolo-qa-code
- Frontend (if active): yolo-fe-architect, yolo-fe-lead, yolo-fe-senior, yolo-fe-tester, yolo-fe-dev, yolo-fe-qa, yolo-fe-qa-code
- UI/UX (if active): yolo-ux-architect, yolo-ux-lead, yolo-ux-senior, yolo-ux-tester, yolo-ux-dev, yolo-ux-qa, yolo-ux-qa-code

Dispatch order follows `leads_to_spawn` pattern from resolve-departments.sh:
- **Parallel workflow**: UX department runs first (if active) → Handoff Gate → FE + BE run in parallel
- **Sequential workflow**: UX → FE → BE (strict sequential)

**Handoff gates** (from cross-team-protocol.md):
- After UX completes: validate design-handoff.jsonl, design-tokens.jsonl, component-specs.jsonl exist
- After FE+BE complete: validate api_contract status
- Integration QA: cross-department verification
- Shared Security: per-department audit
- Owner Sign-off: final SHIP/HOLD decision

### Multi-Department Execution State

`.execution-state.json` gains department tracking when multi_dept=true:
```json
{
  "phase": 1,
  "departments": {
    "uiux": {"status": "complete", "step": "signoff", "result": "PASS"},
    "frontend": {"status": "running", "step": "implementation"},
    "backend": {"status": "running", "step": "code_review"}
  },
  "integration_qa": "pending",
  "owner_signoff": "pending"
}
```

### Multi-Department Sign-off

Replaces standard Step 10 when multi_dept=true:
1. Each department Lead sends `department_result` to Owner.
2. Integration QA runs cross-department verification.
3. Shared Security runs per-department audit.
4. Owner reviews all results → SHIP or HOLD.
5. Owner sends `owner_signoff` to all department Leads.
6. Display multi-department phase banner (see `references/yolo-brand-essentials.toon`).

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/yolo-brand-essentials.toon — Phase Banner, ◆ running, ✓ complete, ✗ failed, ○ skipped, no ANSI color codes.
