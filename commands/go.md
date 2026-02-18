---
name: go
description: "The one command. Detects state, parses intent, routes to any lifecycle mode -- bootstrap, scope, plan, execute, discuss, archive, and more."
argument-hint: "[intent or flags] [--plan] [--execute] [--discuss] [--assumptions] [--scope] [--add] [--insert] [--remove] [--archive] [--yolo] [--effort=level] [--skip-qa] [--skip-audit] [--plan=NN] [N]"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, WebFetch
disable-model-invocation: true
---

# YOLO Go: $ARGUMENTS

## Owner-First Principle (Universal)

The Owner is the SOLE point of contact with the user — in ALL modes, not just multi-department.

- **Single-department mode:** go.md itself acts as the Owner proxy. All user interaction (questions, confirmations, status updates) flows through go.md. No subagent (Lead, Senior, Dev, QA) communicates with the user directly.
- **Multi-department mode:** go.md acts as the Owner proxy for context gathering. The yolo-owner agent is spawned for critique review, conflict resolution, and sign-off. No department lead or subagent talks to the user.
- **Escalation path:** Dev → Senior → Lead → (Owner agent if multi-dept) → go.md → User. Never skip levels.
- **Redirects (`/yolo:debug`, `/yolo:fix`, `/yolo:research`):** go.md confirms intent with the user first, then delegates to the specialized command. The command itself handles user interaction through its own protocol.

## Context

Working directory: `!`pwd``

Pre-computed state (via phase-detect.sh):

```
!`bash ${CLAUDE_PLUGIN_ROOT}/scripts/phase-detect.sh 2>/dev/null || echo "phase_detect_error=true"`
```

Config:

```
!`cat .yolo-planning/config.json 2>/dev/null || echo "No config found"`
```

Department routing (via resolve-departments.sh):

```
!`bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-departments.sh .yolo-planning/config.json 2>/dev/null || echo "multi_dept=false"`
```

Team mode (via resolve-team-mode.sh):

```
!`bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-team-mode.sh .yolo-planning/config.json 2>/dev/null || echo "team_mode=task"`
```

Complexity routing (via complexity-classify.sh — only invoked when Path 0 is active):

```
!`bash ${CLAUDE_PLUGIN_ROOT}/scripts/complexity-classify.sh --intent "$ARGUMENTS" --config .yolo-planning/config.json --codebase-map "$has_codebase_map" 2>/dev/null || echo '{"complexity":"high","confidence":0,"suggested_path":"full_ceremony"}'`
```

Key variables from above (MANDATORY — read these before any mode):

- `multi_dept`: true = multi-department orchestration active, false = single backend lead only
- `workflow`: parallel | sequential | backend_only
- `leads_to_spawn`: pipe-separated waves, comma-separated parallel (e.g., `ux-lead|fe-lead,lead`)
- `spawn_order`: single | wave | sequential
- `owner_active`: true if Owner agent should be spawned for cross-dept review
- `fe_active` / `ux_active`: individual department flags
- `team_mode`: task = spawn agents via Task tool (default), teammate = spawn agents via Teammate API (experimental), auto = detect based on CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS env var (teammate if set + agent_teams=true, otherwise falls back to task)
- `fallback_notice`: true if team_mode was downgraded from teammate to task (display notice to user)
- `config_complexity_routing`: true = complexity-aware routing enabled (Path 0 active), false = skip Path 0
- `config_trivial_threshold`: minimum confidence for trivial path (default 0.85)
- `config_medium_threshold`: minimum confidence for medium path (default 0.7)
- `config_fallback_path`: default path when confidence is too low (default "high")

## Input Parsing

Four input paths, evaluated in order:

### Path 0: Complexity-Aware Routing

**Guard:** Skip if `config_complexity_routing=false` from phase-detect output. Skip if mode flags detected (--plan, --execute, --discuss, etc.). Skip if no $ARGUMENTS present.

When `config_complexity_routing=true` AND $ARGUMENTS present AND no mode flags detected:

1. **Check shell classifier result:** Read `skip_analyze` from the pre-computed complexity-classify.sh output (Context section above). This field indicates whether the shell classifier's confidence is high enough to skip the LLM-based Analyze agent.

2. **Conditional Analyze spawn:**
   - **If `skip_analyze=true`:** Use the shell classifier's output directly as the analysis JSON. Skip spawning the Analyze agent entirely. Display: `○ Shell classifier confidence sufficient — skipping Analyze agent`. The classify.sh output already contains complexity, departments, intent, confidence, reasoning, and suggested_path fields.
   - **If `skip_analyze=false` OR `complexity=high`:** Spawn the Analyze agent for deeper LLM classification:
     ```
     ANALYZE_MODEL=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-model.sh analyze .yolo-planning/config.json ${CLAUDE_PLUGIN_ROOT}/config/model-profiles.json)
     ```
     Spawn yolo-analyze via Task tool with model: "${ANALYZE_MODEL}". Pass:
     - User intent text: $ARGUMENTS
     - Phase-detect output summary (phase state, brownfield, codebase map status)
     - Config path: `.yolo-planning/config.json`
     - Codebase map status: `has_codebase_map` value
     - Shell classifier result (classify.sh output) as `classify_result` for secondary validation

3. **Receive analysis JSON** from Analyze agent (or use classify.sh output if skipped) with fields: complexity, departments, intent, confidence, reasoning, suggested_path.

4. **Route based on suggested_path:**
   - `trivial_shortcut` (confidence >= `config_trivial_threshold`):
     ```bash
     result=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/route-trivial.sh \
       --phase-dir "{phase-dir}" --intent "$ARGUMENTS" \
       --config .yolo-planning/config.json --analysis-json /tmp/yolo-analysis.json)
     ```
     Then dispatch to **Mode: Trivial Shortcut** below.
   - `medium_path` (confidence >= `config_medium_threshold`):
     ```bash
     result=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/route-medium.sh \
       --phase-dir "{phase-dir}" --intent "$ARGUMENTS" \
       --config .yolo-planning/config.json --analysis-json /tmp/yolo-analysis.json)
     ```
     Then dispatch to **Mode: Medium Path** below.
   - `full_ceremony`: Call `bash ${CLAUDE_PLUGIN_ROOT}/scripts/route-high.sh` (if exists), then proceed to **PO Layer** (if enabled) before existing Plan+Execute flow (full ceremony).
   - `medium_path` with PO: If `po.enabled=true`, run abbreviated PO (single-round Questionary, skip Roadmap Agent) before medium path dispatch.
   - `redirect`: Map Analyze intent to existing redirects:
     - debug → Redirect to `/yolo:debug` with $ARGUMENTS
     - fix → Redirect to `/yolo:fix` with $ARGUMENTS
     - research → Redirect to `/yolo:research` with $ARGUMENTS

