---
name: go
description: "The one command. Detects state, parses intent, routes to any lifecycle mode -- bootstrap, scope, plan, execute, discuss, archive, and more."
argument-hint: "[intent or flags] [--plan] [--execute] [--discuss] [--assumptions] [--scope] [--add] [--insert] [--remove] [--archive] [--yolo] [--effort=level] [--skip-qa] [--skip-audit] [--plan=NN] [N]"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, WebFetch
disable-model-invocation: true
---

# YOLO Go: $ARGUMENTS

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

Key variables from above (MANDATORY — read these before any mode):

- `multi_dept`: true = multi-department orchestration active, false = single backend lead only
- `workflow`: parallel | sequential | backend_only
- `leads_to_spawn`: pipe-separated waves, comma-separated parallel (e.g., `ux-lead|fe-lead,lead`)
- `spawn_order`: single | wave | sequential
- `owner_active`: true if Owner agent should be spawned for cross-dept review
- `fe_active` / `ux_active`: individual department flags

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

### Mode: Init Redirect

If `planning_dir_exists=false`: display "Run /yolo:init first to set up your project." STOP.

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

- **B1.5: Discovery Depth** -- Read `discovery_questions` and `active_profile` from config. Map profile to depth:

  | Profile | Depth | Questions |
  |---------|-------|-----------|
  | yolo | skip | 0 |
  | prototype | quick | 1-2 |
  | default | standard | 3-5 |
  | production | thorough | 5-8 |

  If `discovery_questions=false`: force depth=skip. Store DISCOVERY_DEPTH for B2.

- **B2: REQUIREMENTS.md (Discovery)** -- Behavior depends on DISCOVERY_DEPTH:
  - **If skip:** Ask 2 minimal static questions via AskUserQuestion: (1) "What are the must-have features?" (2) "Who will use this?" Create `.yolo-planning/discovery.json` with `{"answered":[],"inferred":[]}`.
  - **If quick/standard/thorough:** Read `${CLAUDE_PLUGIN_ROOT}/references/discovery-protocol.md`. Follow Bootstrap Discovery flow:
    1. Analyze user's description for domain, scale, users, complexity signals
    2. Round 1 -- Scenarios: Generate scenario questions per protocol. Present as AskUserQuestion with descriptive options. Count: quick=1, standard=2, thorough=3-4
    3. Round 2 -- Checklists: Based on Round 1 answers, generate targeted pick-many questions with `multiSelect: true`. Count: quick=1, standard=1-2, thorough=2-3
    4. Synthesize answers into `.yolo-planning/discovery.json` with `answered[]` and `inferred[]` (questions=friendly, requirements=precise)
  - **Wording rules (all depths):** No jargon. Plain language. Concrete situations. Cause and effect. Assume user is not a developer.
  - **After discovery (all depths):** Call:

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
- **B6: CLAUDE.md** -- Extract project name and core value from PROJECT.md. If root CLAUDE.md exists, pass it as EXISTING_PATH for section preservation. Call:

  ```
  bash ${CLAUDE_PLUGIN_ROOT}/scripts/bootstrap/bootstrap-claude.sh CLAUDE.md "$PROJECT_NAME" "$CORE_VALUE" [CLAUDE.md]
  ```

  Script handles: new file generation (heading + core value + YOLO sections), existing file preservation (replaces only YOLO-managed sections: Active Context, YOLO Rules, Key Decisions, Installed Skills, Project Conventions, Commands, Plugin Isolation; preserves all other content). Omit the fourth argument if no existing CLAUDE.md. Max 200 lines.
- **B7: Transition** -- Display "Bootstrap complete. Transitioning to scoping..." Re-evaluate state, route to next match.

### Mode: Scope

**Guard:** PROJECT.md exists but `phase_count=0`.

**Delegation:** Scope delegates to the Architect agent (yolo-architect) for phase decomposition. See `references/company-hierarchy.md` for hierarchy.

