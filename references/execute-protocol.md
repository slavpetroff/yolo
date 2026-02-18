# YOLO Execution Protocol

Loaded on demand by /yolo:go Execute mode. Not a user-facing command.

Implements the 11-step company-grade engineering workflow. See `references/company-hierarchy.md` for full hierarchy and `references/artifact-formats.md` for JSONL schemas.

## Spawn Strategy Gate (MANDATORY — read FIRST before any step)

`team_mode` is passed by go.md from resolve-team-mode.sh. This determines ALL agent spawning for the entire protocol. You MUST check this value and follow the correct path at every step.

**If `team_mode=teammate`:** Department teams are created via Teammate API by go.md before this protocol runs. Within each step, agents that belong to the department team (architect, senior, dev, tester, qa, qa-code, security) are spawned as teammates using `Task` tool with `team_name` param, and coordinate via `SendMessage`. You MUST NOT use bare Task tool (without team_name) for these agents. The ONLY agents spawned via bare Task tool are the three Task-only shared agents: critic, scout, debugger — they are explicitly excluded from team membership (see `references/teammate-api-patterns.md` ## Task-Only Agents).

**If `team_mode=task`:** All agents are spawned via Task tool as documented below. No Teammate API usage.

At each step below, "Spawn X with Task tool" is the task-mode instruction. When team_mode=teammate, replace with: "Dispatch X via SendMessage within the department team" (or register as teammate if first time in this step). The teammate-specific instructions at each step are marked with **[teammate]** blocks.

## Owner-First Communication Rule

**No agent communicates directly with the user.** All user interaction flows through go.md (Owner proxy). Escalation chain: Dev → Senior → Lead → Owner/go.md → User.

## Pre-Execution

1. **Parse arguments:** Phase number (auto-detect if omitted), --effort, --skip-qa, --skip-security, --plan=NN.
2. **Run execute guards:**
   - Not initialized: STOP "Run /yolo:init first."
   - No plans in phase dir: STOP "Phase {N} has no plans. Run `/yolo:go --plan {N}` first."
   - All plans have summary.jsonl: cautious/standard → WARN + confirm; confident/pure-yolo → warn + continue.
3. **Resolve models for all agents:**
   ```bash
   for role in critic scout architect lead senior tester dev qa qa-code security; do
     eval "${role^^}_MODEL=\$(bash \${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-model.sh $role .yolo-planning/config.json \${CLAUDE_PLUGIN_ROOT}/config/model-profiles.json)"
   done
   ```
4. **Validate all plans:** Before execution, validate every plan.jsonl in the phase directory:
   ```bash
   for plan in "${PHASE_DIR}"/*.plan.jsonl; do
     result=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/validate-plan.sh --plan "$plan")
     if [ $? -ne 0 ]; then
       echo "Plan validation failed: $plan" >&2
       echo "$result" | jq -r '.errors[]' >&2
       exit 1
     fi
   done
   ```

   ```bash
   # Naming convention validation (post-structural)
   if [ -x "${CLAUDE_PLUGIN_ROOT}/scripts/validate-naming.sh" ]; then
     for plan in "${PHASE_DIR}"/*.plan.jsonl; do
       result=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/validate-naming.sh "$plan" --type=plan)
       if [ $? -ne 0 ]; then
         echo "Naming validation failed: $plan" >&2
         echo "$result" | jq -r '.errors[]' >&2
         exit 1
       fi
     done
   fi
   ```
   This replaces LLM-based plan validation. Invalid plans (structural or naming) STOP execution before any agent spawns.

### Context Scoping Protocol (MANDATORY)

Each agent receives ONLY what it needs (progressive scoping — lower agents see less). When spawning via Task tool, include ONLY listed inputs. No extra context "for reference." When `team_mode=teammate`, the same scoping rules apply -- agents receive identical context regardless of spawn mechanism. The transport changes (SendMessage vs Task tool), but the content isolation does not.

| Step | Agent | Receives (include in Task prompt) | NEVER pass |
|------|-------|----------------------------------|-----------|
| 1 | Critic | reqs.jsonl, PROJECT.md, codebase/, research.jsonl, dept CONTEXT (if multi-dept) | plans, code-review, QA artifacts |
| 2 | Scout | critique.jsonl (critical/major only), reqs.jsonl, codebase/ mapping, .ctx-scout.toon | plans, architecture, implementation code, QA artifacts, department CONTEXT |
| 3 | Architect | reqs.jsonl, codebase/, research.jsonl, critique.jsonl, dept CONTEXT | implementation code, QA artifacts |
| 4 | Lead | architecture.toon, reqs.jsonl, ROADMAP, prior summaries | critique.jsonl directly (addressed in architecture), QA artifacts |
| 5 | Senior (Review) | plan.jsonl, architecture.toon, codebase patterns | full CONTEXT, ROADMAP, other dept artifacts |
| 6 | Tester | enriched plan.jsonl (tasks with `ts`), codebase patterns | architecture.toon, CONTEXT, critique.jsonl |
| 7 | Dev | enriched plan.jsonl (`spec` + `ts` fields), test files | architecture.toon, CONTEXT, critique.jsonl, ROADMAP |
| 8 | Senior (Review) | plan.jsonl, git diff, test-plan.jsonl | CONTEXT, ROADMAP |
| 9 | QA | plan.jsonl, summary.jsonl, .ctx-qa.toon | CONTEXT, architecture.toon |
| 10 | Security | summary.jsonl (file list), .ctx-security.toon | CONTEXT, plans |

**Teammate mode context delivery:** When `team_mode=teammate`, the Receives column content is delivered via SendMessage instead of Task tool parameters. The NEVER pass column restrictions are identical -- SendMessage does not change what context an agent should receive, only how it is delivered. Lead constructs the SendMessage payload with exactly the artifacts listed in Receives for each step.

**Key principle:** Dev's `spec` field IS its complete instruction set. Escalation flows UP (broader context to resolve), resolution flows DOWN as updated artifacts (never raw context files).

## Verification Gate Protocol

### Gate Check

**ENTRY GATE:** Verify {predecessor_artifact} exists in {phase-dir}.
- File check: `[ -f "{phase-dir}/{artifact}" ]`
- JSONL validity (if .jsonl): `jq empty "{phase-dir}/{artifact}" 2>/dev/null`
- TOON validity (if .toon): `[ -s "{phase-dir}/{artifact}" ]`
- If artifact was produced by a skippable step, also accept: step status is "skipped" in .execution-state.json (check via `jq -r '.steps["{step_name}"].status' .yolo-planning/.execution-state.json`)
- If NEITHER artifact exists NOR step is skipped: **STOP** "{Step N} artifact missing — {artifact} not found in {phase-dir}. Run step {N} first."

> **Script delegation:** Entry gate checks can be delegated to `validate-gates.sh` for deterministic verification:
> ```bash
> result=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/validate-gates.sh --step "{step_name}" --phase-dir "{phase-dir}")
> if [ $? -ne 0 ]; then
>   echo "$result" | jq -r '.missing[]' >&2
>   STOP "{Step N} artifact missing"
> fi
> ```
> This replaces inline file existence checks with a centralized lookup table (see scripts/validate-gates.sh).

### State Commit

**EXIT GATE:** After step completes successfully:
1. Update `.yolo-planning/.execution-state.json`:
   - Set `steps.{step_name}.status` to `"complete"`
   - Set `steps.{step_name}.completed_at` to ISO 8601 timestamp
   - Set `steps.{step_name}.artifact` to the path of the produced artifact
   - Set top-level `step` to `"{step_name}"`
2. Verify this step's output artifact exists: `[ -f "{phase-dir}/{output_artifact}" ]`
3. Commit: `chore(state): {step_name} complete phase {N}`

### Skip Output

When a step's Guard condition triggers a skip:
1. Display: `○ {Step Name} skipped ({reason})`
2. Update `.yolo-planning/.execution-state.json`:
   - Set `steps.{step_name}.status` to `"skipped"`
   - Set `steps.{step_name}.reason` to `"{reason}"`
   - Set `steps.{step_name}.skipped_at` to ISO 8601 timestamp
3. Commit: `chore(state): {step_name} skipped phase {N}`
4. Proceed to next step.

Every step in the 11-step workflow below MUST follow these templates. Entry gates run before any step logic. Exit gates run after step logic completes. Skip output runs instead of step logic when guard conditions are met.

### Mandatory vs Skippable Steps

**Skippable:** critique (turbo or exists or critique.enabled=false), research (turbo), architecture (exists), test_authoring (turbo or no `ts`), documentation (documenter='never' or turbo), qa (--skip-qa or turbo), security (--skip-security or config off).

**Mandatory (failure = STOP, no --force):** planning, design_review, implementation, code_review, signoff.

### Complexity-Aware Step Skipping

When complexity routing is enabled (`config_complexity_routing=true` in phase-detect output) and the Analyze agent classifies the task, steps are skipped based on the suggested path:

| Path | Steps That Run | Steps Skipped |
|------|---------------|---------------|
| Trivial (trivial_shortcut) | design_review (5), implementation (7), post-task QA gate | critique (1), research (2), architecture (3), planning (4), test_authoring (6), code_review (8), qa (9), security (10) |
| Medium (medium_path) | planning (4), design_review (5), implementation (7), code_review (8), signoff (11) | critique (1), research (2), architecture (3), test_authoring (6), qa (9), security (10) |
| High (full_ceremony) | All 11 steps per existing logic | Per existing skip conditions (turbo, --skip-qa, etc.) |

**Rules:**

1. **Trivial path:** Only Senior (design review), Dev (implementation), and the post-task QA gate run. Senior receives the inline plan directly from route-trivial.sh. No formal planning, no code review cycle, no QA agents, no security audit.

2. **Medium path:** Lead performs abbreviated planning (single plan, max `complexity_routing.max_medium_tasks` tasks). Senior enriches, Dev implements, Senior reviews code. Post-plan QA gate runs but full QA agents (qa, qa-code) are skipped. Security audit is skipped.

3. **High path:** All steps run per existing logic. Complexity routing has no effect when high path is selected — the full ceremony applies with standard skip conditions.

4. **Step 11 (signoff) always runs** regardless of path. For trivial path, go.md handles sign-off inline. For medium and high paths, Lead performs sign-off per existing protocol.

5. **Complexity path does NOT override explicit flags.** The `--skip-qa` and `--skip-security` flags are orthogonal to complexity routing. If complexity routing says "run QA" but `--skip-qa` is set, QA is skipped. If complexity routing says "skip QA" (trivial/medium), the flags are redundant but harmless.

6. **Backward compatibility:** When `config_complexity_routing=false`, this section has no effect. All steps follow existing skip conditions only.

### Step 0: Product Ownership (PO Agent — optional, config-gated)

**Guard:** Skip if `po.enabled=false` in config OR `--effort=turbo` OR `scope-document.json` already exists in phase dir. When skipped, the existing 11-step workflow runs unchanged (backward compatible). Skip Output per template. Commit: `chore(state): po skipped phase {N}`.

**ENTRY GATE:** Verify Analyze output exists (analysis.json from Path 0) OR active milestone detected (phase-detect.sh). If neither: STOP "Step 0 requires Analyze output or active milestone."

When `po.enabled=true` and guard conditions not met:

1. **Spawn PO Agent:**
   ```
   PO_MODEL=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-model.sh po .yolo-planning/config.json ${CLAUDE_PLUGIN_ROOT}/config/model-profiles.json)
   ```
   Spawn yolo-po with model: "${PO_MODEL}". Pass: user intent, analysis.json, codebase mapping, REQUIREMENTS.md, ROADMAP.md, prior summaries.
   Display: `◆ Spawning PO (${PO_MODEL}) for scope clarification...`

2. **PO-Questionary loop:** PO spawns Questionary Agent for scope clarification (max 3 rounds, early exit at scope_confidence >= 0.85). Orchestrated via po-scope-loop.sh.
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/po-scope-loop.sh \
     --config .yolo-planning/config.json \
     --phase-dir "{phase-dir}" \
     --max-rounds 3 \
     --confidence-threshold 0.85
   ```

3. **Roadmap Agent (full_ceremony only):** PO spawns Roadmap Agent for dependency analysis. Roadmap produces phase ordering, dependency graph, critical path, milestones. Skip if medium_path or effort=fast.
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/validate-deps.sh \
     --graph "{phase-dir}/roadmap-plan.json" \
     --format adjacency
   ```
   Validate no cycles in dependency graph.

4. **user_presentation rendering:** PO may emit `user_presentation` objects during scope gathering and sign-off. For each:
   ```bash
   rendered=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/render-user-presentation.sh --json "$presentation_json")
   ```
   Orchestrator renders via AskUserQuestion. User response fed back to PO.

5. **PO produces scope-document.json** in phase directory. Contains: vision, enriched scope, requirements, roadmap (if produced), assumptions, deferred items.

6. **EXIT GATE:** Artifact: `scope-document.json` (valid JSON, contains `status: "PO-APPROVED"`). State: `steps.po.status = complete`. Commit: `chore(state): po complete phase {N}`.

**When PO is enabled, the workflow becomes 12-step (Step 0 + Steps 1-11).** Step 1 (Critique) entry gate is unchanged — it does not require scope-document.json. The scope-document.json is passed as additional context to Critic, Architect, and Lead alongside existing inputs.

### Step 1: Critique / Brainstorm (Critic Agent — Confidence-Gated Multi-Round)

**Guard:** Skip if `--effort=turbo` OR `critique.jsonl` exists OR `critique.enabled=false` in config. Skip Output per template. Commit: `chore(state): critique skipped phase {N}`.

**ENTRY GATE:** None (first step after optional Step 0). Verify phase directory exists: `[ -d "{phase-dir}" ]`. If not: STOP "Phase directory missing. Run /yolo:go --plan first."

1. Compile context: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/compile-context.sh {phase} critic {phases_dir}`
2. **Confidence-gated critique loop:** Instead of a single Critic spawn, run the critique-loop.sh orchestrator which manages multi-round critique with early exit on high confidence:
   ```bash
   CRITIQUE_RESULT=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/critique-loop.sh \
     --phase-dir "{phase-dir}" \
     --config .yolo-planning/config.json \
     --role {dept-critic-role})
   ```
   Where `{dept-critic-role}` is `critic` (backend), `fe-critic` (frontend), or `ux-critic` (uiux).

   The loop spawns yolo-critic with Task tool per round:
   - model: "${CRITIC_MODEL}"
   - Provide: reqs.jsonl (or REQUIREMENTS.md), PROJECT.md, codebase/ mapping, research.jsonl (if exists)
   - Include compiled context: `{phase-dir}/.ctx-critic.toon`
   - Include round number for multi-round protocol (see agents/yolo-critic.md § Multi-Round Protocol)
   - Effort: if `--effort=fast`, instruct Critic to limit to `critical` findings only

   > **Tool permissions:** When spawning agents, resolve project-type-specific tool permissions:
   > ```bash
   > TOOL_PERMS=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-tool-permissions.sh --role "critic" --project-dir ".")
   > ```
   > Include resolved `disallowed_tools` from the output in the agent's compiled context (.ctx-critic.toon). See D4 in architecture for soft enforcement details.

   Loop behavior:
   - **Round 1**: Standard critique. Critic produces findings with `cf` (confidence) and `rd:1` fields.
   - **Round 2** (if `cf < critique.confidence_threshold`, default 85): Targeted re-analysis of low-confidence areas only. Findings get `rd:2`.
   - **Round 3** (if `cf` still < threshold): Final sweep with forced assumptions. Findings get `rd:3`. Hard cap — no Round 4 regardless.
   - **Early exit**: If `cf >= threshold` at any round, loop exits immediately.

   critique-loop.sh outputs JSON summary: `{rounds_used, final_confidence, early_exit, findings_total, findings_per_round}`.

3. Display: `◆ Spawning Critic (${CRITIC_MODEL})...` → per-round confidence → `✓ Critique complete (cf:{final_confidence}, rounds:{rounds_used})`
4. Critic returns findings via SendMessage (Critic has no Write tool).
5. Write critique.jsonl from Critic's findings to phase directory. Each entry includes `cf` and `rd` fields.
6. Commit: `docs({phase}): critique and gap analysis`
7. **User gate (balanced/thorough effort):** Display critique summary including confidence score and rounds used. If critical findings exist, AskUserQuestion "Address these before architecture?" Options: "Proceed (Architect will address)" / "Pause to discuss".
8. **EXIT GATE:** Artifact: `critique.jsonl` (valid JSONL, entries have `cf` and `rd` fields). State: `steps.critique = complete`. Commit: `chore(state): critique complete phase {N}`.

### Step 2: Research (Scout Agent)

**Guard:** Skip if `--effort=turbo`. Note: research.jsonl existence does NOT trigger skip (append mode). Skip Output per template. Commit: `chore(state): research skipped phase {N}`.

**ENTRY GATE:** Verify `{phase-dir}/critique.jsonl` exists OR `steps.critique.status` is `"skipped"` in `.execution-state.json`. If neither: STOP "Step 1 artifact missing — critique.jsonl not found. Run step 1 first."

1. Compile context: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/compile-context.sh {phase} scout {phases_dir}`
2. Spawn yolo-scout with Task tool:
   - model: "${SCOUT_MODEL}"
   - Provide: critique.jsonl findings (critical/major only), reqs.jsonl, codebase/ mapping, compiled context `{phase-dir}/.ctx-scout.toon`, research directives for each critical/major critique finding
   - Include resolved `disallowed_tools` from resolve-tool-permissions.sh --role scout pattern

   > **Tool permissions:** When spawning agents, resolve project-type-specific tool permissions:
   > ```bash
   > TOOL_PERMS=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-tool-permissions.sh --role "scout" --project-dir ".")
   > ```
   > Include resolved `disallowed_tools` from the output in the agent's compiled context (.ctx-scout.toon). See D4 in architecture for soft enforcement details.

