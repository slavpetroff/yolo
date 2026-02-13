# VBW Execution Protocol

Loaded on demand by /vbw:vibe Execute mode. Not a user-facing command.

Implements the 8-step company-grade engineering workflow. See `references/company-hierarchy.md` for full hierarchy and `references/artifact-formats.md` for JSONL schemas.

## Pre-Execution

1. **Parse arguments:** Phase number (auto-detect if omitted), --effort, --skip-qa, --skip-security, --plan=NN.
2. **Run execute guards:**
   - Not initialized: STOP "Run /vbw:init first."
   - No plans in phase dir: STOP "Phase {N} has no plans. Run `/vbw:vibe --plan {N}` first."
   - All plans have summary.jsonl: cautious/standard → WARN + confirm; confident/pure-vibe → warn + continue.
3. **Resolve models for all agents:**
   ```bash
   ARCHITECT_MODEL=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-model.sh architect .vbw-planning/config.json ${CLAUDE_PLUGIN_ROOT}/config/model-profiles.json)
   LEAD_MODEL=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-model.sh lead .vbw-planning/config.json ${CLAUDE_PLUGIN_ROOT}/config/model-profiles.json)
   SENIOR_MODEL=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-model.sh senior .vbw-planning/config.json ${CLAUDE_PLUGIN_ROOT}/config/model-profiles.json)
   DEV_MODEL=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-model.sh dev .vbw-planning/config.json ${CLAUDE_PLUGIN_ROOT}/config/model-profiles.json)
   QA_MODEL=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-model.sh qa .vbw-planning/config.json ${CLAUDE_PLUGIN_ROOT}/config/model-profiles.json)
   QA_CODE_MODEL=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-model.sh qa-code .vbw-planning/config.json ${CLAUDE_PLUGIN_ROOT}/config/model-profiles.json)
   SECURITY_MODEL=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-model.sh security .vbw-planning/config.json ${CLAUDE_PLUGIN_ROOT}/config/model-profiles.json)
   ```

### Step 1: Architecture (Architect Agent)

**Guard:** Skip if architecture.toon already exists in phase directory.

1. Compile context: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/compile-context.sh {phase} architect {phases_dir}`
2. Spawn vbw-architect with Task tool:
   - model: "${ARCHITECT_MODEL}"
   - Provide: reqs.jsonl (or REQUIREMENTS.md), codebase/ mapping, research.jsonl (if exists)
   - Include compiled context: `{phase-dir}/.ctx-architect.toon`
3. Display: `◆ Spawning Architect (${ARCHITECT_MODEL})...` → `✓ Architecture complete`
4. Verify: architecture.toon exists in phase directory.
5. Architect commits: `docs({phase}): architecture design`

### Step 2: Load Plans and Detect Resume State

1. Glob `*.plan.jsonl` in phase dir. Read each plan header (line 1, parse with jq).
2. Check existing summary.jsonl files (complete plans).
3. `git log --oneline -20` for committed tasks (crash recovery).
4. Build remaining plans list. If `--plan=NN`, filter to that plan.
5. Partially-complete plans: note resume-from task number.
6. **Crash recovery:** If `.vbw-planning/.execution-state.json` exists with `"status": "running"`, reconcile plan statuses with summary.jsonl state.
7. **Write execution state** to `.vbw-planning/.execution-state.json`:
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

### Step 3: Design Review (Senior Agent)

**Delegation directive:** You are the Lead. NEVER implement tasks yourself.

1. Update execution state: `"step": "design_review"`
2. Compile context: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/compile-context.sh {phase} senior {phases_dir}`
3. For each plan.jsonl without enriched specs (tasks missing `spec` field):
   - Spawn vbw-senior with Task tool:
     - model: "${SENIOR_MODEL}"
     - Mode: "design_review"
     - Provide: plan.jsonl path, architecture.toon path, compiled context
   - Display: `◆ Spawning Senior for design review ({plan})...`
4. Senior reads plan, researches codebase, enriches each task with `spec` field.
5. Senior commits enriched plan: `docs({phase}): enrich plan {NN-MM} specs`
6. Verify: all tasks in plan.jsonl have non-empty `spec` field.

### Step 4: Implementation (Dev Agents)