**Steps:**

1. Load context: PROJECT.md, REQUIREMENTS.md (or reqs.jsonl). If `.yolo-planning/codebase/` exists, note available mapping docs.
2. If $ARGUMENTS (excl. flags) provided, use as scope description. Else ask: "What do you want to build?" Show uncovered requirements as suggestions.
3. Resolve Architect model:

   ```bash
   ARCHITECT_MODEL=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-model.sh architect .yolo-planning/config.json ${CLAUDE_PLUGIN_ROOT}/config/model-profiles.json)
   ```

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
2. **Phase Discovery (if applicable):** Skip if already planned, phase dir has `{phase}-CONTEXT.md`, or DISCOVERY_DEPTH=skip. Otherwise: read `${CLAUDE_PLUGIN_ROOT}/references/discovery-protocol.md` Phase Discovery mode. Generate phase-scoped questions (quick=1, standard=1-2, thorough=2-3). Skip categories already in `discovery.json.answered[]`. Present via AskUserQuestion. Append to `discovery.json`. Write `{phase}-CONTEXT.md`.
3. **Context compilation:** If `config_context_compiler=true`, compile context for the appropriate leads (see step 5/6).
4. **Turbo shortcut:** If effort=turbo, skip Lead. Read phase reqs from ROADMAP.md, create single lightweight plan.jsonl inline (header + tasks, no spec field).
5. **Single-department planning (when `multi_dept=false` from resolve-departments.sh above):**
   - Compile context: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/compile-context.sh {phase} lead {phases_dir}`
   - Resolve Lead model:

     ```bash
     LEAD_MODEL=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-model.sh lead .yolo-planning/config.json ${CLAUDE_PLUGIN_ROOT}/config/model-profiles.json)
     if [ $? -ne 0 ]; then
       echo "$LEAD_MODEL" >&2
       exit 1
     fi
     ```

   - Spawn yolo-lead as subagent via Task tool with compiled context (or full file list as fallback).
   - **CRITICAL:** Add `model: "${LEAD_MODEL}"` parameter to the Task tool invocation.
   - Display `◆ Spawning Lead agent...` -> `✓ Lead agent complete`.
6. **Multi-department planning (when `multi_dept=true` from resolve-departments.sh above):**
   Read `${CLAUDE_PLUGIN_ROOT}/references/cross-team-protocol.md` for workflow order.

   a. **Owner Context Gathering + Context Splitting (FIRST — before any department leads spawn):**
      The Owner is the SOLE point of contact with the user. In multi-department mode, go.md acts as the Owner's proxy to gather ALL requirements before ANY department lead is spawned. NO other agent talks to the user — ONLY the Owner does.

      **Questionnaire** — ask via AskUserQuestion in 2-3 adaptive rounds. Keep asking until ALL context is gathered and NO ambiguity remains:

      **Round 1: Vision and scope** (always):
      - "What are you building? Describe the end goal in 1-2 sentences."
      - "Who will use this? (end users, admins, developers, etc.)"
      - "What are the must-have features vs nice-to-haves?"

      **Round 2: Department-specific** (adapt to active departments):
      - If `ux_active=true`: "Any design preferences? (minimal, bold, playful, corporate) Target devices? Accessibility requirements?"
      - If `fe_active=true`: "Frontend framework preference? (React, Vue, Svelte, vanilla) Any component library? SSR needed?"
      - Backend (always): "Data storage needs? Auth method? External APIs or services to integrate?"

      **Round 3: Gaps, features, and constraints** (if 2+ departments active):
      - "How should frontend and backend communicate? (REST, GraphQL, WebSocket)"
      - "Any hard constraints? (tech stack, hosting, budget, timeline)"
      - Suggest features the user may not have considered based on their vision. Ask: "Would you also want X, Y, or Z?"
      - Surface gaps: "You mentioned X but haven't specified Y — how should that work?"
      - "Anything else the team should know?"

      **Keep asking until satisfied.** If answers are vague, ask follow-ups. If there are contradictions, resolve them. The goal is ZERO ambiguity before any department starts.

      **Context Splitting (MANDATORY — NO CONTEXT BLEED):**
      After gathering ALL context, split into department-specific context files. Each file contains ONLY what that department needs:

      - `{phase-dir}/{phase}-CONTEXT-backend.md` — Backend concerns ONLY: data models, API design, auth, infrastructure, external services, performance requirements. NO UI/UX details. NO frontend framework choices.
      - `{phase-dir}/{phase}-CONTEXT-uiux.md` — UX concerns ONLY: design preferences, target users, accessibility needs, user flows, device targets, interaction patterns. NO backend implementation details. NO frontend framework choices.
      - `{phase-dir}/{phase}-CONTEXT-frontend.md` — Frontend concerns ONLY: framework choice, component architecture, state management, routing, SSR needs, responsive requirements. NO backend implementation details. NO raw design decisions (those come via UX handoff artifacts later).

      Each file structure: **Vision** (shared 1-2 line overview), **Department Requirements** (filtered to this dept only), **Constraints** (dept-relevant only), **Integration Points** (what this dept needs from others, stated abstractly without leaking other dept's implementation).

      Display: `◆ Owner gathering project context...` → (questions) → `✓ Context gathered — split into {N} department briefs`

   b. **Resolve models for ALL active department Leads + Owner:**

      ```bash
      # Backend Lead (always)
      LEAD_MODEL=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-model.sh lead .yolo-planning/config.json ${CLAUDE_PLUGIN_ROOT}/config/model-profiles.json)
      # Frontend Lead (if fe_active=true)
      FE_LEAD_MODEL=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-model.sh fe-lead .yolo-planning/config.json ${CLAUDE_PLUGIN_ROOT}/config/model-profiles.json)
      # UX Lead (if ux_active=true)
      UX_LEAD_MODEL=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-model.sh ux-lead .yolo-planning/config.json ${CLAUDE_PLUGIN_ROOT}/config/model-profiles.json)
      # Owner (always for multi-dept)
      OWNER_MODEL=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-model.sh owner .yolo-planning/config.json ${CLAUDE_PLUGIN_ROOT}/config/model-profiles.json)
      ```

   c. **Compile context per department Lead:**

      ```bash
      bash ${CLAUDE_PLUGIN_ROOT}/scripts/compile-context.sh {phase} lead {phases_dir}
      # If fe_active=true:
      bash ${CLAUDE_PLUGIN_ROOT}/scripts/compile-context.sh {phase} fe-lead {phases_dir}
      # If ux_active=true:
      bash ${CLAUDE_PLUGIN_ROOT}/scripts/compile-context.sh {phase} ux-lead {phases_dir}
      ```

   d. **Follow `leads_to_spawn` dispatch order from resolve-departments.sh:**
      Parse `leads_to_spawn` — `|` separates waves, `,` separates parallel agents within a wave.

      For each wave (separated by `|`):
      - If wave contains `,` (parallel agents): spawn ALL agents in that wave in PARALLEL using multiple Task tool calls in a single message. Wait for all to complete.
      - If wave is a single agent: spawn it and wait for completion.

      **Context isolation per lead (STRICT — NO CONTEXT BLEED):**
      Each lead receives ONLY their department's context file from step 6a. Do NOT pass other departments' context files or the master gathered notes:

      - `yolo-lead` (Backend): Pass `{phase}-CONTEXT-backend.md` — NEVER pass UX or FE context
      - `yolo-ux-lead` (UX): Pass `{phase}-CONTEXT-uiux.md` — NEVER pass BE or FE context
      - `yolo-fe-lead` (Frontend): Pass `{phase}-CONTEXT-frontend.md` + UX design handoff artifacts (after UX completes) — NEVER pass BE context

      For each lead, spawn `yolo-{lead-name}` with:
      - model: resolved model from step 6b
      - Compiled context from step 6c
      - Phase dir, ROADMAP.md, REQUIREMENTS.md
      - Department-specific context file ONLY (from step 6a)
      - **DO NOT pass the other departments' context files**

      Each Lead then delegates down their chain: Lead→Architect→Senior→Dev. At each level, context narrows further (see `references/cross-team-protocol.md` Context Isolation Rules). Dev receives ONLY the enriched `spec` field — no architecture, no CONTEXT, no ROADMAP.

      Display per lead: `◆ Spawning {Dept} Lead ({model})...` -> `✓ {Dept} Lead complete`

      **Example dispatch for `leads_to_spawn=ux-lead|fe-lead,lead`:**
      1. Spawn yolo-ux-lead with `{phase}-CONTEXT-uiux.md`. Wait.
         `◆ Spawning UX Lead...` -> `✓ UX Lead complete`
      2. Spawn yolo-fe-lead (with `{phase}-CONTEXT-frontend.md` + UX handoff) + yolo-lead (with `{phase}-CONTEXT-backend.md`) in PARALLEL. Wait for both.
         `◆ Spawning Frontend Lead + Backend Lead...` -> `✓ All Leads complete`

   e. **Owner plan review (balanced/thorough effort only, when `owner_active=true`):**
      - Spawn yolo-owner (model: "${OWNER_MODEL}") with `owner_review` mode.
      - Provide: all department plan.jsonl files, reqs.jsonl, department config, CONTEXT.md.
      - Owner reviews cross-department plan coherence and sets priorities.
      - Display `◆ Spawning Owner for plan review...` -> `✓ Owner review complete`
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
   - Not initialized: STOP "Run /yolo:init first."
   - No `*.plan.jsonl` files in phase dir: STOP "Phase {N} has no plans. Run `/yolo:go --plan {N}` first."
   - All plans have `*.summary.jsonl`: cautious/standard -> WARN + confirm; confident/pure-yolo -> warn + auto-continue.
3. **Compile context:** If `config_context_compiler=true`, compile context for each agent role as needed per the protocol steps. Include `.ctx-{role}.toon` paths in agent task descriptions.

**Routing (based on `multi_dept` from resolve-departments.sh above):**

- **Single department (`multi_dept=false`):**
  Read `${CLAUDE_PLUGIN_ROOT}/references/execute-protocol.md` and follow its 10-step company workflow (Critique → Architecture → Planning → Design Review → Test Authoring RED → Implementation → Code Review → QA → Security → Sign-off). See `references/company-hierarchy.md` for agent hierarchy.

- **Multi-department (`multi_dept=true`):**
  Read ALL THREE protocol files:
  1. `${CLAUDE_PLUGIN_ROOT}/references/execute-protocol.md` — the per-department 10-step workflow structure
  2. `${CLAUDE_PLUGIN_ROOT}/references/multi-dept-protocol.md` — department dispatch order, handoff gates, Owner review
  3. `${CLAUDE_PLUGIN_ROOT}/references/cross-team-protocol.md` — communication rules, workflow modes, conflict resolution

  Follow `multi-dept-protocol.md` dispatch flow — each department runs its own 10-step using department-prefixed agents (fe-*, ux-*). Workflow order from `workflow` variable:

  **Owner Context Gathering + Splitting** (if `{phase}-CONTEXT-backend.md` does NOT exist) → **Owner Critique Review** → UX 10-step (if ux_active) → Handoff Gate → FE+BE parallel 10-step → Integration QA → Security → **Owner Sign-off**.

  The Owner is the SOLE point of contact with the user. If department context files are missing, run the Owner questionnaire + context splitting from Plan Mode step 6a before any department execution begins. No department lead or agent talks to the user — only the Owner does.

  **Context isolation (STRICT):** Each department's 10-step execution receives ONLY its department context file. Within each department, context cascades DOWN the hierarchy with progressive scoping:
  - Lead receives: department CONTEXT + ROADMAP + REQUIREMENTS
  - Architect receives: Lead's plan structure + department CONTEXT (NOT other department contexts)
  - Senior receives: architecture.toon + plan.jsonl tasks (NOT full CONTEXT, NOT critique.jsonl directly)
  - Dev receives: Senior's enriched `spec` field ONLY (NOT architecture.toon, NOT CONTEXT files)
  - On escalation: flows UP the chain (Dev→Senior→Lead→Architect→Owner→User). Owner clarifies with user, then pushes corrected context back down through the SAME chain — never skipping levels.

  Resolve models for ALL active department agents via `resolve-agent-model.sh` with department-prefixed names (e.g., `fe-lead`, `ux-architect`, `owner`). Compile context per department via `compile-context.sh` with department-aware roles.

### Mode: Add Phase

**Guard:** Initialized. Requires phase name in $ARGUMENTS.
Missing name: STOP "Usage: `/yolo:go --add <phase-name>`"

**Steps:**

1. Resolve context: ACTIVE -> milestone-scoped paths, otherwise defaults.
2. Parse args: phase name (first non-flag arg), --goal (optional), slug (lowercase hyphenated).
3. Next number: highest in ROADMAP.md + 1, zero-padded.
4. Update ROADMAP.md: append phase list entry, append Phase Details section, add progress row.
5. Create dir: `mkdir -p {PHASES_DIR}/{NN}-{slug}/`
6. Present: Phase Banner with milestone, position, goal. Checklist for roadmap update + dir creation. Next Up: `/yolo:go --discuss` or `/yolo:go --plan`.

### Mode: Insert Phase

**Guard:** Initialized. Requires position + name.
Missing args: STOP "Usage: `/yolo:go --insert <position> <phase-name>`"
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
Missing number: STOP "Usage: `/yolo:go --remove <phase-number>`"
Not found: STOP "Phase {N} not found."
Has work (plan.jsonl or summary.jsonl): STOP "Phase {N} has artifacts. Remove plans first."
Completed ([x] in roadmap): STOP "Cannot remove completed Phase {N}."

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
No work (no `*.summary.jsonl` files): STOP "Nothing to ship."

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
8. Regenerate CLAUDE.md: update Active Context, remove shipped refs. Preserve non-YOLO content — only replace YOLO-managed sections, keep user's own sections intact.
9. Present: Phase Banner with metrics (phases, tasks, commits, requirements, deviations), archive path, tag, branch status, memory status. Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/suggest-next.sh go`.

