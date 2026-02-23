# Mode: Plan

**Guard:** Initialized, roadmap exists, phase exists.
**Phase auto-detection:** First phase without PLAN.md. All planned: STOP "All phases planned. Specify phase: `/yolo:vibe --plan N`"

**Steps:**
1. **Parse args:** Phase number (optional, auto-detected), --effort (optional, falls back to config).
2. **Phase context:** If `{phase-dir}/{phase}-CONTEXT.md` exists, include it in Lead agent context. If not, proceed without -- users who want context run `/yolo:discuss N` first.
3. **Research persistence (REQ-08):** If `v3_plan_research_persist=true` in config AND effort != turbo:
   - Check for `{phase-dir}/{phase}-RESEARCH.md`.
   - **If missing:** Research the phase goal, requirements, and relevant codebase patterns directly using your codebase search tools. Write your structured findings to `{phase-dir}/{phase}-RESEARCH.md`. Your findings should include sections: `## Findings`, `## Relevant Patterns`, `## Risks`, `## Recommendations`.
   - **If exists:** Include it in Lead's context for incremental refresh. Lead may update RESEARCH.md if new information emerges.
   - **On failure:** Log warning, continue planning without research. Do not block.
   - If `v3_plan_research_persist=false` or effort=turbo: skip entirely.
   - **Subagent isolation:** When research exceeds 3 queries or explores unfamiliar code areas, use the Task tool with an Explore subagent to protect the planning context window. Consume only the subagent's structured findings -- do not load full file contents into the orchestrator's context.
4. **Context compilation:** If `config_context_compiler=true`, run `yolo compile-context {phase} lead {phases_dir}`. Read the output file `.context-lead.md` content into variable LEAD_CONTEXT for injection into the Lead agent's Task description. The compiled context format uses 3 tiers: `--- TIER 1: SHARED BASE ---` (project-wide, byte-identical across all roles), `--- TIER 2: ROLE FAMILY ({family}) ---` (byte-identical within planning or execution families), and `--- TIER 3: VOLATILE TAIL (phase={N}) ---` for phase-specific content. The compile-context CLI produces a single `.context-{role}.md` file with all 3 tiers concatenated in order.
5. **Turbo shortcut:** If effort=turbo, skip Lead. Read phase reqs from ROADMAP.md, create single lightweight PLAN.md inline.
6. **Other efforts:**
   - Resolve Lead model:
     ```bash
     LEAD_MODEL=$("$HOME/.cargo/bin/yolo" resolve-model lead .yolo-planning/config.json ${CLAUDE_PLUGIN_ROOT}/config/model-profiles.json)
       LEAD_MAX_TURNS=$("$HOME/.cargo/bin/yolo" resolve-turns lead .yolo-planning/config.json "{effort}")
     if [ $? -ne 0 ]; then
       echo "$LEAD_MODEL" >&2
       exit 1
     fi
     ```
   - **Team creation:** Read prefer_teams config:
     ```bash
     PREFER_TEAMS=$(jq -r '.prefer_teams // "always"' .yolo-planning/config.json 2>/dev/null)
     ```
     Decision tree:
     - `prefer_teams='always'`: Create team even for Lead-only
     - `prefer_teams='when_parallel'`: No team created for Planning alone
     - `prefer_teams='auto'`: Same as when_parallel (Lead-only is low-risk)

     When team should be created (based on prefer_teams):
     - Create team via TeamCreate: `team_name="yolo-plan-{NN}"`, `description="Planning Phase {N}: {phase-name}"`
     - Spawn Lead with `team_name: "yolo-plan-{NN}"`, `name: "lead"`, `subagent_type: "yolo:yolo-lead"` parameters on the Task tool invocation.
     - **HARD GATE -- Shutdown before proceeding (NON-NEGOTIABLE):** After all team agents complete their work, you MUST shut down the team BEFORE validating output, presenting results, auto-chaining to Execute, or asking the user anything. This gate CANNOT be skipped, deferred, or optimized away -- even after compaction. Lingering agents burn API credits silently.
       1. Send `shutdown_request` to EVERY active teammate via SendMessage (Lead -- excluding yourself, the orchestrator)
       2. Wait for each `shutdown_response` (approved=true). If rejected, re-request (max 3 attempts per teammate -- then proceed).
       3. Call TeamDelete for team "yolo-plan-{NN}"
       4. Verify: after TeamDelete, there must be ZERO active teammates. If tmux panes still show agent labels, something went wrong -- do NOT proceed.
       5. Only THEN proceed to step 7
       **WHY THIS EXISTS:** Without this gate, each Plan invocation spawns a new Lead that lingers in tmux. After 2-3 phases, multiple @lea panes accumulate, each burning API credits doing nothing. This is the #1 user-reported cost issue.

     When team should NOT be created (Lead-only with when_parallel/auto):
     - Spawn yolo-lead as subagent via Task tool without team (single agent, no team overhead). Include `subagent_type: "yolo:yolo-lead"`.
   - Spawn yolo-lead as subagent via Task tool. The Task description MUST start with `{LEAD_CONTEXT}` content as the first block (prefix-first injection for cache-optimal context), followed by the planning instructions (phase goal, parallel dev guidance). If no compiled context, fall back to full file list. Include `subagent_type: "yolo:yolo-lead"`.
   - **CRITICAL:** Add `model: "${LEAD_MODEL}"`, `maxTurns: ${LEAD_MAX_TURNS}`, and `subagent_type: "yolo:yolo-lead"` parameters to the Task tool invocation.
   - **CRITICAL:** Include in the Lead prompt: "Plans will be executed by a team of parallel Dev agents -- one agent per plan. Maximize wave 1 plans (no deps) so agents start simultaneously. Ensure same-wave plans modify disjoint file sets to avoid merge conflicts."
   - Display `◆ Spawning Lead agent...` -> `✓ Lead agent complete`.
7. **Validate output:** Verify PLAN.md has valid frontmatter (phase, plan, title, wave, depends_on, must_haves) and tasks. Check wave deps acyclic.
8. **Present:** Update STATE.md (phase position, plan count, status=Planned). Resolve model profile:
   ```bash
   MODEL_PROFILE=$(jq -r '.model_profile // "quality"' .yolo-planning/config.json)
   ```
   Display Phase Banner with plan list, effort level, and model profile:
   ```
   Phase {N}: {name}
   Plans: {N}
     {plan}: {title} (wave {W}, {N} tasks)
   Effort: {effort}
   Model Profile: {profile}
   ```
9. **Planning commit boundary (conditional):**
   ```bash
   "$HOME/.cargo/bin/yolo" planning-git commit-boundary "plan phase {N}" .yolo-planning/config.json
   ```
   Behavior: `planning_tracking=commit` commits planning artifacts if changed. `auto_push=always` pushes when upstream exists.
10. **Pre-chain verification:** Before auto-chaining or presenting results, confirm the planning team was fully shut down (step 6 HARD GATE completed). If you skipped the gate or are unsure after compaction, send `shutdown_request` to any teammates that may still be active and call TeamDelete before continuing. NEVER enter Execute mode with a prior planning team still alive.
11. **Cautious gate (autonomy=cautious only):** STOP after planning. Ask "Plans ready. Execute Phase {N}?" Other levels: auto-chain.
