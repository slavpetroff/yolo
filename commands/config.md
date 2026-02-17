---
name: config
disable-model-invocation: true
description: View and modify YOLO configuration including effort profile, verification tier, and skill-hook wiring.
argument-hint: [setting value]
allowed-tools: Read, Write, Edit, Bash, Glob
---

# YOLO Config $ARGUMENTS

## Context

Config:
```
!`cat .yolo-planning/config.json 2>/dev/null || echo "No config found -- run /yolo:init first"`
```

## Guard

If no .yolo-planning/ dir: STOP "YOLO is not set up yet. Run /yolo:init to get started." (check `.yolo-planning/config.json`)

## Behavior

### No arguments: Interactive configuration

**Step 1:** Display current settings in single-line box table (setting, value, description) + skill-hook mappings.

After the settings table, display Model Profile section. Resolve model for each of 6 agents (lead, dev, qa, scout, debugger, architect) via `resolve-agent-model.sh`. For each, check `model_overrides.{agent}` in config.json -- if non-empty, append asterisk to display. Show as:
```
Model Profile: $PROFILE
  Lead: $L | Dev: $D | QA: $Q | Scout: $S | Debugger: $DB | Architect: $A
```

**Step 2:** AskUserQuestion with up to 6 commonly changed settings (mark current values):
- Effort: thorough | balanced | fast | turbo
- Autonomy: cautious | standard | confident | pure-yolo
- Verification: quick | standard | deep
- Max tasks per plan: 3 | 5 | 7
- Model Profile
- Departments

**Step 2.5:** If "Model Profile" was selected, AskUserQuestion with 2 options:
- Use preset profile (quality/balanced/budget)
- Configure each agent individually (6 questions)

Store selection in variable `PROFILE_METHOD`.

**Branching:**
- If `PROFILE_METHOD = "Use preset profile"`: AskUserQuestion with 3 options (quality | balanced | budget). Apply selected profile using model profile switching logic (lines 88-130).
- If `PROFILE_METHOD = "Configure each agent individually"`: Proceed to individual agent configuration flow (Round 1 below).

**Individual Configuration - Round 1 (4 agents):**

**Cost utility** (used in individual config, profile switching, and cost display):
```bash
get_model_cost() { case "$1" in opus) echo 100 ;; sonnet) echo 20 ;; haiku) echo 2 ;; *) echo 0 ;; esac; }
```
Cost weights: opus=100, sonnet=20, haiku=2. Total = sum of get_model_cost for all 6 agents.

Resolve current models for all 6 agents (lead, dev, qa, scout, debugger, architect) via `resolve-agent-model.sh`. Calculate OLD_COST before changes.

AskUserQuestion with 4 questions:
- Lead model (current: $CURRENT_LEAD): opus | sonnet | haiku
- Dev model (current: $CURRENT_DEV): opus | sonnet | haiku
- QA model (current: $CURRENT_QA): opus | sonnet | haiku
- Scout model (current: $CURRENT_SCOUT): opus | sonnet | haiku

Store selections in variables `LEAD_MODEL`, `DEV_MODEL`, `QA_MODEL`, `SCOUT_MODEL`.

**Individual Configuration - Round 2 (2 agents):**

AskUserQuestion with 2 questions (current models already resolved above):
- Debugger model (current: $CURRENT_DEBUGGER): opus | sonnet | haiku
- Architect model (current: $CURRENT_ARCHITECT): opus | sonnet | haiku

Store selections in variables `DEBUGGER_MODEL`, `ARCHITECT_MODEL`.

**Apply Individual Overrides:**

Ensure model_overrides object exists:
```bash
if ! jq -e '.model_overrides' .yolo-planning/config.json >/dev/null 2>&1; then
  jq '.model_overrides = {}' .yolo-planning/config.json > .yolo-planning/config.json.tmp && mv .yolo-planning/config.json.tmp .yolo-planning/config.json
fi
```

Apply each override — for each AGENT in (lead, dev, qa, scout, debugger, architect):
```bash
jq ".model_overrides.$AGENT = \"$MODEL\"" .yolo-planning/config.json > .yolo-planning/config.json.tmp && mv .yolo-planning/config.json.tmp .yolo-planning/config.json
echo "✓ Model override: $AGENT ➜ $MODEL"
```

**Cost Estimate Display:**
Calculate NEW_COST using get_model_cost (defined above) for all 6 selected models. DIFF = (NEW-OLD)*100/OLD. Display: `Before: ~${OLD_DOLLARS} estimated (~{profile})`, `After: ~${NEW_DOLLARS} estimated ({diff}% change)`.

**Step 2.6:** If "Departments" was selected in Step 2, show current department state and allow toggling.

Read current department state:
```bash
IFS='|' read -r DEPT_BE DEPT_FE DEPT_UX DEPT_WF <<< "$(jq -r '[
  (.departments.backend // true),
  (.departments.frontend // false),
  (.departments.uiux // false),
  (.department_workflow // "backend_only")
] | join("|")' .yolo-planning/config.json)"
```

