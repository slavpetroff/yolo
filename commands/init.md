---
description: Initialize a new VBW project with .vbw-planning directory, artifact templates, and project definition.
argument-hint: [project-description]
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# VBW Init: $ARGUMENTS

## Context

Working directory: `!`pwd``

Existing state:
```
!`ls -la .vbw-planning 2>/dev/null || echo "No .vbw-planning directory"`
```

Project files:
```
!`ls package.json pyproject.toml Cargo.toml go.mod *.sln Gemfile build.gradle pom.xml 2>/dev/null || echo "No detected project files"`
```

Installed skills:
```
!`ls ~/.claude/skills/ 2>/dev/null || echo "No global skills"`
```

```
!`ls .claude/skills/ 2>/dev/null || echo "No project skills"`
```

## Guard

1. **Already initialized:** If .vbw-planning/ contains PROJECT.md, STOP: "VBW is already initialized. Use /vbw:config to modify settings or delete .vbw-planning/ to re-initialize."
2. **Brownfield detection:** If project files AND source files (*.ts, *.js, *.py, *.go, *.rs, *.java, *.rb) exist, set BROWNFIELD=true.

## Steps

### Step 0: Agent Teams check

Check if Agent Teams is enabled:
```
!`cat ~/.claude/settings.json 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('env',{}).get('CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS','0'))" 2>/dev/null || echo "0"`
```

If the result is NOT `"1"`:

Display:
```
⚠ Agent Teams is not enabled

VBW uses Agent Teams for parallel builds (/vbw:build) and codebase mapping (/vbw:map).
Without it, these commands will fail.

Enable it now? This adds one line to ~/.claude/settings.json:
  "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
```

Ask the user for permission. If they approve:
1. Read `~/.claude/settings.json` (create `{}` if it doesn't exist)
2. Ensure the `env` key exists as an object
3. Set `env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` to `"1"`
4. Write the file back
5. Display "✓ Agent Teams enabled. Restart Claude Code for it to take effect."

If they decline: display "○ Skipped. You can enable it later in ~/.claude/settings.json" and continue.

### Step 1: Scaffold directory

Read each template from `${CLAUDE_PLUGIN_ROOT}/templates/` and write to .vbw-planning/:

| Target                        | Source                                            |
|-------------------------------|---------------------------------------------------|
| .vbw-planning/PROJECT.md      | ${CLAUDE_PLUGIN_ROOT}/templates/PROJECT.md        |
| .vbw-planning/REQUIREMENTS.md | ${CLAUDE_PLUGIN_ROOT}/templates/REQUIREMENTS.md   |
| .vbw-planning/ROADMAP.md      | ${CLAUDE_PLUGIN_ROOT}/templates/ROADMAP.md        |
| .vbw-planning/STATE.md        | ${CLAUDE_PLUGIN_ROOT}/templates/STATE.md          |
| .vbw-planning/config.json     | ${CLAUDE_PLUGIN_ROOT}/config/defaults.json        |

Create `.vbw-planning/phases/` directory.

Ensure config.json includes `"agent_teams": true`.

### Step 2: Fill PROJECT.md

If $ARGUMENTS provided, use as project description. Otherwise ask:
- "What is the name of your project?"
- "Describe your project's core purpose in 1-2 sentences."

Fill placeholders: {project-name}, {core-value}, {date}.

### Step 3: Gather requirements

Ask 3-5 focused questions:
1. Must-have features for first release?
2. Primary users/audience?
3. Technical constraints (language, framework, hosting)?
4. Integrations or external services?
5. What is out of scope?

Populate REQUIREMENTS.md with REQ-ID format, organized into v1/v2/out-of-scope.

### Step 4: Create roadmap

Suggest 3-5 phases based on requirements. Each phase: name, goal, mapped requirements, success criteria. Fill ROADMAP.md.

### Step 5: Initialize state

Update STATE.md: project name, Phase 1 position, today's date, empty decisions, 0% progress.

### Step 5.5: Brownfield codebase summary

If BROWNFIELD=true:
1. Count source files by extension (Glob)
2. Check for test files, CI/CD, Docker, monorepo indicators
3. Add Codebase Profile section to STATE.md

### Step 5.7: Skill discovery

Follow `${CLAUDE_PLUGIN_ROOT}/references/skill-discovery.md`:
1. Scan installed skills (global, project, MCP)
2. Detect stack via `${CLAUDE_PLUGIN_ROOT}/config/stack-mappings.json`
3. Suggest uninstalled skills (if skill_suggestions enabled in config)
4. Write Skills section to STATE.md

### Step 5.8: Generate CLAUDE.md

Follow `${CLAUDE_PLUGIN_ROOT}/references/memory-protocol.md`. Write CLAUDE.md at project root with:
- Project header (name, core value)
- Active Context (milestone, phase, next action)
- Key Decisions (empty)
- Installed Skills (from 5.7)
- Learned Patterns (empty)
- VBW Commands section (static)

Keep under 200 lines.

### Step 5.9: Statusline offer

Check if a statusline is already configured:
```
!`cat ~/.claude/settings.json 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('statusLine',''))" 2>/dev/null || echo ""`
```

If the result is empty (no statusline configured):

Display:
```
○ VBW includes a custom status line for Claude Code.
  It shows your phase, milestone, effort profile, branch, context usage,
  cost, duration, and line diff — updated after every response.

  Install it?
```

Ask the user for permission. If they approve:
1. Copy `${CLAUDE_PLUGIN_ROOT}/scripts/vbw-statusline.sh` to `~/.claude/vbw-statusline.sh`
2. Make it executable (`chmod +x`)
3. Read `~/.claude/settings.json` (create `{}` if it doesn't exist)
4. Set `statusLine` to `bash ~/.claude/vbw-statusline.sh`
5. Write the file back
6. Display "✓ Statusline installed. Restart Claude Code to activate."

If they decline: display "○ Skipped. Run /vbw:config to install it later." and continue.

If a statusline is already configured BUT contains `vbw-statusline` and the file `~/.claude/vbw-statusline.sh` does NOT exist: the setting is stale — proceed with the copy (steps 1-6 above) without asking.

If a statusline is already configured and does NOT contain `vbw-statusline`: skip silently (don't overwrite other plugins' statuslines).

If a statusline is already configured and `~/.claude/vbw-statusline.sh` exists: skip silently (already installed).

### Step 6: Present summary

```
╔══════════════════════════════════════════╗
║  VBW Project Initialized                 ║
║  {project-name}                          ║
╚══════════════════════════════════════════╝

  ✓ .vbw-planning/PROJECT.md
  ✓ .vbw-planning/REQUIREMENTS.md
  ✓ .vbw-planning/ROADMAP.md
  ✓ .vbw-planning/STATE.md
  ✓ .vbw-planning/config.json
  ✓ .vbw-planning/phases/
  ✓ CLAUDE.md
  {If statusline installed:}
  ✓ ~/.claude/vbw-statusline.sh

  {If skills discovered:}
  Skills:
    Installed: {count} ({names})
    Suggested: {count} ({names})
    Stack:     {detected}
```

If BROWNFIELD:
```
  ⚠ Existing codebase detected ({file-count} source files)

➜ Next Up
  /vbw:map -- Analyze your codebase (recommended)
  /vbw:plan 1 -- Skip mapping and plan directly
```

If greenfield:
```
➜ Next Up
  /vbw:plan 1 -- Plan your first phase
```

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand.md:
- Phase Banner (double-line box) for init completion
- File Checklist (✓ prefix) for created files
- ○ for pending items
- Next Up Block for navigation
- No ANSI color codes