3. Display: `◆ Spawning Scout (${SCOUT_MODEL})...` → `✓ Research complete`
4. Scout returns findings via Task result (or scout_findings schema in teammate mode).
5. Write research.jsonl from Scout findings to phase dir. If research.jsonl already exists (pre-Critic entries), APPEND new entries. Each entry includes `mode: post-critic`. Per D2: orchestrator writes, Scout is read-only.
6. Commit: `docs({phase}): research findings`
7. **EXIT GATE:** Artifact: `research.jsonl` (valid JSONL). State: `steps.research = complete`. Commit: `chore(state): research complete phase {N}`.

### Step 3: Architecture (Architect Agent)

**Guard:** Skip if `architecture.toon` exists. Skip Output per template. Commit: `chore(state): architecture skipped phase {N}`.

**ENTRY GATE:** Verify `{phase-dir}/research.jsonl` exists OR `steps.research.status` is `"skipped"` in `.execution-state.json`. If neither: STOP "Step 2 artifact missing — research.jsonl not found. Run step 2 first."

1. Compile context: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/compile-context.sh {phase} architect {phases_dir}`
2. Spawn yolo-architect with Task tool:
   - model: "${ARCHITECT_MODEL}"
   - Provide: reqs.jsonl (or REQUIREMENTS.md), codebase/ mapping, research.jsonl (if exists), critique.jsonl (if exists)
   - Include compiled context: `{phase-dir}/.ctx-architect.toon`

   > **Tool permissions:** When spawning agents, resolve project-type-specific tool permissions:
   > ```bash
   > TOOL_PERMS=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-tool-permissions.sh --role "architect" --project-dir ".")
   > ```
   > Include resolved `disallowed_tools` from the output in the agent's compiled context (.ctx-architect.toon). See D4 in architecture for soft enforcement details.

3. Display: `◆ Spawning Architect (${ARCHITECT_MODEL})...` → `✓ Architecture complete`
4. Verify: architecture.toon exists in phase directory.
5. Architect addresses critique.jsonl findings (updates `st` field) and commits: `docs({phase}): architecture design`
6. **EXIT GATE:** Artifact: `architecture.toon` (non-empty, meets completeness criteria per references/rnd-handoff-protocol.md ## Architect->Lead Stage-Gate). Completeness: tech_decisions present, components defined, integration_points specified, risks documented, critique_disposition complete. State: `steps.architecture = complete`. Commit: `chore(state): architecture complete phase {N}`.

### Step 4: Load Plans and Detect Resume State

**ENTRY GATE:** Verify `{phase-dir}/architecture.toon` exists OR `steps.architecture.status` is `"skipped"` in `.execution-state.json`. If neither: STOP "Step 3 artifact missing — architecture.toon not found. Run step 3 first."

**Stage-gate validation (per references/rnd-handoff-protocol.md):** Lead validates architecture.toon completeness:
1. tech_decisions section exists with at least one decision
2. components section exists with at least one component
3. risks section exists
4. If critique.jsonl exists: all findings have `st` != `"open"` (all addressed/deferred/rejected)

Gate decision:
- **Go**: All criteria met. Proceed to planning.
- **Recycle**: Criteria incomplete. Escalate to Architect with specific gaps via `escalation` schema. STOP until Architect resubmits.
- **Kill**: Phase should be deferred. Escalate to Architect -> User.

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
     "plans": [{"id": "NN-MM", "title": "...", "wave": W, "status": "pending|complete"}],
     "steps": {
       "po": {"status": "pending", "started_at": "", "completed_at": "", "artifact": "", "reason": ""},
       "critique": {"status": "pending", "started_at": "", "completed_at": "", "artifact": "", "reason": ""},
       "research": {"status": "pending", "started_at": "", "completed_at": "", "artifact": "", "reason": ""},
       "architecture": {"status": "pending", "started_at": "", "completed_at": "", "artifact": "", "reason": ""},
       "planning": {"status": "pending", "started_at": "", "completed_at": "", "artifact": "", "reason": ""},
       "design_review": {"status": "pending", "started_at": "", "completed_at": "", "artifact": "", "reason": ""},
       "test_authoring": {"status": "pending", "started_at": "", "completed_at": "", "artifact": "", "reason": ""},
       "implementation": {"status": "pending", "started_at": "", "completed_at": "", "artifact": "", "reason": ""},
       "code_review": {"status": "pending", "started_at": "", "completed_at": "", "artifact": "", "reason": ""},
       "qa": {"status": "pending", "started_at": "", "completed_at": "", "artifact": "", "reason": ""},
       "security": {"status": "pending", "started_at": "", "completed_at": "", "artifact": "", "reason": ""},
       "signoff": {"status": "pending", "started_at": "", "completed_at": "", "artifact": "", "reason": ""}
     }
   }
   ```

   > **Script alternative:** Use `generate-execution-state.sh` to build this JSON deterministically:
   > ```bash
   > bash ${CLAUDE_PLUGIN_ROOT}/scripts/generate-execution-state.sh --phase-dir "{phase-dir}" --phase {N}
   > ```
   > This replaces inline JSON construction. The script scans *.plan.jsonl files, extracts metadata, and writes the full schema above.

   Commit: `chore(state): execution state phase {N}`