5. **Confidence fallback:** If confidence < `config_medium_threshold`: fall through to Path 2 (natural language intent) as fallback. Display: `○ Analyze confidence too low ({confidence}) — falling back to intent detection`.

### Path 1: Flag detection

Check $ARGUMENTS for flags. If any mode flag is present, go directly to that mode:

- `--plan [N]` -> Plan mode
- `--execute [N]` -> Execute mode
- `--discuss [N]` -> Discuss mode
- `--assumptions [N]` -> Assumptions mode
- `--scope` -> Scope mode
- `--add "desc"` -> Add Phase mode
- `--insert N "desc"` -> Insert Phase mode
- `--remove N` -> Remove Phase mode
- `--archive` -> Archive mode

Behavior modifiers (combinable with mode flags):

- `--effort <level>`: thorough|balanced|fast|turbo (overrides config)
- `--skip-qa`: skip post-build QA
- `--skip-audit`: skip pre-archive audit
- `--yolo`: skip all confirmation gates, auto-loop remaining phases
- `--plan=NN`: execute single plan (bypasses wave grouping)
- Bare integer `N`: targets phase N (works with any mode flag)

If flags present: skip confirmation gate (flags express explicit intent).

### Path 2: Natural language intent

If $ARGUMENTS present but no flags detected, interpret user intent:

- Debug keywords (debug, investigate, bug, error, broken, crash, failing, diagnose) -> Redirect to `/yolo:debug` with $ARGUMENTS
- Fix keywords (fix, patch, hotfix, quick fix, tweak, small change) -> Redirect to `/yolo:fix` with $ARGUMENTS
- Research keywords (research, look up, find out, what is, how does, explore docs) -> Redirect to `/yolo:research` with $ARGUMENTS
- Discussion keywords (talk, discuss, think about, what about) -> Discuss mode
- Assumption keywords (assume, assuming, what if, what are you assuming) -> Assumptions mode
- Planning keywords (plan, scope, break down, decompose, structure) -> Plan mode
- Execution keywords (build, execute, run, do it, go, make it, ship it) -> Execute mode
- Phase mutation keywords (add, insert, remove, skip, drop, new phase) -> relevant Phase Mutation mode
- Completion keywords (done, ship, archive, wrap up, finish, complete) -> Archive mode
- Ambiguous -> AskUserQuestion with 2-3 contextual options

ALWAYS confirm interpreted intent via AskUserQuestion before executing.

### Path 3: State detection (no args)

If no $ARGUMENTS, evaluate phase-detect.sh output. First match determines mode:

| Priority | Condition | Mode | Confirmation |
|---|---|---|---|
| 1 | `planning_dir_exists=false` | Init redirect | (redirect, no confirmation) |
| 2 | `project_exists=false` | Bootstrap | "No project defined. Set one up?" |
| 3 | `phase_count=0` | Scope | "Project defined but no phases. Scope the work?" |
| 4 | `next_phase_state=needs_plan_and_execute` | Plan + Execute | "Phase {N} needs planning and execution. Start?" |
| 5 | `next_phase_state=needs_execute` | Execute | "Phase {N} has plan.jsonl files. Execute it?" |
| 6 | `next_phase_state=all_done` | Archive | "All phases complete. Run audit and archive?" |

### Confirmation Gate

Every mode triggers confirmation via AskUserQuestion before executing, with contextual options (recommended action + alternatives).

- **Exception:** `--yolo` skips all confirmation gates. Error guards (missing roadmap, uninitialized project) still halt.
- **Exception:** Flags skip confirmation (explicit intent).

## Modes

**Model resolution pattern** (used in Scope, Plan, Execute): `ROLE_MODEL=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-model.sh {role} .yolo-planning/config.json ${CLAUDE_PLUGIN_ROOT}/config/model-profiles.json)`. Check $?; non-zero = abort with stderr.

### PO Layer (Product Owner — optional, config-gated)

**Guard:** Skip PO layer entirely if ANY of:
- `po.enabled=false` in config (backward compat — existing Critic→Architect→Lead flow unchanged)
- `--effort=turbo` (PO skipped at turbo)
- Path 0 result is `trivial_shortcut` (PO skipped for trivial tasks)

**When `po.enabled=true` AND guard conditions not met:**

PO layer runs AFTER Analyze routing and BEFORE Critic→Architect→Lead dispatch. It replaces Owner Mode 0 (context gathering) with structured scope clarification.

1. **Resolve PO model:**
   ```
   PO_MODEL=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-model.sh po .yolo-planning/config.json ${CLAUDE_PLUGIN_ROOT}/config/model-profiles.json)
   ```

2. **Spawn yolo-po** via Task tool with model: "${PO_MODEL}". Pass:
   - User intent text: $ARGUMENTS
   - analysis.json from Analyze step (complexity, departments, intent)
   - Codebase mapping: ARCHITECTURE.md, STRUCTURE.md (if `.yolo-planning/codebase/` exists)
   - Existing REQUIREMENTS.md and ROADMAP.md
   - Prior phase summaries (summary.jsonl from completed phases)
   - Display: `◆ Spawning PO (${PO_MODEL}) for scope clarification...`

