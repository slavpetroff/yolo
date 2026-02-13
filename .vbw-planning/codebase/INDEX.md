# Cross-Referenced Index

## Key Files by Function

### Entry Points

| File | Function | References |
|------|----------|------------|
| hooks/hooks.json | Hook registration (10 event types, 16 entries) | ARCHITECTURE.md#Layer-4, PATTERNS.md#P1 |
| commands/go.md | Primary command, smart router | ARCHITECTURE.md#Layer-2, CONCERNS.md#Large-Command-Files |
| commands/init.md | Project initialization (8 steps) | ARCHITECTURE.md#Layer-2, CONCERNS.md#Large-Command-Files |
| scripts/session-start.sh | Session bootstrap (state, updates, cache, migrations) | ARCHITECTURE.md#Layer-4, CONCERNS.md#Shell-Script-Complexity |

### State Management

| File | Function | References |
|------|----------|------------|
| scripts/phase-detect.sh | Pre-compute project state | PATTERNS.md#P6, ARCHITECTURE.md#Data-Flow |
| scripts/state-updater.sh | Auto-update STATE.md/ROADMAP.md on PLAN/SUMMARY writes | PATTERNS.md#P3, CONCERNS.md#State-File-Race-Conditions |
| scripts/compile-context.sh | Role-specific context compilation | ARCHITECTURE.md#Layer-6, PATTERNS.md#P8 |
| scripts/resolve-agent-model.sh | Model resolution (profile + overrides) | PATTERNS.md#P8, ARCHITECTURE.md#Layer-3 |

### Security & Guards

| File | Function | References |
|------|----------|------------|
| scripts/security-filter.sh | Block sensitive file access (fail-closed) | PATTERNS.md#P4, CONCERNS.md#Security-Model-Assumptions |
| scripts/file-guard.sh | Block undeclared file modifications (fail-open) | PATTERNS.md#P4, CONVENTIONS.md#Security |
| scripts/hook-wrapper.sh | Universal hook wrapper (DXP-01) | PATTERNS.md#P1, ARCHITECTURE.md#Layer-4 |

### Verification

| File | Function | References |
|------|----------|------------|
| scripts/validate-commit.sh | Commit message format validation | CONVENTIONS.md#Commit-Format, TESTING.md |
| scripts/validate-summary.sh | SUMMARY.md structure validation | TESTING.md#Continuous-Verification |
| scripts/qa-gate.sh | TeammateIdle structural checks | TESTING.md#Continuous-Verification, PATTERNS.md#P4 |
| references/verification-protocol.md | Three-tier verification spec | TESTING.md#On-Demand-Verification |

### Agent Definitions

| File | Role | Key Traits | References |
|------|------|------------|------------|
| agents/yolo-lead.md | Planning | Write-only, no Edit, 50 turns | ARCHITECTURE.md#Layer-3 |
| agents/yolo-dev.md | Execution | Full tools, 75 turns | ARCHITECTURE.md#Layer-3 |
| agents/yolo-qa.md | Verification | Read-only, no Write/Edit, 25 turns | ARCHITECTURE.md#Layer-3 |
| agents/yolo-scout.md | Research | Read-only, no Bash, 15 turns | ARCHITECTURE.md#Layer-3 |
| agents/yolo-debugger.md | Investigation | Full tools, 40 turns | ARCHITECTURE.md#Layer-3 |
| agents/yolo-architect.md | Scoping | No Edit/Bash/WebFetch, 30 turns | ARCHITECTURE.md#Layer-3 |

### Configuration

| File | Function | References |
|------|----------|------------|
| config/defaults.json | Default config values (18 settings) | ARCHITECTURE.md#Layer-5 |
| config/model-profiles.json | Model presets (quality/balanced/budget) | PATTERNS.md#P8, STACK.md |
| config/stack-mappings.json | Tech stack detection (13 frameworks, 3 testing, 5 services, 4 quality, 3 devops) | DEPENDENCIES.md |

### Bootstrap Pipeline

| File | Input | Output | References |
|------|-------|--------|------------|
| scripts/bootstrap/bootstrap-project.sh | name, description | PROJECT.md | PATTERNS.md#P11 |
| scripts/bootstrap/bootstrap-requirements.sh | discovery.json | REQUIREMENTS.md | PATTERNS.md#P11 |
| scripts/bootstrap/bootstrap-roadmap.sh | phases.json | ROADMAP.md + phase dirs | PATTERNS.md#P11 |
| scripts/bootstrap/bootstrap-state.sh | project/milestone/phase data | STATE.md | PATTERNS.md#P11 |
| scripts/bootstrap/bootstrap-claude.sh | project data + optional existing | CLAUDE.md | PATTERNS.md#P11 |

## Commands by Category

| Category | Commands | Count |
|----------|----------|-------|
| Lifecycle | init, vibe | 2 |
| Monitoring | status, qa | 2 |
| Quick Actions | fix, debug, todo | 3 |
| Session | pause, resume | 2 |
| Codebase | map, research | 2 |
| Config | config, profile, skills, teach, help, whats-new, update, uninstall, release | 9 |
| **Total** | | **20** |

## Hook Event Coverage

| Event | Scripts Triggered | Count |
|-------|-------------------|-------|
| PostToolUse (Write/Edit) | validate-summary, validate-frontmatter, skill-hook-dispatch, state-updater | 4 |
| PostToolUse (Bash) | validate-commit, skill-hook-dispatch | 2 |
| PreToolUse (Read/Glob/Grep/Write/Edit) | security-filter | 1 |
| PreToolUse (Write/Edit) | skill-hook-dispatch, file-guard | 2 |
| SessionStart | session-start, map-staleness, post-compact | 3 |
| SubagentStart | agent-start | 1 |
| SubagentStop | validate-summary, agent-stop | 2 |
| TeammateIdle | qa-gate | 1 |
| TaskCompleted | task-verify | 1 |
| PreCompact | compaction-instructions | 1 |
| Stop | session-stop | 1 |
| UserPromptSubmit | prompt-preflight | 1 |
| Notification | notification-log | 1 |

## Cross-Cutting Themes

### Graceful Degradation
hook-wrapper.sh (P1) -> all hooks exit 0 on failure -> hook-errors.log
Referenced in: ARCHITECTURE.md, PATTERNS.md, CONVENTIONS.md

### Configuration Cascade
defaults.json -> config.json -> per-command flags -> per-agent overrides
Referenced in: ARCHITECTURE.md, PATTERNS.md#P8, STACK.md

### State-Driven Routing
phase-detect.sh -> go.md mode selection -> suggest-next.sh
Referenced in: ARCHITECTURE.md#Data-Flow, PATTERNS.md#P6, PATTERNS.md#P7

### Security Layering
security-filter.sh (files) + file-guard.sh (plan scope) + GSD isolation (plugin boundary)
Referenced in: CONCERNS.md, PATTERNS.md#P4, PATTERNS.md#P12

### Effort-Gated Behavior
Effort level controls: QA tier, discovery depth, teammate communication, scout model, plan approval
Referenced in: PATTERNS.md#P13, ARCHITECTURE.md#Layer-3