8. **Cross-phase deps:** For each plan with `xd` (cross_phase_deps):
   - Verify referenced plan's summary.jsonl exists with `s: complete`
   - If artifact path specified, verify file exists
   - Unsatisfied → STOP with fix instructions
   - All satisfied: `✓ Cross-phase dependencies verified`
9. **EXIT GATE:** Artifact: `.execution-state.json` (status running, plans listed) + `*.plan.jsonl`. State: `steps.planning = complete`. Commit: `chore(state): planning complete phase {N}`.

### Step 5: Design Review (Senior Agent)

**Delegation directive:** You are the Lead. NEVER implement tasks yourself.

**ENTRY GATE:** Verify at least one `*.plan.jsonl` file exists in phase dir (`ls {phase-dir}/*.plan.jsonl`). If none: STOP "Step 4 artifact missing — no plan.jsonl files found. Run step 4 first."

1. Update execution state: `"step": "design_review"`
2. Compile context: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/compile-context.sh {phase} senior {phases_dir}`
3. **Dispatch Senior(s):**

   **When team_mode=teammate:**

   Group remaining plans by wave. For the current wave:
   - If wave has 2+ plans: register one Senior per plan in the wave as teammates (if not already registered). Dispatch all Seniors concurrently via SendMessage, each receiving one plan.jsonl path + architecture.toon + critique.jsonl (if exists) + compiled context. Collect senior_spec messages from all dispatched Seniors.
   - If wave has exactly 1 plan: dispatch a single Senior directly (no parallel coordination overhead -- single-plan waves use sequential dispatch even in teammate mode).
   - See agents/yolo-senior.md ## Parallel Review for Senior-side protocol.

   > **Tool permissions:** When spawning agents, resolve project-type-specific tool permissions:
   > ```bash
   > TOOL_PERMS=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-tool-permissions.sh --role "senior" --project-dir ".")
   > ```
   > Include resolved `disallowed_tools` from the output in the agent's compiled context (.ctx-senior.toon). See D4 in architecture for soft enforcement details.

   **When team_mode=task (default):**

   For each plan.jsonl without enriched specs (tasks missing `spec` field):
   - Spawn yolo-senior with Task tool:
     - model: "${SENIOR_MODEL}"
     - Mode: "design_review"
     - Provide: plan.jsonl path, architecture.toon path, critique.jsonl path (if exists), compiled context
   - Display: `◆ Spawning Senior for design review ({plan})...`

   > **Tool permissions:** When spawning agents, resolve project-type-specific tool permissions:
   > ```bash
   > TOOL_PERMS=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-tool-permissions.sh --role "senior" --project-dir ".")
   > ```
   > Include resolved `disallowed_tools` from the output in the agent's compiled context (.ctx-senior.toon). See D4 in architecture for soft enforcement details.

4. Senior reads plan, researches codebase, enriches each task with `spec` field AND `ts` (test_spec) field.
5. Senior commits enriched plan: `docs({phase}): enrich plan {NN-MM} specs`
6. Verify: all tasks in plan.jsonl have non-empty `spec` field. Tasks with testable logic should have `ts` field.
7. **EXIT GATE:** Artifact: enriched plan.jsonl (all tasks in ALL plans have non-empty `spec`). When team_mode=teammate: Lead waits for senior_spec messages from all dispatched Seniors in the current wave. After all received, Lead verifies each plan.jsonl: `jq -r .spec` on every task line must return non-empty value. If any plan has tasks without specs, Senior failed -- Lead escalates. When team_mode=task: sequential verification unchanged (each plan checked after its Senior completes). State: `steps.design_review = complete`. Commit: `chore(state): design_review complete phase {N}`.

### Step 6: Test Authoring — RED Phase (Tester Agent)

**Guard:** Skip if `--effort=turbo` OR no tasks have `ts` fields. Skip Output per template. Commit: `chore(state): test_authoring skipped phase {N}`.

**ENTRY GATE:** Verify enriched plan.jsonl exists with `spec` fields populated (check at least one task has non-empty `spec` via `jq -r .spec`). If not: STOP "Step 5 artifact missing — plan.jsonl tasks have no spec fields. Run step 5 first."

1. Update execution state: `"step": "test_authoring"`
2. Compile context: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/compile-context.sh {phase} tester {phases_dir} {plan_path}`
2.5. **Teammate registration (team_mode=teammate only):** Lead registers tester as a teammate in the department team before sending test authoring context. The tester receives the enriched plan.jsonl via SendMessage from Lead (replacing Task tool parameter passing). Tester sends `test_plan_result` back to Senior (NOT Lead) via SendMessage when complete. In task mode, this step is skipped (tester spawned via Task tool as documented below).
3. For each plan.jsonl with tasks that have `ts` fields:
   - Spawn yolo-tester with Task tool:
     - model: "${TESTER_MODEL}"
     - Provide: enriched plan.jsonl path, compiled context
   - Display: `◆ Spawning Tester (${TESTER_MODEL}) for RED phase ({plan})...`

   > **Tool permissions:** When spawning agents, resolve project-type-specific tool permissions:
   > ```bash
   > TOOL_PERMS=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-tool-permissions.sh --role "tester" --project-dir ".")
   > ```
   > Include resolved `disallowed_tools` from the output in the agent's compiled context (.ctx-tester.toon). See D4 in architecture for soft enforcement details.