3. **PO-Questionary loop** (orchestrated via po-scope-loop.sh):
   PO may emit `user_presentation` objects during scope gathering. For each:
   ```bash
   rendered=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/render-user-presentation.sh --json "$user_presentation_json")
   ```
   Present rendered content via AskUserQuestion with options from the user_presentation object. Feed user's response back to PO.

   The PO-Questionary loop runs via:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/po-scope-loop.sh \
     --config .yolo-planning/config.json \
     --phase-dir "{phase-dir}" \
     --max-rounds 3 \
     --confidence-threshold 0.85
   ```
   - `full_ceremony`: Full PO-Questionary loop (up to 3 rounds) + Roadmap Agent
   - `medium_path`: Single-round Questionary, skip Roadmap Agent
   - `fast` effort: Single-round Questionary, skip Roadmap Agent

4. **Roadmap Agent** (full_ceremony only, skip if medium_path or effort=fast):
   ```
   ROADMAP_MODEL=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-model.sh roadmap .yolo-planning/config.json ${CLAUDE_PLUGIN_ROOT}/config/model-profiles.json)
   ```
   Spawn yolo-roadmap with enriched scope from PO-Questionary output. Roadmap produces dependency graph:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/validate-deps.sh \
     --graph "{phase-dir}/roadmap-plan.json" \
     --format adjacency
   ```
   Validate no cycles in dependency graph. Display: `◆ Spawning Roadmap (${ROADMAP_MODEL})...` → `✓ Roadmap complete — {N} phases, critical path: {path}`

5. **PO writes scope-document.json** to phase directory. Contains: vision, enriched scope, requirements, roadmap (if produced), assumptions, deferred items.

6. **Vision sign-off** (PO Mode 3): PO emits final `user_presentation` for scope confirmation. Orchestrator renders via AskUserQuestion. On approval: PO marks scope as PO-APPROVED.
   Display: `✓ PO scope approved — dispatching to engineering`

7. **Dispatch to existing Critic→Architect→Lead flow** with enriched scope from PO. The scope-document.json is available to all downstream agents as additional context.

### Mode: Init Redirect

If `planning_dir_exists=false`: STOP "YOLO is not set up yet. Run /yolo:init to get started."

### Mode: Bootstrap

**Guard:** `.yolo-planning/` exists but no PROJECT.md.

**Critical Rules (non-negotiable):**

- NEVER fabricate content. Only use what the user explicitly states.
- If answer doesn't match question: STOP, handle their request, let them re-run.
- No silent assumptions -- ask follow-ups for gaps.
- Phases come from the user, not you.

