---
name: init
disable-model-invocation: true
description: Set up environment, scaffold .yolo-planning, detect project context, and bootstrap project-defining files.
argument-hint:
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# YOLO Init

## Context

Working directory: `!`pwd``

Existing state:
```
!`ls -la .yolo-planning 2>/dev/null || echo "No .yolo-planning directory"`
```
Project files:
```
!`ls package.json pyproject.toml Cargo.toml go.mod *.sln Gemfile build.gradle pom.xml 2>/dev/null || echo "No detected project files"`
```
Skills:
```
!`ls "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/" 2>/dev/null || echo "No global skills"`
```
```
!`ls .claude/skills/ 2>/dev/null || echo "No project skills"`
```

## Guard

1. **Already initialized:** If .yolo-planning/config.json exists, STOP: "YOLO is already initialized. Use /yolo:config to modify settings or /yolo:go to start building."
2. **jq required:** `command -v jq` via Bash. If missing, STOP: "YOLO requires jq. Install: macOS `brew install jq`, Linux `apt install jq`, Manual: https://jqlang.github.io/jq/download/ — then re-run /yolo:init." Do NOT proceed without jq.
3. **Brownfield detection:** Check for existing source files (stop at first match):
   - Git repo: `git ls-files --error-unmatch . 2>/dev/null | head -5` — any output = BROWNFIELD=true
   - No git: Glob `**/*.*` excluding `.yolo-planning/`, `.claude/`, `node_modules/`, `.git/` — any match = BROWNFIELD=true
   - All file types count (shell, config, markdown, C++, Rust, CSS, etc.)

## Steps

### Step 0: Environment setup (settings.json)

**CRITICAL: Complete ENTIRE step (including writing settings.json) BEFORE Step 1. Use AskUserQuestion for prompts. Wait for answers. Write settings.json. Only then proceed.**

**Resolve config directory:** Check env var `CLAUDE_CONFIG_DIR`. If set, use that as `CLAUDE_DIR`. Otherwise default to `~/.claude`. Use `CLAUDE_DIR` for all config paths in this command.

Read `CLAUDE_DIR/settings.json` (create `{}` if missing).

**0a. Agent Teams:** Check `env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` == `"1"`. Enabled: `✓ Agent Teams — enabled`. Not enabled: AskUserQuestion "Agent Teams not enabled. YOLO uses it for parallel builds. Enable?" Approved: set to `"1"`. Declined: `○ Skipped.`

**0b. Statusline:** Read `statusLine` (may be string or object with `command` field). If contains `yolo-statusline`: `✓ Statusline — installed`, skip to 0c. If non-empty other: mention replacement in prompt. If empty: prompt to install. AskUserQuestion: "Install YOLO status line? (phase progress, cost, duration)"
If approved, set `statusLine` to:
```json
{"type": "command", "command": "bash -c 'f=$(ls -1 \"${CLAUDE_CONFIG_DIR:-$HOME/.claude}\"/plugins/cache/yolo-marketplace/yolo/*/scripts/yolo-statusline.sh 2>/dev/null | sort -V | tail -1) && [ -f \"$f\" ] && exec bash \"$f\"'"}
```
Object format with `type`+`command` is **required** — plain string fails silently.
If declined: `○ Skipped. Run /yolo:config to install it later.`

**0c. Write settings.json** if changed (single write). Display: `Environment setup complete:` with `✓/○` for Agent Teams and Statusline (add "(restart to activate)" if newly installed).

### Step 0.5: GSD import (conditional)

**Timing rationale:** Detection happens after environment setup (Step 0) but before scaffold (Step 1) to ensure:
- settings.json writes complete before any directory operations
- .yolo-planning/gsd-archive/ is created before scaffold creates .yolo-planning/
- User sees GSD detection early in the init flow
- Index generation (if implemented) can run after scaffold completes

**Index structure**: See `docs/migration-gsd-to-yolo.md` ## INDEX.json Format for field descriptions and usage examples.

