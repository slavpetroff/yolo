# Directory & File Structure

## Root Layout

```
yolo/
  .claude-plugin/           -- Plugin registration
    plugin.json             -- Plugin identity (name, version, author, license)
    marketplace.json        -- Distribution metadata (source URL, keywords, category)
  .claude/                  -- Claude Code project-level config
    CLAUDE.md               -- Plugin isolation rules
    agent-memory/           -- Persistent agent memory
      yolo-yolo-lead/MEMORY.md
      yolo-yolo-qa/MEMORY.md
  .github/                  -- GitHub templates
    ISSUE_TEMPLATE/
      bug_report.md
      feature_request.md
    PULL_REQUEST_TEMPLATE.md
  agents/                   -- Agent definitions (6 agents)
    yolo-architect.md
    yolo-debugger.md
    yolo-dev.md
    yolo-lead.md
    yolo-qa.md
    yolo-scout.md
  assets/                   -- Static assets
    abraham.jpeg
    statusline.png
  commands/                 -- Slash commands (20 commands)
    config.md
    debug.md
    fix.md
    help.md
    init.md
    map.md
    pause.md
    profile.md
    qa.md
    release.md
    research.md
    resume.md
    skills.md
    status.md
    teach.md
    todo.md
    uninstall.md
    update.md
    go.md
    whats-new.md
  config/                   -- Configuration presets
    defaults.json           -- Default config values
    model-profiles.json     -- Model presets (quality/balanced/budget)
    stack-mappings.json     -- Tech stack detection patterns and skill recommendations
  docs/                     -- Documentation
    migration-gsd-to-yolo.md
    yolo-1-0-99-vs-stock-teams-token-analysis.md
    yolo-1-10-2-vs-stock-agent-teams-token-analysis.md
    yolo-1-10-7-context-compiler-token-analysis.md
  hooks/
    hooks.json              -- Hook declarations (10 event types, 16 hook entries)
  references/               -- Protocol and reference documents
    discovery-protocol.md   -- Bootstrap/phase discovery question generation
    effort-profile-balanced.md
    effort-profile-fast.md
    effort-profile-thorough.md
    effort-profile-turbo.md
    execute-protocol.md     -- Execution mode protocol (extracted from go.md)
    handoff-schemas.md      -- Agent-to-agent communication schemas
    model-profiles.md       -- Model profile documentation
    phase-detection.md      -- Phase detection logic reference
    yolo-brand-essentials.md -- Unicode symbols, box drawing, progress bars
    verification-protocol.md -- Three-tier verification spec
  scripts/                  -- Shell scripts (35 scripts)
    agent-start.sh          -- SubagentStart hook: write .active-agent marker
    agent-stop.sh           -- SubagentStop hook: remove .active-agent marker
    bootstrap/              -- Bootstrap scripts (5 scripts)
      bootstrap-claude.sh   -- Generate/update CLAUDE.md
      bootstrap-project.sh  -- Generate PROJECT.md
      bootstrap-requirements.sh -- Generate REQUIREMENTS.md
      bootstrap-roadmap.sh  -- Generate ROADMAP.md with phase dirs
      bootstrap-state.sh    -- Generate STATE.md
    bump-version.sh         -- Version sync across all version files
    cache-nuke.sh           -- Force clear plugin cache
    compaction-instructions.sh -- PreCompact hook: write compaction marker
    compile-context.sh      -- Produce role-specific context files
    detect-stack.sh         -- Tech stack detection from project files
    file-guard.sh           -- PreToolUse: block undeclared file modifications
    generate-gsd-index.sh   -- GSD archive index generation
    hook-wrapper.sh         -- Universal hook wrapper (DXP-01)
    infer-gsd-summary.sh    -- Extract GSD work history summary
    infer-project-context.sh -- Infer project context from codebase mapping
    install-hooks.sh        -- Git pre-push hook installation
    map-staleness.sh        -- SessionStart: check codebase map freshness
    notification-log.sh     -- Notification hook handler
    phase-detect.sh         -- Pre-compute project state (key=value output)
    post-compact.sh         -- SessionStart(compact): post-compaction handler
    pre-push-hook.sh        -- Git pre-push hook script
    prompt-preflight.sh     -- UserPromptSubmit handler
    qa-gate.sh              -- TeammateIdle: structural completion checks
    resolve-agent-model.sh  -- Model resolution (profile + overrides)
    security-filter.sh      -- PreToolUse: block sensitive file access
    session-start.sh        -- SessionStart: state detection, update check, migrations
    session-stop.sh         -- Stop hook handler
    skill-hook-dispatch.sh  -- Skill-hook wiring dispatch
    state-updater.sh        -- PostToolUse: auto-update STATE.md, ROADMAP.md
    suggest-next.sh         -- Context-aware next action suggestions
    task-verify.sh          -- TaskCompleted hook handler
    validate-commit.sh      -- PostToolUse: commit message format validation
    validate-frontmatter.sh -- PostToolUse: YAML frontmatter validation
    validate-summary.sh     -- PostToolUse/SubagentStop: SUMMARY.md structure validation
    yolo-statusline.sh       -- 4-line status dashboard (context, usage, cost, model)
    verify-go.sh          -- Vibe command verification
  templates/                -- Document templates
    PLAN.md                 -- Plan artifact template (YAML + XML tasks)
    PROJECT.md              -- Project identity template
    REQUIREMENTS.md         -- Requirements catalog template
    ROADMAP.md              -- Roadmap template
    STATE.md                -- State tracking template
    SUMMARY.md              -- Execution summary template
    VERIFICATION.md         -- QA verification template
  CHANGELOG.md
  CLAUDE.md                 -- Project-level instructions for Claude Code
  CONTRIBUTING.md
  LICENSE                   -- MIT
  README.md
  VERSION                   -- Single-line version (1.10.18)
  marketplace.json          -- Root marketplace reference
  .gitignore
  .prettierignore
```

