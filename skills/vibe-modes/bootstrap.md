# Mode: Bootstrap

**Guard:** `.yolo-planning/` exists but no PROJECT.md.

**Critical Rules (non-negotiable):**
- NEVER fabricate content. Only use what the user explicitly states.
- If answer doesn't match question: STOP, handle their request, let them re-run.
- No silent assumptions -- ask follow-ups for gaps.
- Phases come from the user, not you.

**Constraints:** Do NOT explore/scan codebase (that's /yolo:map). Use existing `.yolo-planning/codebase/` if `.yolo-planning/codebase/META.md` exists.

**Brownfield detection:** `git ls-files` or Glob check for existing code.

**Steps:**
- **B1: PROJECT.md** -- If $ARGUMENTS provided (excluding flags), use as description. Otherwise ask name + core purpose. Then call:
  ```
  "$HOME/.cargo/bin/yolo" bootstrap project .yolo-planning/PROJECT.md "$NAME" "$DESCRIPTION"
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
  - **B2.1: Domain Research (if not skip):** If DISCOVERY_DEPTH != skip:
    1. Extract domain from user's project description (the $NAME or $DESCRIPTION from B1)
    2. Research the {domain} domain using `WebFetch` or your internal knowledge. Focus on: Table Stakes, Common Pitfalls, Architecture Patterns, Competitor Landscape. Be concise (2-3 bullets per section).
    3. On success: Write your findings to `.yolo-planning/domain-research.md`. Extract brief summary (3-5 lines max). Display to user: "◆ Domain Research: {brief summary}\n\n✓ Research complete. Now let's explore your specific needs..."
    4. On failure: Log warning "⚠ Domain research failed, proceeding with general questions". Set RESEARCH_AVAILABLE=false, continue.
  - **B2.2: Discussion Engine** -- Read `${CLAUDE_PLUGIN_ROOT}/skills/discussion-engine/SKILL.md` and follow its protocol.
    - Context for the engine: "This is a new project. No phases yet." Use project description + domain research (if available) as input.
    - The engine handles calibration, gray area generation, exploration, and capture.
    - Output: `discovery.json` with answered/inferred/deferred arrays.
  - **If skip (yolo profile or discovery_questions=false):** Ask 2 minimal static questions via AskUserQuestion:
    1. "What are the must-have features for this project?" Options: ["Core functionality only", "A few essential features", "Comprehensive feature set", "Let me explain..."]
    2. "Who will use this?" Options: ["Just me", "Small team (2-10 people)", "Many users (100+)", "Let me explain..."]
    Record answers to `.yolo-planning/discovery.json` with `{"answered":[],"inferred":[],"deferred":[]}`.
  - **After discovery (all depths):** Call:
    ```
    "$HOME/.cargo/bin/yolo" bootstrap requirements .yolo-planning/REQUIREMENTS.md .yolo-planning/discovery.json .yolo-planning/domain-research.md
    ```

- **B3: ROADMAP.md** -- Suggest 3-5 phases from requirements. If `.yolo-planning/codebase/META.md` exists, read PATTERNS.md, ARCHITECTURE.md, and CONCERNS.md (whichever exist) from `.yolo-planning/codebase/`. Each phase: name, goal, mapped reqs, success criteria. Write phases JSON to temp file, then call:
  ```
  "$HOME/.cargo/bin/yolo" bootstrap roadmap .yolo-planning/ROADMAP.md "$PROJECT_NAME" /tmp/yolo-phases.json
  ```
  Script handles ROADMAP.md generation and phase directory creation.
- **B4: STATE.md** -- Extract project name, milestone name, and phase count from earlier steps. Call:
  ```
  "$HOME/.cargo/bin/yolo" bootstrap state .yolo-planning/STATE.md "$PROJECT_NAME" "$MILESTONE_NAME" "$PHASE_COUNT"
  ```
  Script handles today's date, Phase 1 status, empty decisions, and 0% progress.
- **B5: Brownfield summary** -- If BROWNFIELD=true AND no codebase/: count files by ext, check tests/CI/Docker/monorepo, add Codebase Profile to STATE.md.
- **B6: CLAUDE.md** -- Extract project name and core value from PROJECT.md. If root CLAUDE.md exists, pass it as EXISTING_PATH for section preservation. Call:
  ```
  "$HOME/.cargo/bin/yolo" bootstrap CLAUDE.md "$PROJECT_NAME" "$CORE_VALUE" [CLAUDE.md]
  ```
  Script handles: new file generation (heading + core value + YOLO sections), existing file preservation (replaces only YOLO-managed sections: Active Context, YOLO Rules, Installed Skills, Project Conventions, Commands, Plugin Isolation; preserves all other content). Omit the fourth argument if no existing CLAUDE.md. Max 200 lines.
- **B7: Planning commit boundary (conditional)** -- Run:
   ```bash
   "$HOME/.cargo/bin/yolo" planning-git commit-boundary "bootstrap project files" .yolo-planning/config.json
   ```
   Behavior: `planning_tracking=commit` commits `.yolo-planning/` + `CLAUDE.md` if changed. Other modes no-op.
- **B8: Transition** -- Display "Bootstrap complete. Transitioning to scoping..." Re-evaluate state, route to next match.