**Detection:** Check for .planning/ directory: `[ -d .planning ]`

- **NOT found:** skip silently to Step 1 (no display output)
- **Found:** proceed with import flow:
  1. Display: "◆ GSD project detected"
  2. AskUserQuestion: "GSD project detected. Import work history?\n\nThis will copy .planning/ to .yolo-planning/gsd-archive/ for reference.\nYour original .planning/ directory will remain untouched."
     - Options: "Import (Recommended)" / "Skip"
  3. If user declines:
     - Display: "○ GSD import skipped"
     - Proceed to Step 1
  4. If user approves:
     - Create directory: `mkdir -p .yolo-planning/gsd-archive`
     - Copy contents: `cp -r .planning/* .yolo-planning/gsd-archive/`
     - Display: "◆ Generating index..."
     - Run: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/generate-gsd-index.sh`
     - Display: "✓ GSD project archived to .yolo-planning/gsd-archive/ (indexed)"
     - Set GSD_IMPORTED=true flag for later steps
     - Proceed to Step 1

### Step 1: Scaffold directory

Read each template from `${CLAUDE_PLUGIN_ROOT}/templates/` and write to .yolo-planning/:

| Target | Source |
|--------|--------|
| .yolo-planning/PROJECT.md | ${CLAUDE_PLUGIN_ROOT}/templates/PROJECT.md |
| .yolo-planning/REQUIREMENTS.md | ${CLAUDE_PLUGIN_ROOT}/templates/REQUIREMENTS.md |
| .yolo-planning/ROADMAP.md | ${CLAUDE_PLUGIN_ROOT}/templates/ROADMAP.md |
| .yolo-planning/STATE.md | ${CLAUDE_PLUGIN_ROOT}/templates/STATE.md |
| .yolo-planning/config.json | ${CLAUDE_PLUGIN_ROOT}/config/defaults.json |

Create `.yolo-planning/phases/`. Ensure config.json includes `"agent_teams": true` and `"model_profile": "quality"`.

**Apply department selections (after Step 2f completes):**

After Step 2f, update the already-written config.json with the user's department choices via jq:

```bash
jq --argjson fe "$DEPT_FRONTEND" --argjson ux "$DEPT_UIUX" --arg wf "$DEPT_WORKFLOW" \
  '.departments.frontend = $fe | .departments.uiux = $ux | .department_workflow = $wf' \
  .yolo-planning/config.json > .yolo-planning/config.json.tmp && \
  mv .yolo-planning/config.json.tmp .yolo-planning/config.json
```

This ensures config.json reflects user choices before any downstream scripts read it.

### Step 1.3: Initialize artifact store

Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/db/init-db.sh --planning-dir .yolo-planning`. On success display `✓ Artifact store initialized`. On failure display error and STOP -- DB is mandatory.

### Step 1.5: Install git hooks