## File Counts

| Directory | Files | Description |
|-----------|-------|-------------|
| commands/ | 20 | Slash command definitions |
| agents/ | 6 | Agent behavior definitions |
| scripts/ | 30 | Shell scripts (non-bootstrap) |
| scripts/bootstrap/ | 5 | Bootstrap generation scripts |
| references/ | 11 | Protocol and reference documents |
| templates/ | 7 | Document templates |
| config/ | 3 | Configuration presets |
| hooks/ | 1 | Hook declarations |
| Total (core) | ~83 | Excluding docs, assets, github templates |

## Runtime Artifacts (not in git)

```
.yolo-planning/               -- Created by /yolo:init
  config.json
  PROJECT.md
  REQUIREMENTS.md
  ROADMAP.md
  STATE.md
  conventions.json
  ACTIVE                      -- Milestone slug (optional)
  .execution-state.json       -- Runtime execution tracking
  .cost-ledger.json           -- Per-agent cost tracking
  .hook-errors.log            -- Hook failure log
  .active-agent               -- Active agent marker
  .yolo-session                -- YOLO session marker
  .gsd-isolation              -- GSD isolation flag
  .compaction-marker          -- Compaction occurred marker
  phases/
    {NN}-{slug}/
      {NN}-{MM}-PLAN.md
      {NN}-{MM}-SUMMARY.md
      {NN}-VERIFICATION.md
      {NN}-CONTEXT.md
      .context-lead.md
      .context-dev.md
      .context-qa.md
  codebase/                   -- From /yolo:map
    STACK.md, DEPENDENCIES.md, ARCHITECTURE.md, STRUCTURE.md,
    CONVENTIONS.md, TESTING.md, CONCERNS.md, INDEX.md, PATTERNS.md,
    META.md
  milestones/                 -- Archived milestones
  gsd-archive/                -- Imported GSD data
```