1. Update execution state: `"step": "implementation"`
2. Compile context: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/compile-context.sh {phase} dev {phases_dir} {plan_path}`
3. For each uncompleted plan, TaskCreate:
   ```
   subject: "Execute {NN-MM}: {plan-title}"
   description: |
     Execute all tasks in {PLAN_PATH}.
     Effort: {DEV_EFFORT}. Working directory: {pwd}.
     Phase context: {phase-dir}/.ctx-dev.toon (if compiled)
     {If resuming: "Resume from Task {N}. Tasks 1-{N-1} already committed."}
   activeForm: "Executing {NN-MM}"
   ```
   **CRITICAL:** Pass `model: "${DEV_MODEL}"` to Task tool.
4. Wire dependencies via TaskUpdate: `addBlockedBy` from plan `d` (depends_on) field.
5. Spawn Dev teammates and assign tasks.
6. Display: `◆ Spawning Dev (${DEV_MODEL})...`

**Dev escalation chain:** Dev → Senior (not Lead). If Dev sends `dev_blocker`, route to Senior.

**Summary verification gate (mandatory):**
When Dev reports completion:
1. Verify `{phase_dir}/{plan_id}.summary.jsonl` exists with valid JSONL.
2. If missing: message Dev to write it. If unavailable: write from git log.
3. Only after verification: mark plan `"complete"` in .execution-state.json.

### Step 5: Code Review (Senior Agent)

1. Update execution state: `"step": "code_review"`
2. For each completed plan:
   - Spawn vbw-senior with Task tool:
     - model: "${SENIOR_MODEL}"
     - Mode: "code_review"
     - Provide: plan.jsonl path, git diff of plan commits
   - Display: `◆ Spawning Senior for code review ({plan})...`
3. Senior reviews code, produces code-review.jsonl.
4. If `r: "changes_requested"`:
   - Route changes to Dev via Senior's instructions.
   - Dev fixes, Senior re-reviews. Max 2 cycles.
   - After cycle 2: escalate to Lead for decision.
5. Senior commits: `docs({phase}): code review {NN-MM}`
6. Verify: code-review.jsonl exists with `r: "approve"`.

### Step 6: QA (QA Lead + QA Code)

If `--skip-qa` or turbo: `○ QA skipped ({reason})`

1. Update execution state: `"step": "qa"`
2. **Tier resolution:** turbo=skip, fast=quick, balanced=standard, thorough=deep.
3. Compile context:
   - `bash ${CLAUDE_PLUGIN_ROOT}/scripts/compile-context.sh {phase} qa {phases_dir}`
   - `bash ${CLAUDE_PLUGIN_ROOT}/scripts/compile-context.sh {phase} qa-code {phases_dir}`

**QA Lead (plan-level):**
4. Spawn vbw-qa:
   - model: "${QA_MODEL}"
   - Provide: plan.jsonl files, summary.jsonl files, compiled context
   - Tier: {tier}
5. QA Lead produces verification.jsonl. Commits: `docs({phase}): verification results`

**QA Code (code-level):**
6. Spawn vbw-qa-code:
   - model: "${QA_CODE_MODEL}"
   - Provide: summary.jsonl (for file list), compiled context
   - Tier: {tier}
7. QA Code runs tests, lint, patterns. Produces qa-code.jsonl. Commits: `docs({phase}): code quality review`

**Result handling:**
- Both PASS → Step 7 (or Step 8 if security disabled)
- QA Lead FAIL → remediation plan → Senior re-specs → Dev fixes → re-verify (max 2 cycles)
- QA Code PARTIAL/FAIL → **remediation loop:**
  1. QA Code writes `gaps.jsonl` with `st: "open"` entries (critical/major findings).
  2. Dev reads gaps.jsonl, fixes each `st: "open"` gap, marks `st: "fixed"` with commit hash.
  3. QA Code re-verifies (re-run Phase 1-3 checks on modified files).
  4. Max 2 remediation cycles. After cycle 2:
     - Still FAIL → Senior architectural review (escalation).
     - 3rd failure → Architect re-evaluates design.
- If `config.approval_gates.qa_fail` is true: pause for user approval before remediation.

### Step 7: Security Audit (optional)

If `--skip-security` or config `security_audit` != true: `○ Security audit skipped`

1. Update execution state: `"step": "security"`
2. Compile context: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/compile-context.sh {phase} security {phases_dir}`
3. Spawn vbw-security:
   - model: "${SECURITY_MODEL}"
   - Provide: summary.jsonl (file list), compiled context
4. Security produces security-audit.jsonl. Commits: `docs({phase}): security audit`
5. If `r: "FAIL"`: **HARD STOP**. Display findings. Only user `--force` overrides.
6. If `r: "WARN"`:
   - Display warnings.
   - If `config.approval_gates.security_warn` is true: pause for user approval.
   - Otherwise: continue.
7. If `r: "PASS"`: continue.

### Step 8: Sign-off (Lead)

1. Update execution state: `"step": "signoff"`
2. Review all artifacts:
   - code-review.jsonl: all approved?
   - verification.jsonl: PASS or PARTIAL (with accepted gaps)?
   - qa-code.jsonl: PASS?
   - security-audit.jsonl: PASS or WARN?
3. Decision:
   - All good → SHIP (mark phase complete)
   - Issues remain → HOLD (generate remediation instructions)
4. **Shutdown teammates:** Send shutdown to each, wait for approval, clean up.
5. **Update state:**
   - .execution-state.json: `"status": "complete"`, `"step": "signoff"`
   - ROADMAP.md: mark phase complete
   - Commit: `chore(state): phase {N} complete`
6. Display per `@${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md`:
   ```
   ╔═══════════════════════════════════════════════╗
   ║  Phase {N}: {name} — Built                    ║
   ╚═══════════════════════════════════════════════╝

     Plan Results:
       ✓ Plan 01: {title}  /  ✗ Plan 03: {title} (failed)

     Metrics:
       Plans: {completed}/{total}  Effort: {profile}
       Code Review: {approve/changes}  QA: {PASS|PARTIAL|FAIL}
       Security: {PASS|WARN|FAIL|skipped}

     Deviations: {count}
   ```
7. Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/suggest-next.sh execute {qa-result}`

## Execution State Transitions

| Step | state.step | Commits |
|------|-----------|---------|
| Architecture | architecture | architecture.toon |
| Load Plans | planning | .execution-state.json |
| Design Review | design_review | enriched plan.jsonl |
| Implementation | implementation | source code + summary.jsonl |
| Code Review | code_review | code-review.jsonl |
| QA | qa | verification.jsonl + qa-code.jsonl |
| Security | security | security-audit.jsonl |
| Sign-off | signoff | state.json + ROADMAP.md |

Each transition commits .execution-state.json so resume works on exit.

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md — Phase Banner, ◆ running, ✓ complete, ✗ failed, ○ skipped, no ANSI color codes.