4. Tester writes failing test files per `ts` specifications.
5. Tester verifies ALL tests FAIL (RED confirmation).
6. Tester produces test-plan.jsonl and commits: `test({phase}): RED phase tests for plan {NN-MM}`
7. Verify: test-plan.jsonl exists with `red: true` for all entries.
8. Display: `✓ RED phase complete — {N} test files, {M} test cases (all failing)`
9. **EXIT GATE:** Artifact: `test-plan.jsonl` (valid JSONL, all `red: true`). State: `steps.test_authoring = complete`. Commit: `chore(state): test_authoring complete phase {N}`.

### Step 7: Implementation (Dev Agents)

**ENTRY GATE:** Verify enriched plan.jsonl exists with `spec` fields populated. If test-plan.jsonl should exist (step 6 was not skipped): verify `{phase-dir}/test-plan.jsonl` exists with `red: true` entries. Check via: `jq -r '.steps.test_authoring.status' .yolo-planning/.execution-state.json` — if `"complete"`, verify test-plan.jsonl exists; if `"skipped"`, proceed without it. If step 6 is `"complete"` but test-plan.jsonl missing: STOP "Step 6 artifact missing — test-plan.jsonl not found. Run step 6 first."

1. Update execution state: `"step": "implementation"`
2. Compile context: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/compile-context.sh {phase} dev {phases_dir} {plan_path}`
3. **Task Creation and Dev Dispatch:**

   **When team_mode=teammate:**

   a. **TaskCreate mapping:** Lead reads each plan.jsonl, creates shared task list items via TaskCreate for each task. Map plan-level `d` (depends_on) field: if plan B depends on plan A, all tasks in B have `blocked_by=[all tasks in A]`. Map task-level `td` (task_depends) field: if task T3 has `td:["T1"]`, add `blocked_by="{plan_id}/T1"` for intra-plan ordering. See `references/teammate-api-patterns.md` ## Task-Level Blocking.

   b. **File-overlap enforcement:** Tasks whose `f` field overlaps with currently-executing tasks are NOT claimable. Lead maintains `claimed_files` set per `agents/yolo-lead.md` ## Summary Aggregation ### File-Overlap Detection.

   c. **Dynamic Dev scaling:** Lead computes `dev_count = min(available_unblocked_tasks, 5)` via `scripts/compute-dev-count.sh --available N`. Lead registers `dev_count` Dev agents as teammates. See `references/teammate-api-patterns.md` ## Dynamic Dev Scaling.

   d. **Serialized commits:** All Devs use `scripts/git-commit-serialized.sh` for commits (flock-based locking prevents index.lock conflicts). See `agents/yolo-dev.md` ## Task Self-Claiming ### Serialized Commits.

   e. **Dev claim loop:** Spawned Devs call TaskList to find available tasks, claim via TaskUpdate, execute per spec, commit, report `task_complete` to Lead and `dev_progress` to Senior. Loop continues until no tasks remain. See `agents/yolo-dev.md` ## Task Self-Claiming ### Claim Loop.

   **Dev Self-Claiming Flow (teammate mode):** Each Dev operates autonomously after registration: (1) Dev calls TaskList -- Lead filters results to exclude tasks with file overlap (see ## Task Coordination in `teammate-api-patterns.md`). (2) Dev selects first available task and claims via TaskUpdate. (3) Dev sends `task_claim` to Lead (Lead adds files to `claimed_files`). (4) Dev executes task per `spec` field. (5) Dev commits via `scripts/git-commit-serialized.sh -m "{type}({phase}-{plan}): {task-name}"`. (6) Dev sends `dev_progress` to Senior (visibility) and `task_complete` to Lead (accounting). (7) Dev loops to step 1. When TaskList returns empty, Dev signals idle to Lead.

   Full self-claiming protocol: `agents/yolo-dev.md` ## Task Self-Claiming. File-overlap detection: `agents/yolo-lead.md` ## Summary Aggregation ### File-Overlap Detection.

   **Lead Summary Aggregation (teammate mode):** Lead collects `task_complete` messages from all Devs. Per plan: (1) Lead tracks completion count (`tasks_completed` vs `tasks_total` from plan header). (2) When all tasks in a plan report complete, Lead constructs `summary_aggregation` (see `references/handoff-schemas.md` ## summary_aggregation). (3) Lead writes `{plan_id}.summary.jsonl` to phase directory with aggregated `commit_hashes`, `files_modified`, `deviations`. (4) Lead commits summary.jsonl using `scripts/git-commit-serialized.sh -m "docs({phase}): summary {NN-MM}"`. (5) Lead verifies summary.jsonl is valid JSONL (`jq empty`). This replaces per-Dev summary writes -- in teammate mode, Dev does NOT write summary.jsonl (see `agents/yolo-dev.md` ## Task Self-Claiming ### Stage 3 Override).

   Full aggregation protocol: `agents/yolo-lead.md` ## Summary Aggregation.

   **summary.jsonl Ownership (IMPORTANT):** Clean ownership split to prevent write conflicts: When team_mode=teammate: Lead is the SOLE writer of summary.jsonl. Lead aggregates all `task_complete` messages per plan and writes the summary. Dev SKIPS Stage 3 summary.jsonl write entirely (see `agents/yolo-dev.md` ## Task Self-Claiming ### Stage 3 Override). When team_mode=task: Dev is the SOLE writer of summary.jsonl (unchanged from current behavior, see `agents/yolo-dev.md` ### Stage 3: Produce Summary). In BOTH modes, exactly one agent writes summary.jsonl per plan. Zero conflict by design.

   See `agents/yolo-dev.md` ## Task Self-Claiming ### Stage 3 Override for Dev-side conditional. See `agents/yolo-lead.md` ## Summary Aggregation ### Aggregation Protocol for Lead-side write logic.

   > **Tool permissions:** When spawning agents, resolve project-type-specific tool permissions:
   > ```bash
   > TOOL_PERMS=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-tool-permissions.sh --role "dev" --project-dir ".")
   > ```
   > Include resolved `disallowed_tools` from the output in the agent's compiled context (.ctx-dev.toon). See D4 in architecture for soft enforcement details.

   **When team_mode=task (default):**

   For each uncompleted plan, TaskCreate:
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
   Wire dependencies via TaskUpdate: `addBlockedBy` from plan `d` (depends_on) field.
   Spawn Dev teammates and assign tasks.
   Display: `◆ Spawning Dev (${DEV_MODEL})...`

   > **Tool permissions:** When spawning agents, resolve project-type-specific tool permissions:
   > ```bash
   > TOOL_PERMS=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-tool-permissions.sh --role "dev" --project-dir ".")
   > ```
   > Include resolved `disallowed_tools` from the output in the agent's compiled context (.ctx-dev.toon). See D4 in architecture for soft enforcement details.

**Dev TDD protocol:**
- Before each task with `ts`: run tests, verify FAIL (RED). If tests pass → escalate to Senior.
- After implementing: run tests, verify PASS (GREEN). If fail after 3 attempts → escalate to Senior.

**Post-task QA Gate (after each task commit):**

After each Dev task commit (and TDD GREEN verification if applicable), run the post-task QA gate as a fast automated check before proceeding to the next task:

```bash
result=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/qa-gate-post-task.sh \
  --phase-dir "{phase-dir}" --plan "{plan-id}" --task "{task-id}" --scope)