Display current state:
```
Current departments:
  Backend:  ✓ (always on)
  Frontend: {✓ or ○}
  UI/UX:    {✓ or ○}
  Workflow:  {DEPT_WF}
```

Use AskUserQuestion multiSelect: "Toggle departments (Backend is always on):"
- **"Frontend"** — description: "Currently: {enabled|disabled}. UI components, client-side logic."
- **"UI/UX"** — description: "Currently: {enabled|disabled}. Design systems, wireframes, accessibility."

Toggle the selected departments (if Frontend was enabled and user selects it, disable it; if disabled, enable it).

If the result has 2+ departments active (Frontend or UI/UX enabled) AND current workflow is "backend_only", ask workflow:

AskUserQuestion: "Multiple departments enabled. Choose workflow:"
- **"Parallel (Recommended)"** — description: "UI/UX first, then Frontend + Backend in parallel."
- **"Sequential"** — description: "UI/UX → Frontend → Backend, one at a time."

If the result has only Backend active, set workflow to "backend_only" automatically.

Apply all changes via jq:
```bash
jq --argjson fe "$NEW_FE" --argjson ux "$NEW_UX" --arg wf "$NEW_WF" \
  '.departments.frontend = $fe | .departments.uiux = $ux | .department_workflow = $wf' \
  .yolo-planning/config.json > .yolo-planning/config.json.tmp && \
  mv .yolo-planning/config.json.tmp .yolo-planning/config.json
```

Display: `✓ Departments: {comma-separated active} — workflow: {NEW_WF}`

**Step 3:** Apply changes to config.json. Display ✓ per changed setting with ➜. No changes: "✓ No changes made."

**Step 4: Profile drift detection** — if effort/autonomy/verification_tier changed:
- Compare against active profile's expected values
- If mismatch: AskUserQuestion "Settings no longer match '{profile}'. Save as new profile?" → "Save" (route to /yolo:profile save) or "No" (set active_profile to "custom")
- Skip if no profile-tracked settings changed or already "custom"

Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/suggest-next.sh config` and display.

### With arguments: `<setting> <value>`

Validate setting + value. Update config.json. Display ✓ with ➜.

### Skill-hook wiring: `skill_hook <skill> <event> <matcher>`

- `config skill_hook lint-fix PostToolUse Write|Edit`
- `config skill_hook test-runner PostToolUse Bash`
- `config skill_hook remove <skill>`

Stored in config.json `skill_hooks`:
```json
{"skill_hooks": {"lint-fix": {"event": "PostToolUse", "matcher": "Write|Edit"}}}
```

### Model profile switching: `model_profile <profile>`

Validate profile in model-profiles.json (`jq -e ".$PROFILE"`). Invalid: `⚠ Unknown profile. Valid: quality, balanced, budget`.

Calculate OLD_COST and NEW_COST using get_model_cost (cost utility above) by counting opus/sonnet/haiku agents per profile. Display: `Switching from $OLD to $NEW (~{diff}% cost reduction/increase per phase)`.

Update config.json:
```bash
jq ".model_profile = \"$PROFILE\"" .yolo-planning/config.json > .yolo-planning/config.json.tmp && mv .yolo-planning/config.json.tmp .yolo-planning/config.json
```
Display: `✓ Model profile ➜ $PROFILE`

### Per-agent override: `model_override <agent> <model>`

Validate AGENT in (lead|dev|qa|scout|debugger|architect), MODEL in (opus|sonnet|haiku). Invalid: display `⚠` with valid values.

Get current model via `resolve-agent-model.sh`. Display: `Set $AGENT model override: $MODEL (was: $OLD)`.

Ensure model_overrides exists (same init pattern as individual config). Apply:
```bash
jq ".model_overrides.$AGENT = \"$MODEL\"" .yolo-planning/config.json > .yolo-planning/config.json.tmp && mv .yolo-planning/config.json.tmp .yolo-planning/config.json
```
Display: `✓ Model override: $AGENT ➜ $MODEL`

## Settings Reference

| Setting | Type | Values | Default |
|---------|------|--------|---------|
| effort | string | thorough/balanced/fast/turbo | balanced |
| autonomy | string | cautious/standard/confident/pure-yolo | standard |
| auto_commit | boolean | true/false | true |
| verification_tier | string | quick/standard/deep | standard |
| skill_suggestions | boolean | true/false | true |
| auto_install_skills | boolean | true/false | false |
| discovery_questions | boolean | true/false | true |
| visual_format | string | unicode/ascii | unicode |
| max_tasks_per_plan | number | 1-7 | 5 |
| agent_teams | boolean | true/false | true |
| team_mode | string | auto/task/teammate | auto |
| branch_per_milestone | boolean | true/false | false |
| plain_summary | boolean | true/false | true |
| active_profile | string | profile name or "custom" | default |
| custom_profiles | object | user-defined profiles | {} |

## Output Format

Per @${CLAUDE_PLUGIN_ROOT}/references/yolo-brand-essentials.toon -- single-line box, ✓/⚠/➜ symbols, no ANSI.