**Constraints:** Do NOT explore/scan codebase (that's /yolo:map). Use existing `.yolo-planning/codebase/` if present.

**Brownfield detection:** `git ls-files` or Glob check for existing code.

**Steps:**

- **B1: PROJECT.md** -- If $ARGUMENTS provided (excluding flags), use as description. Otherwise ask name + core purpose. Then call:

  ```
  bash ${CLAUDE_PLUGIN_ROOT}/scripts/bootstrap/bootstrap-project.sh .yolo-planning/PROJECT.md "$NAME" "$DESCRIPTION"
  ```

- **B1.5: Discovery Depth** -- Read `discovery_questions` and `active_profile` from config. Map profile to depth: yolo=skip(0), prototype=quick(1-2), default=standard(3-5), production=thorough(5-8). If `discovery_questions=false`: force depth=skip. Store DISCOVERY_DEPTH for B2.

- **B2: REQUIREMENTS.md (Discovery)** -- If skip: 2 minimal AskUserQuestion (must-have features, target users). Create `discovery.json` with `{"answered":[],"inferred":[]}`. If quick/standard/thorough: follow `${CLAUDE_PLUGIN_ROOT}/references/discovery-protocol.md` Bootstrap Discovery (analyze description, scenario questions per depth count, then multiSelect checklists, synthesize to `discovery.json` with `answered[]` and `inferred[]`). Wording: no jargon, plain language, concrete situations, assume non-developer. After discovery:

    ```
    bash ${CLAUDE_PLUGIN_ROOT}/scripts/bootstrap/bootstrap-requirements.sh .yolo-planning/REQUIREMENTS.md .yolo-planning/discovery.json
    ```

- **B3: ROADMAP.md** -- Suggest 3-5 phases from requirements. If `.yolo-planning/codebase/` exists, read INDEX.md, PATTERNS.md, ARCHITECTURE.md, CONCERNS.md. Each phase: name, goal, mapped reqs, success criteria. Write phases JSON to temp file, then call:

  ```
  bash ${CLAUDE_PLUGIN_ROOT}/scripts/bootstrap/bootstrap-roadmap.sh .yolo-planning/ROADMAP.md "$PROJECT_NAME" /tmp/yolo-phases.json
  ```

  Script handles ROADMAP.md generation and phase directory creation.
- **B4: STATE.md** -- Extract project name, milestone name, and phase count from earlier steps. Call:

  ```
  bash ${CLAUDE_PLUGIN_ROOT}/scripts/bootstrap/bootstrap-state.sh .yolo-planning/STATE.md "$PROJECT_NAME" "$MILESTONE_NAME" "$PHASE_COUNT"
  ```

  Script handles today's date, Phase 1 status, empty decisions, and 0% progress.
- **B5: Brownfield summary** -- If BROWNFIELD=true AND no codebase/: count files by ext, check tests/CI/Docker/monorepo, add Codebase Profile to STATE.md.
- **B6: CLAUDE.md** -- Extract name + core value from PROJECT.md. Call `bash ${CLAUDE_PLUGIN_ROOT}/scripts/bootstrap/bootstrap-claude.sh CLAUDE.md "$PROJECT_NAME" "$CORE_VALUE" [CLAUDE.md]`. Pass existing CLAUDE.md as 4th arg for section preservation (script replaces only YOLO-managed sections). Omit 4th arg if no existing file. Max 200 lines.
- **B7: Transition** -- Display "Bootstrap complete. Transitioning to scoping..." Re-evaluate state, route to next match.

### Mode: Scope

**Guard:** PROJECT.md exists but `phase_count=0`.

**Delegation:** Scope delegates to the Architect agent (yolo-architect) for phase decomposition. See `references/company-hierarchy.md` for hierarchy.

**Steps:**

1. Load context: PROJECT.md, REQUIREMENTS.md (or reqs.jsonl). If `.yolo-planning/codebase/` exists, note available mapping docs.
2. If $ARGUMENTS (excl. flags) provided, use as scope description. Else ask: "What do you want to build?" Show uncovered requirements as suggestions.
3. Resolve Architect model (see pattern above).
4. Spawn yolo-architect as subagent via Task tool with:
   - model: "${ARCHITECT_MODEL}"
   - Mode: "scoping"
   - Provide: PROJECT.md, REQUIREMENTS.md, codebase/ mapping paths, user scope description
   - Display: `◆ Spawning Architect (${ARCHITECT_MODEL}) for scoping...`
5. Architect decomposes into 3-5 phases (name, goal, success criteria, mapped REQ-IDs, dependencies). Writes ROADMAP.md and creates phase dirs.
6. Display: `✓ Architect complete — scoping done`
7. Update STATE.md: Phase 1, status "Pending planning".
8. Display "Scoping complete. {N} phases created." STOP -- do not auto-continue to planning.

### Mode: Discuss

**Guard:** Initialized, phase exists in roadmap.
**Phase auto-detection:** First phase without `*.plan.jsonl`. All planned: STOP "All phases planned. Specify: `/yolo:go --discuss N`"

**Steps:**

1. Load phase goal, requirements, success criteria, dependencies from ROADMAP.md.
2. Ask 3-5 phase-specific questions across: essential features, technical preferences, boundaries, dependencies, acceptance criteria.
3. Write `.yolo-planning/phases/{phase-dir}/{phase}-CONTEXT.md` with sections: User Vision, Essential Features, Technical Preferences, Boundaries, Acceptance Criteria, Decisions Made.
4. Update `.yolo-planning/discovery.json`: append each question+answer to `answered[]` (category, phase, date), extract inferences to `inferred[]`.
5. Show summary, ask for corrections. Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/suggest-next.sh go`.

### Mode: Assumptions

**Guard:** Initialized, phase exists in roadmap.
**Phase auto-detection:** Same as Discuss mode.

**Steps:**

1. Load context: ROADMAP.md, REQUIREMENTS.md, PROJECT.md, STATE.md, CONTEXT.md (if exists), codebase signals.
2. Generate 5-10 assumptions by impact: scope (included/excluded), technical (implied approaches), ordering (sequencing), dependency (prior phases), user preference (defaults without stated preference).
3. Gather feedback per assumption: "Confirm, correct, or expand?" Confirm=proceed, Correct=user provides answer, Expand=user adds nuance.
4. Present grouped by status (confirmed/corrected/expanded). This mode does NOT write files. For persistence: "Run `/yolo:go --discuss {N}` to capture as CONTEXT.md." Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/suggest-next.sh go`.

### Mode: Plan

**Guard:** Initialized, roadmap exists, phase exists.
**Phase auto-detection:** First phase without `*.plan.jsonl`. All planned: STOP "All phases planned. Specify phase: `/yolo:go --plan N`"

**Steps:**

1. **Parse args:** Phase number (optional, auto-detected), --effort (optional, falls back to config).
1.5. **Fallback notice:** If `fallback_notice=true` from resolve-team-mode.sh, display: `[notice] Teammate API requested but unavailable (CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS not set). Using Task tool spawn instead.` This is informational only -- execution proceeds with team_mode=task.
2. **Phase Discovery (if applicable):** Skip if already planned or DISCOVERY_DEPTH=skip. If phase dir has `{phase}-CONTEXT.md`: AskUserQuestion "Existing context found for this phase. What would you like to do?" Options: (1) "Reuse existing context (Recommended)" — skip Phase Discovery, use existing file. (2) "Gather fresh context" — delete `{phase}-CONTEXT.md` and run Phase Discovery below. If no CONTEXT.md exists, run Phase Discovery: read `${CLAUDE_PLUGIN_ROOT}/references/discovery-protocol.md` Phase Discovery mode. Generate phase-scoped questions (quick=1, standard=1-2, thorough=2-3). Skip categories already in `discovery.json.answered[]`. Present via AskUserQuestion. Append to `discovery.json`. Write `{phase}-CONTEXT.md`.
3. **Context compilation:** If `config_context_compiler=true`, compile context for the appropriate leads (see step 5/6).
4. **Turbo shortcut:** If effort=turbo, skip Lead. Read phase reqs from ROADMAP.md, create single lightweight plan.jsonl inline (header + tasks, no spec field).
5. **Single-department planning (when `multi_dept=false` from resolve-departments.sh above):**
   - Compile context: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/compile-context.sh {phase} lead {phases_dir}`
   - Resolve Lead model (see pattern above).
   - **CRITICAL:** Add `model: "${LEAD_MODEL}"` parameter to the Task tool invocation.
   - **Spawn strategy (OBEY team_mode from pre-computed output above):**
     - **If `team_mode=teammate`:** Spawn yolo-lead via Task tool. Include in prompt: 'team_mode=teammate. Create team yolo-backend via TeamCreate, then register specialists as teammates. Use SendMessage to coordinate within your team. See @references/teammate-api-patterns.md for lifecycle patterns.' The Lead creates its own team (the orchestrator does NOT call TeamCreate — Claude Code API constraint: one team per leader).
     - **If `team_mode=task`:** Spawn yolo-lead as subagent via Task tool with compiled context (or full file list as fallback). Do not add any team mode context.
   - Display `◆ Spawning Lead agent...` -> `✓ Lead agent complete`.
6. **Multi-department planning (when `multi_dept=true` from resolve-departments.sh above):**
   Read `${CLAUDE_PLUGIN_ROOT}/references/cross-team-protocol.md` for workflow order.

   a. **Owner Context Gathering + Context Splitting (FIRST — before any department leads spawn):**
      **Replan gate:** Glob `{phase-dir}/{phase}-CONTEXT-*.md`. If ANY exist: AskUserQuestion "Existing department context found." Options: (1) "Reuse existing context (Recommended)" — skip to 6b. Display: `✓ Reusing existing department context ({N} files)`. (2) "Gather fresh context" — delete all, run questionnaire. Display: `◆ Refreshing department context...`

      Run Owner questionnaire per `references/multi-dept-protocol.md` Step 0a (2-3 adaptive rounds: vision, dept-specific, gaps). Keep asking until ZERO ambiguity. Split into `{phase-dir}/{phase}-CONTEXT-{backend,uiux,frontend}.md` — each contains ONLY that department's concerns (see multi-dept-protocol.md Context Delegation). Each file: **Vision** (shared overview), **Department Requirements** (filtered), **Constraints** (dept-relevant), **Integration Points** (abstract, no leaking).

      Display: `◆ Owner gathering project context...` → (questions) → `✓ Context gathered — split into {N} department briefs`

   b. **Resolve models for ALL active department Leads + Owner** (resolve-agent-model.sh pattern for each: lead, fe-lead if fe_active, ux-lead if ux_active, owner).

   c. **Compile context per department Lead:**
      `compile-context.sh {phase} {role} {phases_dir}` for each active lead (lead, fe-lead, ux-lead).

   d. **Follow `leads_to_spawn` dispatch order from resolve-departments.sh:**
      Parse `leads_to_spawn` — `|` separates waves, `,` separates parallel within a wave.

      **Context isolation (STRICT — NO CONTEXT BLEED):** Each lead receives ONLY its dept context file from 6a:
      - `yolo-lead`: `{phase}-CONTEXT-backend.md` only
      - `yolo-ux-lead`: `{phase}-CONTEXT-uiux.md` only
      - `yolo-fe-lead`: `{phase}-CONTEXT-frontend.md` + UX handoff artifacts only

      Each lead spawned with: resolved model (6b), compiled context (6c), phase dir, ROADMAP.md, REQUIREMENTS.md, dept context ONLY. Each Lead delegates Lead→Architect→Senior→Dev with narrowing context (see `references/cross-team-protocol.md` Context Isolation Rules).

      **Spawn strategy per wave (OBEY team_mode from pre-computed output):**

      **If `team_mode=teammate` (MANDATORY when resolved — DO NOT fall back to Task tool):**
      **IMPORTANT:** The orchestrator does NOT call TeamCreate directly. Each Lead creates its own team. This avoids the Claude Code API constraint: "a leader can only manage one team at a time." Each Lead is a separate subagent context and can independently lead one team.
      For each dept in the wave:
      1. Spawn dept Lead using Task tool (NOT TeamCreate — Lead creates own team)
      2. Include in Lead prompt: `team_mode=teammate. Create team yolo-{dept} via TeamCreate, then register specialists as teammates. See @references/teammate-api-patterns.md.`
      3. Lead calls TeamCreate: spawnTeam(name="yolo-{dept}", description="{Dept} engineering team for phase {N}: {phase-name}")
      4. Lead registers core specialists (architect, senior, dev) as teammates at creation
      5. Additional specialists on-demand: tester at step 6, qa + qa-code at step 9, security at step 10 (backend only)
      6. Full rosters: Backend 7 (incl security), Frontend 6, UI/UX 6
      7. Shutdown: Lead sends shutdown_request to all teammates on completion
      Parallel waves: spawn all Leads in one message (each creates its own team independently).

      **If `team_mode=task`:**
      Per wave: parallel agents spawn via multiple Task tool calls in one message; single agents spawn and wait. Include `team_mode=task` in every Lead's spawn context.

      Display per lead: `◆ Spawning {Dept} Lead ({model})...` -> `✓ {Dept} Lead complete`

   e. **Owner plan review (balanced/thorough effort only, when `owner_active=true`):**
      Spawn yolo-owner (model from 6b) with `owner_review` mode + all dept plan.jsonl files + reqs.jsonl + dept config.
      Display `◆ Spawning Owner for plan review...` -> `✓ Owner review complete`
6. **Validate output:** Verify plan.jsonl files exist with valid JSONL (each line parses with jq). Check header has p, n, t, w, mh fields. Check wave deps acyclic.
7. **Present:** Update STATE.md (phase position, plan count, status=Planned). Resolve model profile:

   ```bash
   MODEL_PROFILE=$(jq -r '.model_profile // "balanced"' .yolo-planning/config.json)
   ```

   Display Phase Banner with plan list, effort level, and model profile:

   ```
   Phase {N}: {name}
   Plans: {N}
     {NN-MM}: {title} (wave {W}, {N} tasks)
   Effort: {effort}
   Model Profile: {profile}
   ```

8. **Cautious gate (autonomy=cautious only):** STOP after planning. Ask "Plans ready. Execute Phase {N}?" Other levels: auto-chain.

### Mode: Execute

This mode delegates to protocol files. Before reading:

1. **Parse arguments:** Phase number (auto-detect if omitted), --effort, --skip-qa, --skip-security, --plan=NN.
2. **Run execute guards:**
   - Not initialized: STOP "YOLO is not set up yet. Run /yolo:init to get started."
   - No `*.plan.jsonl` files in phase dir: STOP "Phase {N} has no plans. Run `/yolo:go --plan {N}` first."
   - All plans have `*.summary.jsonl`: cautious/standard -> WARN + confirm; confident/pure-yolo -> warn + auto-continue.
3. **Compile context:** If `config_context_compiler=true`, compile context for each agent role as needed per the protocol steps. Include `.ctx-{role}.toon` paths in agent task descriptions.

4. **Fallback notice:** If `fallback_notice=true` from resolve-team-mode.sh, display: `[notice] Teammate API requested but unavailable. Using Task tool spawn instead.` Informational only.

5. **MANDATORY SPAWN STRATEGY GATE (read before ANY agent spawning):**

   Read `team_mode` from the pre-computed resolve-team-mode.sh output above. This is a HARD GATE — you MUST branch here and follow ONLY the matching path below. Do NOT default to Task tool when team_mode=teammate.

   - **If `team_mode=teammate`:** You MUST instruct department Leads to use the Teammate API. The orchestrator does NOT call TeamCreate directly — each Lead creates its own team (Claude Code API: one team per leader). Spawn Leads via Task tool. Include `team_mode=teammate` in every Lead's prompt so the Lead calls TeamCreate and registers specialists as teammates. Leads use SendMessage for intra-team communication. The Task tool (without team context) is ONLY used for shared-department agents that are explicitly Task-only: critic, scout, debugger. ALL other agents (architect, senior, dev, tester, qa, qa-code, security) MUST be spawned as teammates within department teams by their Lead. Display: `[team_mode=teammate] Using Teammate API for department orchestration.`

   - **If `team_mode=task`:** Use Task tool for ALL agent spawning (current default behavior). No Teammate API usage. Display nothing (this is the silent default).

   This gate applies to BOTH single-department and multi-department execution below. When team_mode=teammate in single-department mode: Lead creates one team (yolo-backend) and spawns all non-shared agents as teammates within it. When team_mode=teammate in multi-department mode: each Lead creates one team per active department (yolo-backend, yolo-frontend, yolo-uiux). The orchestrator (go.md) never calls TeamCreate directly.

6. **Escalation from Agents:**

   When an escalation reaches the top of the chain (Architect in single-dept, Owner in multi-dept), go.md intercepts and presents to the user:

   a. **Receive escalation context:** Architect/Owner returns structured escalation via Task result (task mode) or file-based artifact (teammate mode). The escalation contains: issue description, evidence array, recommendation, options array (2-3 concrete choices), severity.

   b. **Format for user:** Present via AskUserQuestion:
      ```
      Agent escalation requires your input:

      Blocker: {issue description}
      Evidence:
        - {evidence[0]}
        - {evidence[1]}
      Recommendation: {recommendation}

      Options:
      1. {options[0]} (recommended)
      2. {options[1]}
      3. {options[2]}
      ```

   c. **Wait for response:** AskUserQuestion blocks until user responds. No timeout on user response.

   d. **Package resolution:** Construct `escalation_resolution` schema:
      ```json
      {
        "type": "escalation_resolution",
        "original_escalation": "{escalation_id}",
        "decision": "{user's choice text}",
        "rationale": "{user's explanation if provided, otherwise 'User selected option N'}",
        "action_items": ["{derived from the selected option's implications}"],
        "resolved_by": "user"
      }
      ```

   e. **Return resolution:** Send escalation_resolution back to the escalating agent (Architect/Owner). In task mode: return as Task result. In teammate mode (cross-team): write as file artifact `.escalation-resolution-{dept}.json` in phase dir (go.md acts as Owner proxy per D1).

   f. **Update escalation state:** Update .execution-state.json escalation entry: set status to "resolved", resolved_at to current timestamp, resolution to decision text. Commit immediately: `chore(state): escalation resolved phase {N}`.

**Routing (based on `multi_dept` from resolve-departments.sh above):**

- **Single department (`multi_dept=false`):**
  Read `${CLAUDE_PLUGIN_ROOT}/references/execute-protocol.md` and follow its workflow (Critique → Research → Architecture → Planning → Design Review → Test Authoring RED → Implementation → Code Review → Documentation (optional) → QA → Security → Sign-off). See `references/company-hierarchy.md` for agent hierarchy. Pass `team_mode` to execute-protocol.md — it contains teammate-specific instructions at each step.

  **Phase 3 orchestration wiring:**

  - **Critique step (Step 1):** Replace direct Critic spawn with critique-loop.sh call:
    ```bash
    CRITIQUE_RESULT=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/critique-loop.sh \
      --phase-dir "{phase-dir}" \
      --config .yolo-planning/config.json \
      --role critic)
    ```
    Log confidence and rounds in status display: `✓ Critique complete (cf:{final_confidence}, rounds:{rounds_used})`. See execute-protocol.md Step 1 for full multi-round protocol.

  - **Documentation step (Step 8.5):** After code review, resolve documenter gate:
    ```bash
    GATE_RESULT=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-documenter-gate.sh \
      --config .yolo-planning/config.json \
      --defaults ${CLAUDE_PLUGIN_ROOT}/config/defaults.json)
    DOC_SPAWN=$(echo "$GATE_RESULT" | jq -r '.spawn')
    ```
    If `spawn=true`: spawn yolo-documenter. Non-blocking — proceed to QA immediately.

  - **Security step (Step 10):** Spawn yolo-security (BE-scoped). Single-dept mode always uses backend security reviewer only.

- **Multi-department (`multi_dept=true`):**
  Read `execute-protocol.md` + `multi-dept-protocol.md` + `cross-team-protocol.md`. Follow `multi-dept-protocol.md` dispatch flow. Each department runs its workflow with dept-prefixed agents (fe-*, ux-*).

  Workflow: Owner Context Gathering + Splitting (same reuse/refresh gate as Plan Mode 6a) → Owner Critique → UX workflow (if ux_active) → Handoff Gate → FE+BE parallel workflow → Integration QA → Security → Owner Sign-off.

  Context isolation: Lead gets dept CONTEXT + ROADMAP + REQUIREMENTS; Architect gets plan structure + dept CONTEXT; Senior gets architecture.toon + tasks; Dev gets enriched `spec` only. Escalation flows UP chain (Dev→Senior→Lead→Architect→Owner→User), never skipping levels.

  Resolve all dept agent models via `resolve-agent-model.sh` with dept-prefixed names. Compile context per dept via `compile-context.sh`.

  **Phase 3 multi-dept orchestration wiring:**

  - **Critique step (Step 1):** Each department runs its own confidence-gated critique loop with dept-specific role:
    ```bash
    # Backend
    bash ${CLAUDE_PLUGIN_ROOT}/scripts/critique-loop.sh --phase-dir "{phase-dir}" --config .yolo-planning/config.json --role critic
    # Frontend (if fe_active)
    bash ${CLAUDE_PLUGIN_ROOT}/scripts/critique-loop.sh --phase-dir "{phase-dir}" --config .yolo-planning/config.json --role fe-critic
    # UI/UX (if ux_active)
    bash ${CLAUDE_PLUGIN_ROOT}/scripts/critique-loop.sh --phase-dir "{phase-dir}" --config .yolo-planning/config.json --role ux-critic
    ```
    Display per-dept confidence: `✓ BE Critique (cf:88, 2 rounds) | FE Critique (cf:91, 1 round) | UX Critique (cf:85, 3 rounds)`

  - **Documentation step (Step 8.5):** Per-department documenter dispatch gated by resolve-documenter-gate.sh. Spawn yolo-documenter (BE), yolo-fe-documenter (FE), yolo-ux-documenter (UX) based on active departments. Non-blocking.

  - **Security step (Step 10):** Per-department security reviewers. Check departments config: for each active dept, spawn corresponding security reviewer:
    - Backend: yolo-security (BE-scoped)
    - Frontend: yolo-fe-security (FE-scoped)
    - UI/UX: yolo-ux-security (UX-scoped)
    Spawn in parallel when multiple depts active. FAIL from ANY dept = hard STOP.

  **Department Lead spawning (OBEY the spawn strategy gate above):**

  When `team_mode=teammate`: For each department, spawn the Lead via Task tool with `team_mode=teammate` in the prompt. The Lead creates its own team via TeamCreate (name: `yolo-{dept}`, description: `{Dept} engineering team for phase {N}: {phase-name}`). The orchestrator does NOT call TeamCreate directly (Claude Code API: one team per leader). The Lead registers core specialists (architect, senior, dev) as teammates at creation, then registers additional specialists on-demand: tester at step 6, documenter at step 8.5 (if gated), qa + qa-code at step 9, security at step 10. Leads coordinate with specialists via SendMessage. Gate satisfaction shifts from file polling to SendMessage-based status reporting. Shutdown: Lead sends shutdown_request to all teammates, waits for shutdown_response.

  When `team_mode=task`: Spawn department Leads as background Task subagents (`run_in_background=true`). File-based coordination via dept-gate.sh, dept-status.sh, and handoff sentinels. This is the current documented behavior.

### Mode: Trivial Shortcut

**Guard:** Only entered via Path 0 complexity-aware routing when suggested_path=trivial_shortcut and confidence >= config_trivial_threshold. Never entered directly by flags or natural language.

**Steps:**

1. Display: `Trivial task detected — fast path active`
2. Read route-trivial.sh output for `plan_path` and `steps_skipped`.
3. Resolve Senior model:
   ```
   SENIOR_MODEL=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-model.sh senior .yolo-planning/config.json ${CLAUDE_PLUGIN_ROOT}/config/model-profiles.json)
   ```
4. Spawn yolo-senior directly (skip Critic, Scout, Architect, Lead) with:
   - model: "${SENIOR_MODEL}"
   - Mode: "design_review"
   - User intent as context
   - Inline plan.jsonl from route-trivial.sh (`plan_path`)
   - Codebase mapping if available (`has_codebase_map`)
   - Display: `◆ Spawning Senior (${SENIOR_MODEL}) for trivial path...`
5. Senior enriches spec inline (single task, no formal plan decomposition).
6. Resolve Dev model:
   ```
   DEV_MODEL=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-model.sh dev .yolo-planning/config.json ${CLAUDE_PLUGIN_ROOT}/config/model-profiles.json)
   ```
7. Spawn Dev with enriched spec:
   - model: "${DEV_MODEL}"
   - Provide: enriched plan.jsonl (spec field)
   - Display: `◆ Spawning Dev (${DEV_MODEL}) for trivial path...`
8. Run post-task QA gate:
   ```bash
   result=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/qa-gate-post-task.sh \
     --phase-dir "{phase-dir}" --plan "{plan-id}" --task "T1" --scope)
   ```
9. Skip QA agents and security audit.
10. Commit and display completion:
    ```
    ✓ Trivial path complete — {1} task, {1} commit
    ```
    Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/suggest-next.sh execute`.