gate_status=$(echo "$result" | jq -r '.gate')
```

Note: `--scope` flag is DEFAULT per architecture D4 (scoped to task-modified files only for speed).

- On `gate_status=pass`: Dev proceeds to next task.
- On `gate_status=fail`: Dev pauses. Senior reviews test failures from gate JSON output (`tst.fl` field). Senior re-specs fix. Dev implements fix and re-commits. Re-run post-task gate. Max 2 remediation cycles per task -- after cycle 2 still failing, Senior escalates to Lead.
- On `gate_status=warn`: Dev proceeds (warn indicates missing test infrastructure, not test failure). Gate result is recorded for QA agent review.

**[teammate]** When `team_mode=teammate`: Dev runs post-task gate autonomously after each self-claimed task commit (part of the Dev claim loop step 5-6). Dev sends gate result to Senior via `dev_progress` message (include `gate_status` field). If gate fails, Dev sends `dev_blocker` to Senior with gate output. Senior routes fix instructions back to Dev via `code_review_changes` schema.

**[task]** When `team_mode=task`: Orchestrator (Lead) runs post-task gate after each Dev task commit. On failure, orchestrator messages Dev with fix instructions from Senior.

**Dev escalation chain:** Dev → Senior (not Lead). If Dev sends `dev_blocker`, route to Senior.

**Escalation State Tracking (mid-step, per D8):**

When a Dev sends `dev_blocker` (received by Senior, potentially escalated to Lead), the orchestrator tracks the escalation immediately in `.execution-state.json`:

```json
{
  "escalations": [
    {
      "id": "ESC-05-01-T3",
      "task": "05-01/T3",
      "plan": "05-01",
      "severity": "blocking",
      "status": "pending",
      "level": "senior",
      "escalated_at": "2026-02-18T10:00:00Z",
      "last_escalated_at": "2026-02-18T10:00:00Z",
      "resolved_at": "",
      "round_trips": 0,
      "resolution": ""
    }
  ]
}
```

Commit immediately on receipt: `chore(state): escalation received phase {N}` (extends Commit-Every-Artifact pattern #4 to escalation state).

**Periodic timeout check:** During Step 7, the orchestrator periodically calls:
```bash
result=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/check-escalation-timeout.sh \
  --phase-dir "{phase-dir}" --config config/defaults.json)
timed_out=$(echo "$result" | jq -r '.timed_out | length')
```
If `timed_out > 0`: auto-escalate each timed-out entry to the next level per ## Escalation Handling. Update the entry's `level` and `last_escalated_at` fields. Send `escalation_timeout_warning` schema.

**Resolution handling:** When `escalation_resolution` is received (forwarded down the chain):
1. Update escalation entry: `status: "resolved"`, `resolved_at: "{ISO8601}"`, `resolution: "{decision text}"`
2. Commit: `chore(state): escalation resolved phase {N}`

**Summary verification gate (mandatory):**
When team_mode=teammate: Lead-written summary.jsonl is verified (Lead is sole writer). Lead checks `jq empty {phase-dir}/{plan_id}.summary.jsonl` after writing.
When team_mode=task: Dev-written summary.jsonl is verified (unchanged behavior):
1. Verify `{phase_dir}/{plan_id}.summary.jsonl` exists with valid JSONL.
2. If missing: message Dev to write it. If unavailable: write from git log.
3. Only after verification: mark plan `"complete"` in .execution-state.json.

**Post-plan QA Gate (after plan completion):**

After all tasks in a plan complete and summary.jsonl is written and verified, run the post-plan QA gate before proceeding to the next plan:

```bash
result=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/qa-gate-post-plan.sh \
  --phase-dir "{phase-dir}" --plan "{plan-id}")
gate_status=$(echo "$result" | jq -r '.gate')
```

Note: NO `--scope` flag -- post-plan runs full test suite per architecture D4.

- On `gate_status=pass`: Proceed to next plan (or Step 8 if last plan).
- On `gate_status=fail`: Block progression to next plan. Read gate JSON: check `tst` (test failures), `mh` (must_have failures). For test failures: Senior reviews, re-specs fix tasks, Dev implements. For must_have failures: Senior reviews plan coverage gaps. Max 1 remediation cycle at post-plan level -- persistent failure escalates to Lead.

**[teammate]** When `team_mode=teammate`: Lead runs post-plan gate after writing summary.jsonl (Lead is sole summary writer in teammate mode). Lead sends gate result to Senior for review if fail.

**[task]** When `team_mode=task`: Orchestrator runs post-plan gate after Dev writes summary.jsonl. On failure, orchestrator routes to Senior.

**EXIT GATE:** Artifact: `{plan_id}.summary.jsonl` per plan (valid JSONL). When team_mode=teammate: Lead verifies all summary.jsonl files were written by Lead aggregation (all `task_complete` messages collected, all plans accounted for). Lead checks summary.jsonl validity: `jq empty {phase-dir}/{plan_id}.summary.jsonl` for each plan. When team_mode=task: Dev-written summary.jsonl verified per existing protocol. Also verify: no escalations in .execution-state.json have `status: "pending"`. All must be `"resolved"` or escalated beyond the current step. Check via: `jq '[.escalations[] | select(.status == "pending")] | length' .yolo-planning/.execution-state.json` must equal 0. If pending escalations remain: STOP "Step 7 cannot complete -- {N} pending escalation(s). Resolve or escalate before proceeding." State: `steps.implementation = complete`. Commit: `chore(state): implementation complete phase {N}`.

### Step 8: Code Review (Senior Agent)

**ENTRY GATE:** For each plan, verify `{phase-dir}/{plan_id}.summary.jsonl` exists with valid JSONL (`jq empty`). If not: STOP "Step 7 artifact missing — summary.jsonl not found for plan {plan_id}. Run step 7 first."

1. Update execution state: `"step": "code_review"`
2. **Dispatch Senior(s):**

   **When team_mode=teammate:**

   Group completed plans by wave. For the current wave:
   - If wave has 2+ completed plans: register one Senior per plan as teammates. Dispatch all Seniors concurrently via SendMessage, each receiving one plan.jsonl path + git diff of plan commits + test-plan.jsonl (if exists). Collect code_review_result messages from all dispatched Seniors.
   - If wave has exactly 1 completed plan: dispatch a single Senior directly (no parallel coordination overhead).
   - See agents/yolo-senior.md ## Parallel Review for Senior-side protocol.

   > **Tool permissions:** When spawning agents, resolve project-type-specific tool permissions:
   > ```bash
   > TOOL_PERMS=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-tool-permissions.sh --role "senior" --project-dir ".")
   > ```
   > Include resolved `disallowed_tools` from the output in the agent's compiled context (.ctx-senior.toon). See D4 in architecture for soft enforcement details.

   **When team_mode=task (default):**

   For each completed plan:
   - Spawn yolo-senior with Task tool:
     - model: "${SENIOR_MODEL}"
     - Mode: "code_review"
     - Provide: plan.jsonl path, git diff of plan commits, test-plan.jsonl (if exists)
   - Display: `◆ Spawning Senior for code review ({plan})...`

   > **Tool permissions:** When spawning agents, resolve project-type-specific tool permissions:
   > ```bash
   > TOOL_PERMS=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-tool-permissions.sh --role "senior" --project-dir ".")
   > ```
   > Include resolved `disallowed_tools` from the output in the agent's compiled context (.ctx-senior.toon). See D4 in architecture for soft enforcement details.

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
   - Otherwise → proceed to Step 9.
7. Senior commits: `docs({phase}): code review {NN-MM}`
8. Verify: code-review.jsonl exists with `r: "approve"`.
9. **EXIT GATE:** Artifact: `code-review.jsonl` per plan (r: "approve"). When team_mode=teammate: Lead waits for code_review_result messages from all dispatched Seniors in the current wave. After all received, Lead verifies each plan has code-review.jsonl with `r: "approve"` in line 1 (via `jq -r .r` equals "approve"). If any plan has changes_requested after cycle 2, Senior escalates to Lead per existing protocol. When team_mode=task: sequential verification unchanged (each plan checked after its Senior completes). State: `steps.code_review = complete`. Commit: `chore(state): code_review complete phase {N}`.

### Step 9: QA (QA Lead + QA Code)

**Guard:** Skip if `--skip-qa` OR `--effort=turbo`. Skip Output per template. Commit: `chore(state): qa skipped phase {N}`.

**ENTRY GATE:** Verify `{phase-dir}/code-review.jsonl` exists with `r: "approve"` in line 1 (`jq -r .r` equals `"approve"`). If not: STOP "Step 8 artifact missing — code-review.jsonl not found or not approved. Run step 8 first."

**Post-phase QA Gate (automated pre-check):**

Before spawning QA agents (LLM-powered, expensive), run the post-phase gate as a fast automated pre-check (script-only, <60s). This catches obvious failures before committing LLM cost.

```bash
result=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/qa-gate-post-phase.sh \
  --phase-dir "{phase-dir}")
