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

Key variables from above (MANDATORY — read these before any mode):

- `multi_dept`: true = multi-department orchestration active, false = single backend lead only
- `workflow`: parallel | sequential | backend_only
- `leads_to_spawn`: pipe-separated waves, comma-separated parallel (e.g., `ux-lead|fe-lead,lead`)
- `spawn_order`: single | wave | sequential
- `owner_active`: true if Owner agent should be spawned for cross-dept review
- `fe_active` / `ux_active`: individual department flags
- `team_mode`: task = spawn agents via Task tool (default), teammate = spawn agents via Teammate API (experimental), auto = detect based on CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS env var (teammate if set + agent_teams=true, otherwise falls back to task)
- `fallback_notice`: true if team_mode was downgraded from teammate to task (display notice to user)

## Input Parsing

Three input paths, evaluated in order:

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
     - **If `team_mode=teammate`:** Call `Teammate` tool with `spawnTeam` operation (name: `yolo-backend`). Then spawn yolo-lead using `Task` tool with `team_name="yolo-backend"` and `name="backend-lead"`. Include in prompt: 'team_mode=teammate. Use Teammate API (SendMessage) to coordinate with specialists within your team. See @references/teammate-api-patterns.md for lifecycle patterns.'
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
      For each dept in the wave:
      1. Call `Teammate` tool: `spawnTeam` with name `yolo-{dept}`, description `{Dept} engineering team for phase {N}: {phase-name}`
      2. Spawn dept Lead using `Task` tool with `team_name="yolo-{dept}"` and `name="{dept}-lead"` params
      3. Include in Lead prompt: `team_mode=teammate. You are the lead of team yolo-{dept}. Use SendMessage to coordinate with specialists within your team. See @references/teammate-api-patterns.md.`
      4. Lead registers core specialists (architect, senior, dev) as teammates at creation
      5. Additional specialists on-demand: tester at step 6, qa + qa-code at step 9, security at step 10 (backend only)
      6. Full rosters: Backend 7 (incl security), Frontend 6, UI/UX 6
      7. Shutdown: Lead sends shutdown_request to all teammates on completion
      Parallel waves: create all department teams in one message (multiple Teammate + Task calls).

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

   - **If `team_mode=teammate`:** You MUST use the Teammate API for department Leads. Call `Teammate` tool with `spawnTeam` to create department teams. Use `Task` tool with `team_name` and `name` params to register teammates within those teams. Use `SendMessage` for intra-team communication. The Task tool (without team_name) is ONLY used for shared-department agents that are explicitly Task-only: critic, scout, debugger. ALL other agents (architect, senior, dev, tester, qa, qa-code, security) MUST be spawned as teammates within department teams. Display: `[team_mode=teammate] Using Teammate API for department orchestration.`

   - **If `team_mode=task`:** Use Task tool for ALL agent spawning (current default behavior). No Teammate API usage. Display nothing (this is the silent default).

   This gate applies to BOTH single-department and multi-department execution below. When team_mode=teammate in single-department mode: create one team (yolo-backend) and spawn all non-shared agents as teammates within it. When team_mode=teammate in multi-department mode: create one team per active department (yolo-backend, yolo-frontend, yolo-uiux).

**Routing (based on `multi_dept` from resolve-departments.sh above):**

- **Single department (`multi_dept=false`):**
  Read `${CLAUDE_PLUGIN_ROOT}/references/execute-protocol.md` and follow its 11-step company workflow (Critique → Research → Architecture → Planning → Design Review → Test Authoring RED → Implementation → Code Review → QA → Security → Sign-off). See `references/company-hierarchy.md` for agent hierarchy. Pass `team_mode` to execute-protocol.md — it contains teammate-specific instructions at each step.

- **Multi-department (`multi_dept=true`):**
  Read `execute-protocol.md` + `multi-dept-protocol.md` + `cross-team-protocol.md`. Follow `multi-dept-protocol.md` dispatch flow. Each department runs its 11-step with dept-prefixed agents (fe-*, ux-*).

  Workflow: Owner Context Gathering + Splitting (same reuse/refresh gate as Plan Mode 6a) → Owner Critique → UX 11-step (if ux_active) → Handoff Gate → FE+BE parallel 11-step → Integration QA → Security → Owner Sign-off.

  Context isolation: Lead gets dept CONTEXT + ROADMAP + REQUIREMENTS; Architect gets plan structure + dept CONTEXT; Senior gets architecture.toon + tasks; Dev gets enriched `spec` only. Escalation flows UP chain (Dev→Senior→Lead→Architect→Owner→User), never skipping levels.

  Resolve all dept agent models via `resolve-agent-model.sh` with dept-prefixed names. Compile context per dept via `compile-context.sh`.

  **Department Lead spawning (OBEY the spawn strategy gate above):**

  When `team_mode=teammate`: For each department, call `Teammate` tool with `spawnTeam` operation to create a team (name: `yolo-{dept}`, description: `{Dept} engineering team for phase {N}: {phase-name}`). Then use `Task` tool with `team_name="yolo-{dept}"` and `name="{dept}-lead"` to spawn the Lead as a teammate. The Lead registers core specialists (architect, senior, dev) as teammates at creation, then registers additional specialists on-demand: tester at step 6, qa + qa-code at step 9, security at step 10 (backend only). Leads coordinate with specialists via SendMessage. Gate satisfaction shifts from file polling to SendMessage-based status reporting. Shutdown: Lead sends shutdown_request to all teammates, waits for shutdown_response.

  When `team_mode=task`: Spawn department Leads as background Task subagents (`run_in_background=true`). File-based coordination via dept-gate.sh, dept-status.sh, and handoff sentinels. This is the current documented behavior.

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