Owner-first principle still applies — go.md is the user proxy throughout.

### Mode: Medium Path

**Guard:** Only entered via Path 0 complexity-aware routing when suggested_path=medium_path and confidence >= config_medium_threshold. Never entered directly by flags or natural language.

**Steps:**

1. Display: `Medium complexity — streamlined path active`
2. Read route-medium.sh output for `steps_included`, `steps_skipped`, `has_architecture`.
3. Skip Critic (Step 1) and Scout (Step 2).
4. If `has_architecture=true` (architecture.toon exists in phase dir): use it. Otherwise skip architecture step.
5. Resolve Lead model:
   ```
   LEAD_MODEL=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-model.sh lead .yolo-planning/config.json ${CLAUDE_PLUGIN_ROOT}/config/model-profiles.json)
   ```
6. Spawn Lead for abbreviated planning:
   - model: "${LEAD_MODEL}"
   - Max tasks: `config_max_medium_tasks` from complexity_routing config (default 3)
   - Single plan only
   - Display: `◆ Spawning Lead (${LEAD_MODEL}) for medium path...`
7. Continue with existing execute-protocol.md steps:
   - Step 5: Design Review (Senior enriches specs)
   - Step 7: Implementation (Dev executes tasks)
   - Step 8: Code Review (Senior reviews code)