gate_status=$(echo "$result" | jq -r '.gate')
```

- On `gate_status=pass`: Proceed to QA agent spawn below.
- On `gate_status=fail`: BLOCK QA agent spawn. Read gate JSON for failure details: `plans.complete` (incomplete plans), `steps.fl` (failed validation gates), `tst.fl` (test failures). Generate remediation: for incomplete plans, route back to Step 7. For failed gates, identify which step artifacts are missing. For test failures, route to Senior for re-spec. Do NOT spawn QA agents until post-phase gate passes -- this saves LLM cost on obviously-broken phases.

Post-phase gate result is available to QA agents via `{phase-dir}/.qa-gate-results.jsonl`. QA Lead and QA Code can reference prior gate results for incremental verification.

1. Update execution state: `"step": "qa"`
2. **Tier resolution:** turbo=skip, fast=quick, balanced=standard, thorough=deep.
2.5. **Teammate registration (team_mode=teammate only):** Lead registers qa and qa-code as teammates in the department team. QA Lead receives plan.jsonl + summary.jsonl via SendMessage from Lead. QA Code receives summary.jsonl + test-plan.jsonl via SendMessage. QA Lead sends `qa_result` to Lead via SendMessage. QA Code sends `qa_code_result` to Lead via SendMessage. If QA Code result is PARTIAL/FAIL, QA Code also writes gaps.jsonl as a file artifact (not SendMessage -- it is a persistent artifact for remediation). In task mode, this step is skipped (qa/qa-code spawned via Task tool as documented below).
3. Compile context:
   - `bash ${CLAUDE_PLUGIN_ROOT}/scripts/compile-context.sh {phase} qa {phases_dir}`
   - `bash ${CLAUDE_PLUGIN_ROOT}/scripts/compile-context.sh {phase} qa-code {phases_dir}`

**QA Lead (plan-level):**
4. Spawn yolo-qa:
   - model: "${QA_MODEL}"
   - Provide: plan.jsonl files, summary.jsonl files, compiled context
   - Tier: {tier}

   > **Tool permissions:** When spawning agents, resolve project-type-specific tool permissions:
   > ```bash
   > TOOL_PERMS=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-tool-permissions.sh --role "qa" --project-dir ".")
   > ```
   > Include resolved `disallowed_tools` from the output in the agent's compiled context (.ctx-qa.toon). See D4 in architecture for soft enforcement details.

5. QA Lead produces verification.jsonl. Commits: `docs({phase}): verification results`

**QA Code (code-level):**
6. Spawn yolo-qa-code:
   - model: "${QA_CODE_MODEL}"
   - Provide: summary.jsonl (for file list), test-plan.jsonl (for TDD compliance), compiled context
   - Tier: {tier}

   > **Tool permissions:** When spawning agents, resolve project-type-specific tool permissions:
   > ```bash
   > TOOL_PERMS=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-tool-permissions.sh --role "qa-code" --project-dir ".")
   > ```
   > Include resolved `disallowed_tools` from the output in the agent's compiled context (.ctx-qa-code.toon). See D4 in architecture for soft enforcement details.

7. QA Code runs TDD compliance (Phase 0), tests, lint, patterns. For shell/bats projects: `bash scripts/test-summary.sh` (single invocation, outputs `PASS (N tests)` or `FAIL (F/N failed)` with details — never invoke bats directly). Produces qa-code.jsonl. Commits: `docs({phase}): code quality review`

**Result handling:**
- Both PASS → Manual QA (if enabled) → Step 10 (or Step 11 if security disabled)
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
12. If all PASS (automated + manual) → proceed to Step 10.
13. **EXIT GATE:** Verify `{phase-dir}/verification.jsonl` exists with valid JSONL (`jq empty`). Verify `{phase-dir}/qa-code.jsonl` exists with valid JSONL. Update `.execution-state.json`: set `steps.qa.status` to `"complete"`, `steps.qa.completed_at` to ISO timestamp, `steps.qa.artifact` to `"{phase-dir}/verification.jsonl"`. Commit: `chore(state): qa complete phase {N}`.

### Step 8.5: Documentation (optional — Documenter Agent)

**Guard:** Skip if documenter config is `'never'`. Skip if effort=turbo. Skip Output per template. Commit: `chore(state): documentation skipped phase {N}`.

**ENTRY GATE:** Verify `{phase-dir}/code-review.jsonl` exists with `r: "approve"` in line 1. If not: STOP "Step 8 artifact missing — code-review.jsonl not approved. Run step 8 first."

1. **Resolve documenter gate:**
   ```bash
   GATE_RESULT=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-documenter-gate.sh \
     --config .yolo-planning/config.json --defaults ${CLAUDE_PLUGIN_ROOT}/config/defaults.json)
   DOC_SPAWN=$(echo "$GATE_RESULT" | jq -r '.spawn')
   ```
   - If `DOC_SPAWN=false` (documenter='on_request' and user did not request): skip. Display: `○ Documentation skipped (on_request, not requested)`
   - If `DOC_SPAWN=true` (documenter='always' or user requested): proceed.

2. **Spawn per-department documenter** based on active departments:
   - Backend active: spawn yolo-documenter
   - Frontend active: spawn yolo-fe-documenter
   - UI/UX active: spawn yolo-ux-documenter
   - Provide: plan.jsonl files, summary.jsonl files, code-review.jsonl, compiled context

3. Documenter produces docs.jsonl. Commits: `docs({phase}): documentation`

4. **Non-blocking:** QA (Step 9) proceeds regardless of documenter status. Documentation is additive, not a gate.

5. **EXIT GATE:** Artifact: `docs.jsonl` (valid JSONL, if produced). State: `steps.documentation = complete`. Commit: `chore(state): documentation complete phase {N}`.

### Step 10: Security Audit (optional — Per-Department Security Reviewers)

**Guard:** Skip if `--skip-security` OR config `security_audit` != true. Skip Output per template. Commit: `chore(state): security skipped phase {N}`.

**ENTRY GATE:** Verify `{phase-dir}/verification.jsonl` exists OR `steps.qa.status` is `"skipped"` in `.execution-state.json`. If neither: STOP "Step 9 artifact missing — verification.jsonl not found. Run step 9 first."

1. Update execution state: `"step": "security"`
2. **Per-department security dispatch:** Each active department gets its own scoped Security Reviewer. Compile context per dept:
   - Backend active: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/compile-context.sh {phase} security {phases_dir}`
   - Frontend active: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/compile-context.sh {phase} fe-security {phases_dir}`
   - UI/UX active: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/compile-context.sh {phase} ux-security {phases_dir}`

2.5. **Teammate registration (team_mode=teammate only):** Each department Lead registers its security reviewer as a teammate within that department's team. Security receives summary.jsonl file list via SendMessage from Lead. Security sends `security_audit` result to Lead via SendMessage. FAIL result from ANY department is still a hard stop regardless of transport mode. In task mode, this step is skipped (security spawned via Task tool as documented below).

3. **Spawn per-department security reviewers** for each active department:
   - Backend: spawn yolo-security (BE-scoped — backend code, APIs, auth, data access)
   - Frontend: spawn yolo-fe-security (FE-scoped — XSS, CSP, client-side storage, bundle analysis)
   - UI/UX: spawn yolo-ux-security (UX-scoped — accessibility compliance, PII exposure, input validation)

   When multiple departments active, spawn in parallel. Each reviewer receives:
   - model: "${SECURITY_MODEL}" (resolved per dept role)
   - Provide: summary.jsonl (file list), compiled context (dept-scoped)

   > **Tool permissions:** When spawning agents, resolve project-type-specific tool permissions:
   > ```bash
   > TOOL_PERMS=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-tool-permissions.sh --role "security" --project-dir ".")
   > ```
   > Include resolved `disallowed_tools` from the output in the agent's compiled context (.ctx-security.toon). See D4 in architecture for soft enforcement details.

4. Each Security Reviewer produces security-audit.jsonl (dept-prefixed when multi-dept: fe-security-audit.jsonl, ux-security-audit.jsonl). Commits: `docs({phase}): security audit`
5. If `r: "FAIL"` from ANY department: **HARD STOP**. Display findings from failing department. Only user `--force` overrides.
6. If `r: "WARN"`:
   - Display warnings.
   - If `config.approval_gates.security_warn` is true: pause for user approval.
   - Otherwise: continue.
7. If `r: "PASS"` from all departments: continue.
8. **EXIT GATE:** Artifact: `security-audit.jsonl` (valid JSONL, per-dept when multi-dept). State: `steps.security = complete`. Commit: `chore(state): security complete phase {N}`.

### Step 11: Sign-off (Lead)