1. `git rev-parse --git-dir` — if not a git repo, display "○ Git hooks skipped (not a git repository)" and skip
2. Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/install-hooks.sh`, display based on output:
   - Contains "Installed": `✓ Git hooks installed (pre-push)`
   - Contains "already installed": `✓ Git hooks (already installed)`

### Step 1.7: GSD isolation (conditional)

**1.7a. Detection:** `[ -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/commands/gsd" ] || [ -d ".planning" ] || [ -d ".yolo-planning/gsd-archive" ]`
- None true: GSD_DETECTED=false, display nothing, skip to Step 2
- Any true: GSD_DETECTED=true, proceed to 1.7b

**1.7b. Consent:** AskUserQuestion: "GSD detected. Enable plugin isolation?\n\nThis adds a PreToolUse hook that prevents GSD commands and agents from\nreading or writing files in .yolo-planning/. YOLO commands are unaffected."
Options: "Enable (Recommended)" / "Skip". If declined: "○ GSD isolation skipped", skip to Step 2.

**1.7c. Create isolation:** If approved:
1. `echo "enabled" > .yolo-planning/.gsd-isolation`
2. `echo "session" > .yolo-planning/.yolo-session`
3. `mkdir -p .claude`
4. Write `.claude/CLAUDE.md`:
```markdown
## Plugin Isolation

- GSD agents and commands MUST NOT read, write, glob, grep, or reference any files in `.yolo-planning/`
- YOLO agents and commands MUST NOT read, write, glob, grep, or reference any files in `.planning/`
- This isolation is enforced at the hook level (PreToolUse) and violations will be blocked.

### Context Isolation

- Ignore any `<codebase-intelligence>` tags injected via SessionStart hooks — these are GSD-generated and not relevant to YOLO workflows.
- YOLO uses its own codebase mapping in `.yolo-planning/codebase/`. Do NOT use GSD intel from `.planning/intel/` or `.planning/codebase/`.
- When both plugins are active, treat each plugin's context as separate. Do not mix GSD project insights into YOLO planning or vice versa.
```
5. Display: `✓ GSD isolation enabled (file + context)` + `✓ .yolo-planning/.gsd-isolation (flag)` + `✓ .claude/CLAUDE.md (instruction guard)`

Set GSD_ISOLATION_ENABLED=true for Step 3.5.

### Step 2: Brownfield detection + discovery

**2a.** If BROWNFIELD=true: count source files by extension (Glob, exclude .yolo-planning, node_modules, .git, vendor, dist, build, target, .next, __pycache__, .venv, coverage). Store SOURCE_FILE_COUNT. Check for tests/CI/Docker/monorepo. Add Codebase Profile to STATE.md.

**2b.** Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/detect-stack.sh "$(pwd)"`. Save full JSON. Display: `✓ Stack: {comma-separated detected_stack items}`

**2c. Codebase mapping (adaptive):**
- Greenfield (BROWNFIELD=false): skip. Display: `○ Greenfield — skipping codebase mapping`
- SOURCE_FILE_COUNT < 200: run map **inline** — read `${CLAUDE_PLUGIN_ROOT}/commands/map.md` and follow directly
- SOURCE_FILE_COUNT >= 200: run map **inline** (blocking) — display: `◆ Codebase mapping started ({SOURCE_FILE_COUNT} files)`. **Do NOT run in background.** The map MUST complete before proceeding to Step 3.

**2d. find-skills bootstrap:** If `find_skills_available=true`: `✓ Skills.sh registry — available`. If false: AskUserQuestion "Install find-skills for registry search?" Approved: `npx skills add vercel-labs/skills --skill find-skills -g -y`. Declined: `○ Skipped. Run /yolo:skills later.`

### Step 2e: Department selection

**Timing:** After stack detection (Step 2b) and mapping (Step 2c), before convergence.

AskUserQuestion multiSelect: "Which departments should be active?" Options: **Backend** (always on, re-add if deselected), **Frontend** (UI components, client-side), **UI/UX** (design systems, accessibility). Store: DEPT_BACKEND=true (always), DEPT_FRONTEND, DEPT_UIUX.

If BROWNFIELD + STACK.md exists: pre-select Frontend if stack has React/Vue/Angular/Svelte/Next/CSS/Tailwind, pre-select UI/UX if stack has Figma/Storybook/design tokens. Display: `◆ Department suggestion based on detected stack`

### Step 2f: Department workflow (conditional)

**Only run this step if Frontend or UI/UX was enabled in Step 2e** (i.e., DEPT_FRONTEND=true OR DEPT_UIUX=true).

If only Backend is enabled, set DEPT_WORKFLOW="backend_only" and skip this step.

Use AskUserQuestion to ask the workflow mode:

"How should departments coordinate?"

Options:
- **"Parallel (Recommended)"** — description: "UI/UX designs first, then Frontend + Backend build in parallel. Fastest."
- **"Sequential"** — description: "UI/UX → Frontend → Backend, one at a time. Simpler but slower."

Store selection as DEPT_WORKFLOW="parallel"|"sequential".

Display: `✓ Departments: {comma-separated active} — workflow: {DEPT_WORKFLOW}`

### Step 3: Convergence — augment and search

**3a.** Verify mapping completed. Display `✓ Codebase mapped ({document-count} documents)`. If skipped (greenfield): proceed immediately.

**3b.** If `.yolo-planning/codebase/STACK.md` exists, read it and merge additional stack components into detected_stack[].

**3b2. Auto-detect conventions:** If `.yolo-planning/codebase/PATTERNS.md` exists:
- Read PATTERNS.md, ARCHITECTURE.md, STACK.md, CONCERNS.md
- Extract conventions per `${CLAUDE_PLUGIN_ROOT}/commands/teach.md` (Step R2)
- Write `.yolo-planning/conventions.json`. Display: `✓ {count} conventions auto-detected from codebase`

If greenfield: write `{"conventions": []}`. Display: `○ Conventions — none yet (add with /yolo:teach)`

**3c. Parallel registry search** (if find-skills available): run `npx skills find "<stack-item>"` for ALL detected_stack items **in parallel** (multiple concurrent Bash calls). Deduplicate against installed skills. If detected_stack empty, search by project type. Display results with `(registry)` tag.

**3d. Unified skill prompt:** Combine curated (from 2b) + registry (from 3c) results into single AskUserQuestion multiSelect. Tag `(curated)` or `(registry)`. Max 4 options + "Skip". Install selected: `npx skills add <skill> -g -y`.

**3e.** Write Skills section to STATE.md (SKIL-05 capability map). Protocol:
  1. **Discovery (SKIL-01):** Scan `CLAUDE_DIR/skills/` (global), `.claude/skills/` (project), `.claude/mcp.json` (mcp). Record name, scope, path per skill.
  2. **Stack detection (SKIL-02):** Read `${CLAUDE_PLUGIN_ROOT}/config/stack-mappings.json`. For each category, match `detect` patterns via Glob/file content. Collect `recommended_skills[]`.
  3. **find-skills bootstrap (SKIL-06):** Check `CLAUDE_DIR/skills/find-skills/` or `~/.agents/skills/find-skills/`. If missing + `skill_suggestions=true`: offer install (`npx skills add vercel-labs/skills --skill find-skills -g -y`).
  4. **Suggestions (SKIL-03/04):** Compare recommended vs installed. Tag each `(curated)` or `(registry)`. If `auto_install_skills=true`: auto-install. Else: display with install commands.
  5. **Write STATE.md section:** Format: `### Skills` / `**Installed:** {list or "None detected"}` / `**Suggested:** {list or "None"}` / `**Stack detected:** {comma-separated}` / `**Registry available:** yes/no`

### Step 3.5: Generate bootstrap CLAUDE.md

Generate initial CLAUDE.md with YOLO bootstrap sections using the central script.

**Brownfield handling:** If root `CLAUDE.md` exists, pass it as 4th arg for section preservation.

```
if [ -f CLAUDE.md ]; then
  bash ${CLAUDE_PLUGIN_ROOT}/scripts/bootstrap/bootstrap-claude.sh CLAUDE.md "$PROJECT_NAME" "$CORE_VALUE" CLAUDE.md --minimal
else
  bash ${CLAUDE_PLUGIN_ROOT}/scripts/bootstrap/bootstrap-claude.sh CLAUDE.md "$PROJECT_NAME" "$CORE_VALUE" --minimal
fi
```

The `--minimal` flag generates only init-appropriate sections (YOLO Rules, Project Conventions, Commands, Plugin Isolation) since no project context exists yet. Active Context, Key Decisions, Department Architecture, and Installed Skills are added later by `/yolo:go` bootstrap mode (B6) which calls bootstrap-claude.sh without `--minimal`.

Display `✓ CLAUDE.md (created)` or `✓ CLAUDE.md (YOLO sections merged with existing)`.

### Step 4: Present summary

Display Phase Banner then file checklist (✓ for each created file).

**GSD import status** (conditional):
- If GSD_IMPORTED=true: Display "✓ GSD project archived ({file count} files, indexed)" where file count = `find .yolo-planning/gsd-archive -type f | wc -l`, then display sub-bullet: "  • Index: .yolo-planning/gsd-archive/INDEX.json"
- If .planning exists but GSD_IMPORTED=false: Display "○ GSD import skipped"

Then show conditional lines for GSD isolation, statusline, codebase mapping, conventions, skills.

### Step 5: Scenario detection

Display transition message: `◆ Infrastructure complete. Defining project...`

Detect the initialization scenario based on flags set in earlier steps:

1. **GREENFIELD:** BROWNFIELD=false (set in Guard step). No existing codebase to infer from.
2. **GSD_MIGRATION:** `.yolo-planning/gsd-archive/` directory exists (created in Step 0.5). Has GSD work history to import.
3. **BROWNFIELD:** BROWNFIELD=true AND `.yolo-planning/codebase/` directory exists (created in Step 2c mapping). Has codebase context to infer from.
4. **HYBRID:** BROWNFIELD=true but `.yolo-planning/codebase/` does not exist. Edge case — should not occur after Step 2c, but handle gracefully by treating as GREENFIELD.

Check conditions in order (GSD_MIGRATION first since a GSD project may also be brownfield):

```
if [ -d .yolo-planning/gsd-archive ]; then SCENARIO=GSD_MIGRATION
elif [ "$BROWNFIELD" = "true" ] && [ -d .yolo-planning/codebase ]; then SCENARIO=BROWNFIELD
elif [ "$BROWNFIELD" = "true" ]; then SCENARIO=HYBRID
else SCENARIO=GREENFIELD
fi
```

Display the detected scenario:
- GREENFIELD: `○ Scenario: Greenfield — new project`
- BROWNFIELD: `◆ Scenario: Brownfield — existing codebase detected`
- GSD_MIGRATION: `◆ Scenario: GSD Migration — importing work history`
- HYBRID: `○ Scenario: Hybrid — treating as greenfield (no mapping)`

No user interaction in this step. Proceed immediately to Step 6.

### Step 6: Inference & confirmation

Run inference scripts based on the detected scenario, display results, and confirm with the user. Always show inferred data even if fields are null (REQ-03).

**6a. Greenfield branch** (SCENARIO=GREENFIELD or SCENARIO=HYBRID):
- Display: `○ Greenfield — no codebase context to infer`
- Set SKIP_INFERENCE=true
- Skip to Step 7 (discovery questions will be asked inline)

**Display format for inferred fields** (used in 6b and 6c): Show each field as `{field}: {value} (source: {source})`. Null fields show `(not detected)`. Always display every field.

**6b. Brownfield branch** (SCENARIO=BROWNFIELD):
Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/infer-project-context.sh .yolo-planning/codebase/ "$(pwd)"`, capture to `.yolo-planning/inference.json`. Display: Name, Tech stack (joined), Architecture, Purpose, Features (joined) with sources.

**6c. GSD Migration branch** (SCENARIO=GSD_MIGRATION):
Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/infer-gsd-summary.sh .yolo-planning/gsd-archive/`, capture to `.yolo-planning/gsd-inference.json`. If codebase/ exists, also run `infer-project-context.sh` and capture to `inference.json`. Display GSD fields: Latest milestone, Recent phases, Key decisions, Current work. If codebase inference ran, display those fields too.

**6d. Confirmation UX** (all non-greenfield): AskUserQuestion "Does this look right?" Options: "Yes, looks right" (proceed to Step 7), "Close, but needs adjustments" (enter 6e), "Define from scratch" (set SKIP_INFERENCE=true, proceed to Step 7).

**6e. Correction flow** (when user picks "Close, but needs adjustments"):

Display all fields as a numbered list. Use AskUserQuestion: "Which fields would you like to correct? (enter numbers, comma-separated)"

For each selected field, use AskUserQuestion to ask the user for the corrected value. Update the inference JSON with corrected values.

After all corrections, display updated summary and proceed to Step 7 with corrected data.

Write the final confirmed/corrected data to `.yolo-planning/inference.json` for Step 7 consumption.

### Step 7: Bootstrap execution

Generate all project-defining files using confirmed data from Step 6 or discovery questions. Display: `◆ Generating project files...`

**Bootstrap script argument formats:** bootstrap-project.sh: OUTPUT NAME DESC | bootstrap-requirements.sh: OUTPUT DISCOVERY_JSON | bootstrap-roadmap.sh: OUTPUT NAME PHASES_JSON | bootstrap-state.sh: OUTPUT NAME MILESTONE PHASE_COUNT | bootstrap-claude.sh: OUTPUT NAME VALUE [EXISTING_PATH]

**7a. Gather project data:**
If SKIP_INFERENCE=true: AskUserQuestion for (1) project name, (2) one-sentence description, (3) key requirements, (4) phases with names and goals. If SKIP_INFERENCE=false: read `inference.json` (NAME from name.value, DESC from purpose.value). If GSD: also read `gsd-inference.json`. AskUserQuestion for remaining gaps (pre-fill from inferred features/phases).

**For each bootstrap script below:** run via Bash, display `✓ {filename}` on success.

| Step | Output | Script | Key args |
|------|--------|--------|----------|
| 7b | PROJECT.md | bootstrap-project.sh | .yolo-planning/PROJECT.md "$NAME" "$DESCRIPTION" |
| 7c | REQUIREMENTS.md | bootstrap-requirements.sh | .yolo-planning/REQUIREMENTS.md .yolo-planning/discovery.json |
| 7d | ROADMAP.md | bootstrap-roadmap.sh | .yolo-planning/ROADMAP.md "$NAME" .yolo-planning/phases.json |
| 7e | STATE.md | bootstrap-state.sh | .yolo-planning/STATE.md "$NAME" "$MILESTONE_NAME" "$PHASE_COUNT" |
| 7f | CLAUDE.md | bootstrap-claude.sh | CLAUDE.md "$NAME" "$DESCRIPTION" ["CLAUDE.md"] |

**7c prep:** Create `discovery.json` with `{"answered": [...], "inferred": [...]}` from user answers + inference features.
**7d prep:** Create `phases.json` as `[{"name", "goal", "requirements[]", "success_criteria[]"}]` from user phases.
**7e prep:** MILESTONE_NAME from NAME or GSD inference. PHASE_COUNT from phases.json length.
**7f note:** Pass existing CLAUDE.md as 4th arg to preserve non-YOLO content. Omit if no existing file.

**7g. Cleanup:** Remove temporary `discovery.json`, `phases.json`, `inference.json`, `gsd-inference.json` (intermediate artifacts, not project state).

### Step 8: Completion summary

Display a Phase Banner (double-line box per @${CLAUDE_PLUGIN_ROOT}/references/yolo-brand-essentials.toon) with the title "YOLO Initialization Complete".

```
╔══════════════════════════════════════╗
║   YOLO Initialization Complete        ║
╚══════════════════════════════════════╝
```

**File checklist:** Display all created/updated files:
- `✓ .yolo-planning/PROJECT.md`
- `✓ .yolo-planning/REQUIREMENTS.md`
- `✓ .yolo-planning/ROADMAP.md`
- `✓ .yolo-planning/STATE.md`
- `✓ CLAUDE.md`
- `✓ .yolo-planning/config.json`
- `✓ .yolo-planning/yolo.db (artifact store)`
- If GSD_IMPORTED=true: `✓ GSD project archived`
- If BROWNFIELD=true: `✓ Codebase mapped`

**Next steps:**
```
➜ Next: Run /yolo:go to start planning your first milestone
  Or:   Run /yolo:status to review project state
```

## Output Format

Per @${CLAUDE_PLUGIN_ROOT}/references/yolo-brand-essentials.toon -- double-line box, ✓/○ symbols, Next Up, no ANSI.