8. Run post-plan QA gate only (skip QA Lead and QA Code agents):
   ```bash
   result=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/qa-gate-post-plan.sh \
     --phase-dir "{phase-dir}" --plan "{plan-id}")
   ```
9. Skip security audit (Step 10).
10. Sign-off via Lead (Step 11).
    ```
    ✓ Medium path complete — {N} tasks, {N} commits
    ```
    Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/suggest-next.sh execute`.

This mode reuses execute-protocol.md steps 4-8 and 11 but skips steps 1-3, 6 (test authoring), 9, and 10. Owner-first principle applies. Test authoring is skipped for medium-path tasks because the abbreviated scope does not warrant a formal RED phase; the post-plan QA gate provides sufficient automated verification.

### Mode: Add Phase

**Guard:** Initialized. Requires phase name in $ARGUMENTS.
Missing name: STOP "Missing required input. Usage: `/yolo:go --add <phase-name>`"

**Steps:**

1. Resolve context: ACTIVE -> milestone-scoped paths, otherwise defaults.
2. Parse args: phase name (first non-flag arg), --goal (optional), slug (lowercase hyphenated).
3. Next number: highest in ROADMAP.md + 1, zero-padded.
4. Update ROADMAP.md: append phase list entry, append Phase Details section, add progress row.
5. Create dir: `mkdir -p {PHASES_DIR}/{NN}-{slug}/`
6. Present: Phase Banner with milestone, position, goal. Checklist for roadmap update + dir creation. Next Up: `/yolo:go --discuss` or `/yolo:go --plan`.

### Mode: Insert Phase

**Guard:** Initialized. Requires position + name.
Missing args: STOP "Missing required input. Usage: `/yolo:go --insert <position> <phase-name>`"
Invalid position (out of range 1 to max+1): STOP with valid range.
Inserting before completed phase: WARN + confirm.

**Steps:**

1. Resolve context: ACTIVE -> milestone-scoped paths, otherwise defaults.
2. Parse args: position (int), phase name, --goal (optional), slug (lowercase hyphenated).
3. Identify renumbering: all phases >= position shift up by 1.
4. Renumber dirs in REVERSE order: rename dir {NN}-{slug} -> {NN+1}-{slug}, rename internal plan.jsonl/summary.jsonl files, update `p` field in JSONL headers, update `d` (depends_on) references.
5. Update ROADMAP.md: insert new phase entry + details at position, renumber subsequent entries/headers/cross-refs, update progress table.
6. Create dir: `mkdir -p {PHASES_DIR}/{NN}-{slug}/`
7. Present: Phase Banner with renumber count, phase changes, file checklist, Next Up.

### Mode: Remove Phase

**Guard:** Initialized. Requires phase number.
Missing number: STOP "Missing required input. Usage: `/yolo:go --remove <phase-number>`"
Not found: STOP "Phase {N} does not exist. Run /yolo:status to see available phases."
Has work (plan.jsonl or summary.jsonl): STOP "Phase {N} has plan files. Delete plans from phase dir first."
Completed ([x] in roadmap): STOP "Phase {N} is complete and cannot be removed."

**Steps:**

1. Resolve context: ACTIVE -> milestone-scoped paths, otherwise defaults.
2. Parse args: extract phase number, validate, look up name/slug.
3. Confirm: display phase details, ask confirmation. Not confirmed -> STOP.
4. Remove dir: `rm -rf {PHASES_DIR}/{NN}-{slug}/`
5. Renumber FORWARD: for each phase > removed: rename dir {NN} -> {NN-1}, rename internal plan.jsonl/summary.jsonl files, update `p` field in JSONL headers, update `d` references.
6. Update ROADMAP.md: remove phase entry + details, renumber subsequent, update deps, update progress table.
7. Present: Phase Banner with renumber count, phase changes, file checklist, Next Up.

### Mode: Archive

**Guard:** Initialized, roadmap exists.
No roadmap: STOP "No milestones configured. Run `/yolo:go` to bootstrap."
No work (no `*.summary.jsonl` files): STOP "No completed plans found to archive. Run /yolo:go to execute a plan first."

**Pre-gate audit (unless --skip-audit or --force):**
Run 6-point audit matrix:

1. Roadmap completeness: every phase has real goal (not TBD/empty)
2. Phase planning: every phase has >= 1 `*.plan.jsonl`
3. Plan execution: every plan.jsonl has matching summary.jsonl
4. Execution status: every summary.jsonl has `"s":"complete"`
5. Verification: verification.jsonl exists + `"r":"PASS"`. Missing=WARN, failed=FAIL
6. Requirements coverage: req IDs in roadmap exist in REQUIREMENTS.md or reqs.jsonl
FAIL -> STOP with remediation suggestions. WARN -> proceed with warnings.

**Steps:**

1. Resolve context: ACTIVE -> milestone-scoped paths. No ACTIVE -> SLUG="default", root paths.
2. Parse args: --tag=vN.N.N (custom tag), --no-tag (skip), --force (skip audit).
3. Compute summary: from ROADMAP (phases), summary.jsonl files (tasks/commits/deviations via jq), REQUIREMENTS.md or reqs.jsonl (satisfied count).
4. Archive: `mkdir -p .yolo-planning/milestones/`. Move roadmap, state, phases to milestones/{SLUG}/. Write SHIPPED.md. Delete stale RESUME.md.
5. Git branch merge: if `milestone/{SLUG}` branch exists, merge --no-ff. Conflict -> abort, warn. No branch -> skip.
6. Git tag: unless --no-tag, `git tag -a {tag} -m "Shipped milestone: {name}"`. Default: `milestone/{SLUG}`.
7. Update ACTIVE: remaining milestones -> set ACTIVE to first. None -> remove ACTIVE.
8. Regenerate CLAUDE.md via bootstrap-claude.sh:
   ```
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/bootstrap/bootstrap-claude.sh CLAUDE.md "$PROJECT_NAME" "$CORE_VALUE" CLAUDE.md
   ```
   Script handles section replacement and user content preservation. After regeneration, update Active Context section via Edit tool: set **Work:** to next milestone name (if any) or "No active milestone", set **Last shipped:** to archived milestone name with metrics (phases, plans, tasks, commits, tests).
9. Present: Phase Banner with metrics (phases, tasks, commits, requirements, deviations), archive path, tag, branch status, memory status. Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/suggest-next.sh go`.

### Pure-YOLO Phase Loop

After Execute mode completes (autonomy=pure-yolo only): if more unbuilt phases exist, auto-continue to next phase (Plan + Execute). Loop until `next_phase_state=all_done` or error. Other autonomy levels: STOP after phase.

## Output Format

Per @${CLAUDE_PLUGIN_ROOT}/references/yolo-brand-essentials.toon -- double-line box, semantic symbols, no ANSI.

Per-mode: Bootstrap/Scope show banner + STOP. Discuss/Assumptions show list + Next Up. Plan/Execute show Phase Banner + metrics + Next Up. Phase mutations show Phase Banner + checklist + Next Up. Archive shows Phase Banner + full metrics + archive details + Next Up.

Symbols: Phase Banner (double-line box), ◆ running, ✓ complete, ✗ failed, ○ skipped. No ANSI color codes.

Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/suggest-next.sh go {result}` for Next Up suggestions.