**ENTRY GATE:** Verify `{phase-dir}/security-audit.jsonl` exists OR `steps.security.status` is `"skipped"` in `.execution-state.json`. Also verify `{phase-dir}/code-review.jsonl` exists with `r: "approve"`. If security artifact missing AND security not skipped: STOP "Step 10 artifact missing — security-audit.jsonl not found. Run step 10 first."

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
3.5. **Teammate shutdown (team_mode=teammate only):** If team_mode=teammate, Lead executes the shutdown protocol before cleanup:
   - Send `shutdown_request` to all registered teammates per agents/yolo-lead.md ## Shutdown Protocol Enforcement.
   - Collect responses (30s deadline).
   - Log timeouts and incomplete work as deviations.
   - When team_mode=task: skip this step entirely (Task tool sessions end naturally).
4. **Cleanup:** If multi_dept=true, run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/dept-cleanup.sh --phase-dir {phase-dir} --reason complete` to remove coordination files. If single-dept: no additional cleanup.
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
8. **EXIT GATE:** Artifact: `.execution-state.json` (status: complete, step: signoff) + ROADMAP.md updated. State commit in item 5 -- no additional commit.

## Execution State Transitions (Enforcement Contract)

**This table is the enforcement contract.** go.md MUST verify the Entry Artifact column before running each step and verify the Exit Artifact column after each step completes. No exceptions.

| Step | state.step | Entry Artifact | Exit Artifact | Commit Format | Skip Conditions |
|------|-----------|----------------|---------------|---------------|----------------|
| 0. PO | `po` | Analyze output OR active milestone | `scope-document.json` (PO-APPROVED) | `chore(state): po complete phase {N}` | `po.enabled=false`, `--effort=turbo`, scope-document.json exists |
| 1. Critique | `critique` | Phase dir exists | `critique.jsonl` | `docs({phase}): critique and gap analysis` | `--effort=turbo`, critique.jsonl exists |
| 2. Research | `research` | `critique.jsonl` OR step 1 skipped | `research.jsonl` | `docs({phase}): research findings` | `--effort=turbo` |
| 3. Architecture | `architecture` | `research.jsonl` OR step 2 skipped | `architecture.toon` (completeness validated per rnd-handoff-protocol.md) | `docs({phase}): architecture design` | architecture.toon exists |
| 4. Load Plans | `planning` | `architecture.toon` OR step 3 skipped | `.execution-state.json` + `*.plan.jsonl` | `chore(state): execution state phase {N}` | NONE (mandatory) |
| 5. Design Review | `design_review` | `*.plan.jsonl` exists | enriched `plan.jsonl` (all tasks have `spec`) | `docs({phase}): enrich plan {NN-MM} specs` | NONE (mandatory) |
| 6. Test Authoring | `test_authoring` | enriched `plan.jsonl` with `spec` fields | `test-plan.jsonl` + test files | `test({phase}): RED phase tests for plan {NN-MM}` | `--effort=turbo`, no `ts` fields |
| 7. Implementation | `implementation` | enriched `plan.jsonl` + `test-plan.jsonl` (if step 6 ran) | `{plan_id}.summary.jsonl` per plan | `{type}({phase}-{plan}): {task}` per task | NONE (mandatory) |
| 8. Code Review | `code_review` | `{plan_id}.summary.jsonl` for each plan | `code-review.jsonl` with `r: "approve"` | `docs({phase}): code review {NN-MM}` | NONE (mandatory) |
| 8.5. Documentation | `documentation` | `code-review.jsonl` with `r: "approve"` | `docs.jsonl` (if produced) | `docs({phase}): documentation` | `documenter='never'`, `--effort=turbo` |
| 9. QA | `qa` | `code-review.jsonl` with `r: "approve"` | `verification.jsonl` + `qa-code.jsonl` | `docs({phase}): verification results` | `--skip-qa`, `--effort=turbo` |
| 10. Security | `security` | `verification.jsonl` OR step 9 skipped | `security-audit.jsonl` | `docs({phase}): security audit` | `--skip-security`, config `security_audit` != true |
| 11. Sign-off | `signoff` | `security-audit.jsonl` OR step 10 skipped + `code-review.jsonl` approved | `.execution-state.json` complete + ROADMAP.md | `chore(state): phase {N} complete` | NONE (mandatory) |

Each transition commits `.execution-state.json` so resume works on exit. Schema: see Step 4 item 7 above. Per-step status values: `"pending"`, `"running"`, `"complete"`, `"skipped"`. The `reason` field is populated only for skipped steps.

**Multi-department note:** When `multi_dept=true`, `.phase-orchestration.json` is created alongside `.execution-state.json` and tracks per-department status and gate state. See ## Multi-Department Execution above for schema.

## Change Management

Formalizes the Senior-Dev revision cycle and classification system. Referenced by agents/yolo-senior.md and agents/yolo-dev.md.

### Senior-Dev Revision Cycle

When Senior's code review requests changes (Step 8):
1. Senior classifies findings as **Minor** or **Major**:
   - **Minor**: Nits, style, naming, formatting. Does not affect logic or architecture.
   - **Major**: Logic errors, missing error handling, architecture violations, security issues.
2. Senior sends `code_review_changes` to Dev with exact fix instructions.
3. Dev fixes per instructions precisely -- no creative interpretation.
4. Dev recommits and Senior re-reviews (cycle 2).

### Cycle Limits and Escalation

- **Cycle 1 (Minor only)**: If ALL findings are Minor (nits), Senior auto-approves after Dev fixes. No cycle 2 needed.
- **Cycle 1 (Major findings)**: Dev fixes, Senior re-reviews in cycle 2.
- **Cycle 2 (still failing)**: Senior escalates to Lead via `escalation` schema.
- **Lead decision**: Accept with known issues (mark as accepted_risk in code-review.jsonl) OR escalate to Architect for design change.

### Collaborative Relationship (per R7)

Senior-Dev relationship is collaborative, not gatekeeping:
- Senior sends suggestions and exact fix instructions
- Dev retains decision power within spec boundaries
- If Dev disagrees with a finding: Dev documents rationale and Senior considers it
- Senior can override only on Major findings with documented reasoning

### Phase 4 Metric Collection Hooks

The following metrics are collected at each review cycle for Phase 4 continuous QA instrumentation:
- `cycle_count`: Number of review cycles for this plan (1 or 2)
- `finding_severity_distribution`: Count of critical/major/minor/nit findings per cycle
- `time_per_cycle`: Timestamp delta between code_review_changes sent and Dev recommit
- `escalation_triggered`: Boolean -- did cycle 2 trigger Lead escalation?

Phase 4 can instrument at these hook points without modifying Phase 3 artifacts. Hooks are observation points (metric recording), not control points (decision gates).

See @references/company-hierarchy.md ## Code Review Chain for the escalation path.
See @references/rnd-handoff-protocol.md for the R&D pipeline handoff.

## Escalation Handling

When a Dev agent encounters a blocker it cannot resolve, the escalation flows upward through the company hierarchy until resolved. This section documents the exact upward path and timeout behavior.

### Upward Escalation Flow

**Level 1: Dev -> Senior**
Dev sends `dev_blocker` schema to Senior (via SendMessage in teammate mode, via Task result in task mode). Dev includes: blocker description, what was attempted, what is needed. Dev pauses current task (see ## Dev Pause Behavior below).

**Level 2: Senior attempts resolution**
Senior receives dev_blocker. Senior may: (a) clarify the spec and send updated instructions via `code_review_changes`, or (b) determine the issue is beyond spec-level and escalate to Lead via `escalation` schema.

**Level 3: Lead assesses authority**
Lead receives escalation from Senior. Lead checks Decision Authority Matrix (see company-hierarchy.md). If within Lead's authority (task ordering, resource allocation, plan decomposition): Lead resolves and sends `escalation_resolution` back to Senior. If beyond Lead's authority (architecture, technology, scope): Lead escalates to Architect (single-dept) or Owner (multi-dept) via `escalation` schema.

**Level 4: Architect/Owner -> go.md -> User**
Architect receives escalation. Architect packages a structured escalation with an options array containing 2-3 concrete choices for the user. Architect sends this to Lead via SendMessage (teammate mode) or returns via Task result (task mode). Lead forwards to go.md. go.md calls AskUserQuestion presenting:
- Blocker summary (1-2 sentences)
- Evidence bullets (from escalation chain)
- 2-3 concrete resolution options (from Architect's options array)
- Recommendation (Architect's preferred option, if any)

In multi-dept mode: Lead sends to Owner instead of Architect. Owner routes through go.md identically.

**[teammate]** Intra-team escalation (Dev->Senior->Lead->Architect) uses SendMessage. Cross-team escalation (Lead->Owner, Architect->go.md) uses file-based artifacts per D3.

**[task]** All escalation uses Task tool result returns or direct communication within the orchestrator session.

### Timeout-Based Auto-Escalation

If an escalation remains at one level longer than `escalation.timeout_seconds` (default 300s from config/defaults.json):
1. The orchestrator detects the timeout via `check-escalation-timeout.sh` (periodic call during Step 7)
2. Auto-escalation fires ONLY if the current level has NOT already escalated upward (prevents duplicates per D4)
3. The escalation's `level` field is updated to the next level, `last_escalated_at` is refreshed
4. An `escalation_timeout_warning` schema is generated and sent to the next level
5. If `escalation.auto_owner_on_timeout` is true and timeout fires at Architect level: auto-involve Owner/go.md to present to user

### Max Round-Trips

`escalation.max_round_trips` (default 2) caps how many times the same blocker (by escalation id) can bounce between levels. After max reached: force resolution at current level or STOP execution with blocker report to user.

### Dev Pause Behavior

**task mode:** Dev is a single-threaded Task session. When blocked, the orchestrator (Lead) simply does not assign the next task until the escalation resolves. The Dev Task session either completes (reporting the blocker in its return value) or remains active.

**teammate mode:** Dev sends dev_blocker to Senior and continues the claim loop. The blocked task is NOT available for re-claiming (its status is claimed, not available). Dev may work on other unblocked tasks while waiting. On receiving resolution instructions from Senior (via code_review_changes), Dev resumes the blocked task.

## Multi-Department Execution

**Detection:** `multi_dept` from resolve-departments.sh. If false: skip this section entirely. All Steps 1-11 above apply to single-dept unchanged.

**When multi_dept=true:**

1. **Generate spawn plan:**
   ```bash
   SPAWN_PLAN=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/dept-orchestrate.sh \
     .yolo-planning/config.json {phase-dir})
   ```
   Returns JSON: `{"waves":[{"id":1,"depts":["uiux"],"gate":"handoff-ux-complete"},{"id":2,"depts":["frontend","backend"],"gate":"all-depts-complete"}],"timeout_minutes":30}`

2. **Create orchestration state:**
   Write `.phase-orchestration.json` to phase directory with schema:
   ```json
   {
     "phase": "{N}",
     "multi_dept": true,
     "workflow": "parallel",
     "departments": {
       "uiux": {"status":"pending","step":"","started":"","completed":""},
       "frontend": {"status":"pending","step":"","started":"","completed":""},
       "backend": {"status":"pending","step":"","started":"","completed":""}
     },
     "gates": {
       "ux-complete": {"status":"pending","passed_at":""},
       "api-contract": {"status":"pending","passed_at":""},
       "all-depts": {"status":"pending","passed_at":""}
     },
     "integration_qa": {"status":"pending"},
     "security": {"status":"pending"},
     "owner_signoff": {"status":"pending"},
     "started_at": "ISO8601",
     "timeout_minutes": 30
   }
   ```
   Commit: `chore(state): orchestration state phase {N}`

3. **Spawn department Leads per wave (OBEY spawn strategy gate at top of this file):**

   **If `team_mode=teammate` (MANDATORY — do NOT fall back to Task tool):**

   **IMPORTANT:** The orchestrator (go.md) does NOT call TeamCreate/spawnTeam directly. Each Lead creates its own department team. This avoids the Claude Code API constraint: "a leader can only manage one team at a time." Since each Lead is a separate subagent context, each can independently lead one team.

   For each wave in spawn plan:
   ```
   For each dept in wave.depts:
     1. Spawn Lead using Task tool (NOT TeamCreate — Lead creates its own team):
        - model: resolved via resolve-agent-model.sh for {dept}-lead role
        - Provide: dept CONTEXT file, phase-dir, ROADMAP.md, REQUIREMENTS.md
        - Include in prompt: "team_mode=teammate. Create team yolo-{dept} via TeamCreate,
          then register specialists as teammates."
     2. Lead calls TeamCreate: spawnTeam(name="yolo-{dept}", description="{Dept} team for phase {N}")
     3. Lead registers core specialists (architect, senior, dev) as teammates at creation
     4. Additional specialists on-demand: tester at step 6, qa+qa-code at step 9, security at step 10 (backend only)
     5. Full rosters: Backend 7 (incl security), Frontend 6, UI/UX 6
     6. Lead coordinates via SendMessage within team
     7. On completion: Lead sends shutdown_request to all teammates, then writes department_result
   ```
   Parallel waves: spawn all Leads in one message (each creates its own team independently).
   Cross-team coordination still uses file-based handoff artifacts (Leads are in different teams, SendMessage is intra-team only). See `references/teammate-api-patterns.md` ## Cross-Team Communication.

   **If `team_mode=task`:**

   For each wave in spawn plan, spawn department Leads as background Task subagents (`run_in_background=true`):
   ```
   For each dept in wave.depts:
     Spawn {dept} Lead as Task subagent:
       - run_in_background: true
       - model: resolved via resolve-agent-model.sh for {dept}-lead role
       - Provide: dept CONTEXT file, phase-dir, ROADMAP.md, REQUIREMENTS.md
       - Lead runs full 11-step workflow using foreground Task subagents internally
       - On completion: Lead writes .dept-status-{dept}.json via dept-status.sh
       - On completion: Lead writes handoff sentinel (e.g., .handoff-ux-complete)
   ```
   File-based coordination via dept-gate.sh, dept-status.sh, and handoff sentinels.

4. **Poll for gate satisfaction:**
   After spawning a wave, enter polling loop:
   ```bash
   # Polling loop pattern (per-gate)
   ELAPSED=0
   TIMEOUT=$((TIMEOUT_MINUTES * 60))
   while ! bash ${CLAUDE_PLUGIN_ROOT}/scripts/dept-gate.sh \
     --gate {gate-name} --phase-dir {phase-dir} --no-poll; do
     sleep 0.5
     ELAPSED=$((ELAPSED + 1))
     if [ "$ELAPSED" -ge "$((TIMEOUT * 2))" ]; then
       echo "TIMEOUT: Gate {gate-name} not satisfied after ${TIMEOUT_MINUTES}m"
       bash ${CLAUDE_PLUGIN_ROOT}/scripts/dept-cleanup.sh \
         --phase-dir {phase-dir} --reason timeout
       STOP with per-department status report
     fi
   done
   ```
   Interval: 500ms (sleep 0.5). Timeout: configurable (default 30 minutes).

   **Teammate mode note:** When `team_mode=teammate`, gate satisfaction shifts from file polling to SendMessage-based status reporting. Department Leads send completion signals via SendMessage to go.md instead of writing sentinel files. The polling loop above applies only to `team_mode=task`. In teammate mode, go.md receives department_result messages asynchronously via teammate message delivery. Cross-department gates (ux-complete, api-contract, all-depts) still use file-based validation via dept-gate.sh because cross-team SendMessage is not possible.

5. **On all departments complete:**
   - Verify via `dept-gate.sh --gate all-depts --phase-dir {phase-dir}`
   - Proceed to Integration QA (foreground, Step 9 equivalent)
   - Proceed to Security audit (foreground, Step 10 equivalent)
   - Proceed to Owner sign-off (Step 11)

6. **Cleanup on completion or failure:**
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/dept-cleanup.sh \
     --phase-dir {phase-dir} --reason {complete|failure|timeout}
   ```
   Removes: .dept-status-*.json, .handoff-*, .dept-lock-*, .phase-orchestration.json