### Pure-YOLO Phase Loop

After Execute mode completes (autonomy=pure-yolo only): if more unbuilt phases exist, auto-continue to next phase (Plan + Execute). Loop until `next_phase_state=all_done` or error. Other autonomy levels: STOP after phase.

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/yolo-brand-essentials.toon for all output.

Per-mode output:

- **Bootstrap:** project-defined banner + transition to scoping
- **Scope:** phases-created summary + STOP
- **Discuss:** ✓ for captured answers, Next Up Block
- **Assumptions:** numbered list, ✓ confirmed, ✗ corrected, ○ expanded, Next Up
- **Plan:** Phase Banner (double-line box), plan list with waves/tasks, Effort, Next Up
- **Execute:** Phase Banner, plan results (✓/✗), Metrics (plans, effort, deviations), QA result, "What happened" (NRW-02), Next Up
- **Add/Insert/Remove Phase:** Phase Banner, ✓ checklist, Next Up
- **Archive:** Phase Banner, Metrics (phases, tasks, commits, reqs, deviations), archive path, tag, branch, memory status, Next Up

Rules: Phase Banner (double-line box), ◆ running, ✓ complete, ✗ failed, ○ skipped, Metrics Block, Next Up Block, no ANSI color codes.

Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/suggest-next.sh go {result}` for Next Up suggestions.