**Full protocol details:** See references/multi-dept-protocol.md for dispatch flow and coordination files. See references/cross-team-protocol.md for handoff gate definitions. REQ-03: Multi-department orchestration via file-based coordination.

**Teammate mode per-department 11-step:** When `team_mode=teammate`, the per-department 11-step workflow is identical in logic but uses SendMessage for intra-team coordination instead of Task tool spawning. The Lead creates the team via spawnTeam and registers specialists on-demand:
- **Team creation:** Lead registers architect, senior, dev as teammates
- **Step 6:** Lead registers tester as teammate. Tester sends test_plan_result to Senior (not Lead) via SendMessage.
- **Step 9:** Lead registers qa + qa-code as teammates. Both send results to Lead via SendMessage. QA Code writes gaps.jsonl as file artifact if PARTIAL/FAIL.
- **Step 10 (backend only):** Lead registers security as teammate. Security sends security_audit to Lead via SendMessage. FE/UX teams skip this step.
- **Shutdown:** On department completion, Lead sends shutdown_request to all registered teammates. Each teammate commits pending artifacts and sends shutdown_response. Lead then writes .dept-status-{dept}.json (file-based, for cross-department gate) and sends department_result.
See `references/teammate-api-patterns.md` ## Team Lifecycle for spawnTeam and shutdown patterns. See ## Registering Teammates for the full step-to-role mapping.

**Execution state extension:** `.execution-state.json` gains `departments` object when multi_dept=true, mirroring `.phase-orchestration.json` department statuses for resume support.

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/yolo-brand-essentials.toon — Phase Banner, ◆ running, ✓ complete, ✗ failed, ○ skipped, no ANSI color codes.
