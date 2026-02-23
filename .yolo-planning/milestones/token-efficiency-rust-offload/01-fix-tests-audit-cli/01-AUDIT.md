# Audit: Rust CLI vs MD-Side Deterministic Operations

Phase: 01 | Plan: 02 | Date: 2026-02-23

## Part 1: Rust CLI Command Inventory (65 commands)

| # | Command | Args/Flags | Purpose |
|---|---------|-----------|---------|
| 1 | `report` | (none) | Generate ROI & telemetry dashboard from SQLite DB |
| 2 | `report-tokens` | (varies) | Token economics report |
| 3 | `update-state` | `<file_path>` | Update STATE.md from file |
| 4 | `statusline` | stdin JSON | Render status line for Claude Code statusLine |
| 5 | `hard-gate` | `<gate_type> <phase> <plan> <task> <contract_path>` | Execute pre/post-task hard gates (contract_compliance, protected_file, required_checks, commit_hygiene, artifact_persistence, verification_threshold) |
| 6 | `session-start` | (none) | Session initialization |
| 7 | `metrics-report` | `[phase_filter]` | Generate metrics report for phase |
| 8 | `token-baseline` | (varies) | Token baseline capture |
| 9 | `bootstrap` | subcommands: `project`, `requirements`, `roadmap`, `state`, or CLAUDE.md (default) | Generate project-defining files |
| 10 | `suggest-next` | `<context>` | Suggest next action based on current state |
| 11 | `list-todos` | `[priority_filter]` | List pending todos from STATE.md as JSON |
| 12 | `phase-detect` | (none) | Detect current phase state (next_phase, phase_count, etc.) |
| 13 | `detect-stack` | `<dir>` | Detect tech stack, installed skills, suggestions |
| 14 | `infer` | `<codebase_dir> <project_dir>` | Infer project context from codebase mapping |
| 15 | `planning-git` | subcommands: `commit-boundary`, `sync-ignore`, `push-after-phase` | Git operations for planning artifacts |
| 16 | `resolve-model` | `<role> <config_path> <profiles_path>` | Resolve model for agent role |
| 17 | `resolve-turns` | `<role> <config_path> <effort>` | Resolve max turns for agent role |
| 18 | `log-event` | `<event_type> <phase> [key=value...]` | Log event to event log |
| 19 | `collect-metrics` | `<metric_type> <phase> [key=value...]` | Collect execution metrics |
| 20 | `generate-contract` | `<plan_path>` | Generate contract sidecar JSON |
| 21 | `contract-revision` | (varies) | Revise contract |
| 22 | `assess-risk` | `<plan_path>` | Assess plan risk (low/medium/high) |
| 23 | `gate-policy` | `<effort> <risk> <autonomy>` | Resolve gate policy for plan |
| 24 | `smart-route` | (varies) | Smart routing for agent plans |
| 25 | `route-monorepo` | `<phase_dir>` | Detect monorepo package paths |
| 26 | `snapshot-resume` | `save|restore <phase> [args...]` | Save/restore execution snapshots |
| 27 | `persist-state` | `<source_state> <target_state> <project_name>` | Persist project-level state across milestones |
| 28 | `recover-state` | `<phase> [args...]` | Event-sourced state recovery |
| 29 | `rolling-summary` | `<phases_dir> <output_path>` | Compile rolling summary from SUMMARYs |
| 30 | `gsd-index` | (none) | Generate GSD archive index JSON |
| 31 | `incidents` | (varies) | Generate incidents report |
| 32 | `artifact` | `register <file> <event_id> <phase> <plan>` | Artifact registry operations |
| 33 | `gsd-summary` | `<archive_dir>` | Infer GSD summary from archive |
| 34 | `cache-context` | (varies) | Cache compiled context |
| 35 | `cache-nuke` | (none) | Nuclear cache wipe |
| 36 | `delta-files` | (varies) | Compute delta files between states |
| 37 | `map-staleness` | (varies) | Check codebase map staleness |
| 38 | `token-budget` | `<role> <context_path> [contract_path] [task_number]` | Enforce per-role token budgets |
| 39 | `lock` | `acquire|release <task_id> [files...]` | Lightweight file locking |
| 40 | `lease-lock` | `acquire|release|renew|check <task_id> [--ttl=N] [files...]` | Time-limited file locking |
| 41 | `two-phase-complete` | `<task_id> <phase> <plan> <contract_path> [evidence...]` | Two-phase task completion |
| 42 | `help-output` | `[plugin_root] [command_name]` | Generate help text from command frontmatter |
| 43 | `bump-version` | `[--verify]` | Bump patch version or verify sync |
| 44 | `doctor` | `scan|cleanup` | Scan/cleanup stale teams, orphans, PIDs |
| 45 | `auto-repair` | `<gate_type> <phase> <plan> <task> <contract_path>` | Auto-repair gate failures |
| 46 | `rollout-stage` / `rollout` | (varies) | Feature flag staged rollout |
| 47 | `verify` | (varies) | Run verification checks |
| 48 | `hook` | `<event-name>` + stdin JSON | Dispatch hook handler |
| 49 | `install-hooks` | (none) | Install git hooks (pre-push) |
| 50 | `migrate-config` | `<config_path> [defaults_path] [--print-added]` | Backfill missing config keys |
| 51 | `invalidate-tier-cache` | (none) | Invalidate tier context cache |
| 52 | `compress-context` | (varies) | Compress compiled context |
| 53 | `prune-completed` | `<milestone_dir>` | Strip PLAN.md from completed phases |
| 54 | `compile-context` | `<phase> <role> <phases_dir> [plan_path]` | Compile tiered context for agent |
| 55 | `install-mcp` | (varies) | Install YOLO Expert MCP server |
| 56 | `migrate-orphaned-state` | `<planning_dir>` | Migrate orphaned STATE.md |
| 57 | `clean-stale-teams` | (none) | Clean stale agent teams |
| 58 | `tmux-watchdog` | (none) | Check tmux session status |
| 59 | `verify-init-todo` | (varies) | Verify init todo completion |
| 60 | `verify-vibe` | (varies) | Verify vibe completion |
| 61 | `verify-claude-bootstrap` | (varies) | Verify CLAUDE.md bootstrap |
| 62 | `pre-push` | (varies) | Pre-push hook validation |
| 63 | `validate-plan` | `<plan_path> <phase_dir>` | Validate plan cross-phase deps |
| 64 | `review-plan` | `<plan_path> <phase_dir>` | Automated plan quality review |
| 65 | `check-regression` | `<phase_dir>` | Check test count regression |
| 66 | `commit-lint` | `<commit_range>` | Validate conventional commit format |
| 67 | `diff-against-plan` | `<summary_path>` | Compare git diff vs SUMMARY.md |
| 68 | `validate-requirements` | `<plan_path> <phase_dir>` | Validate must_haves have evidence |
| 69 | `verify-plan-completion` | `<summary_path> <plan_path>` | Cross-reference SUMMARY vs PLAN |

## Part 2: MD-Side Deterministic Operations Inventory

### Common Pattern: Plugin Root Resolution

Found in **18 command files** and **7 skill files**. Every file with a Context block contains:

```
echo ${CLAUDE_PLUGIN_ROOT:-$(ls -1d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/yolo-marketplace/yolo/* 2>/dev/null | (sort -V 2>/dev/null || sort -t. -k1,1n -k2,2n -k3,3n) | tail -1)}
```

**Deterministic:** Yes. Pure path resolution with version-sort fallback.
**Rust equivalent:** None.

### Common Pattern: Working Directory

Found in **17 command files**: `` `!`pwd`` ``

**Deterministic:** Yes. Equivalent to `std::env::current_dir()`.
**Rust equivalent:** Already available internally but not exposed as a CLI command.

### Per-File Deterministic Operations

#### commands/config.md

| Line(s) | Operation | Deterministic? |
|---------|-----------|---------------|
| 12 | Plugin root resolution | Yes |
| 16 | `cat .yolo-planning/config.json` | Yes |
| 30-38 | `yolo migrate-config --print-added` | Yes (Rust CLI) |
| 49 | `jq -r '.model_profile // "quality"' config.json` | Yes |
| 54-57 | `yolo resolve-model` x4 (lead, dev, debugger, architect) | Yes (Rust CLI) |
| 63-66 | `jq -r '.model_overrides.{role} // ""' config.json` x4 | Yes |
| 103-104 | `jq -r 'to_entries[] | select(.key | startswith("v3_")...)` | Yes |
| 128-148 | Cost calculation: `get_model_cost()` case/arithmetic | Yes |
| 131-136 | `yolo resolve-model` x4 again for OLD cost | Yes (Rust CLI) |
| 153-155 | `yolo resolve-model` x2 (lead, dev current) | Yes (Rust CLI) |
| 167-168 | `yolo resolve-model` x2 (debugger, architect current) | Yes (Rust CLI) |
| 181-198 | `jq` config manipulation x5 (model_overrides) | Yes |
| 205-224 | Cost diff arithmetic | Yes |
| 234 | `yolo suggest-next config` | Yes (Rust CLI) |
| 243-244 | `yolo planning-git sync-ignore` | Yes (Rust CLI) |
| 264-298 | Profile switching: `jq` validate + cost calc + update | Yes |

**Unique gaps:** Cost calculation (model cost weights + percentage diff), config key enumeration with v2_/v3_ prefix filter, model override batch read/write.

#### commands/debug.md

| Line(s) | Operation | Deterministic? |
|---------|-----------|---------------|
| 11 | Plugin root resolution | Yes |
| 15 | `git log --oneline -10` | Yes |
| 36 | `jq -r '.prefer_teams // "always"' config.json` | Yes |
| 50-53 | `yolo resolve-model debugger` + `yolo resolve-turns debugger` | Yes (Rust CLI) |
| 66-69 | Same resolve-model/turns for Path B | Yes (Rust CLI) |

#### commands/discuss.md

| Line(s) | Operation | Deterministic? |
|---------|-----------|---------------|
| 13 | Plugin root resolution | Yes |
| 17 | `yolo phase-detect` | Yes (Rust CLI) |

#### commands/doctor.md

| Line(s) | Operation | Deterministic? |
|---------|-----------|---------------|
| 11 | `pwd` | Yes |
| 12 | `cat VERSION` | Yes |
| 20 | `jq --version` | Yes |
| 27 | `yolo bump-version --verify` | Yes (Rust CLI) |
| 45 | `gh --version` | Yes |
| 49-50 | `echo -e "1.0.2\n1.0.10" | sort -V | tail -1` | Yes |
| 55-56 | `yolo doctor-cleanup scan` + line counting | Yes (Rust CLI) |

#### commands/fix.md

| Line(s) | Operation | Deterministic? |
|---------|-----------|---------------|
| 11 | Plugin root resolution | Yes |
| 26-27 | `yolo resolve-model dev` + `yolo resolve-turns dev` | Yes (Rust CLI) |
| 43 | `git log --oneline -1` | Yes |
| 52 | `yolo suggest-next fix` | Yes (Rust CLI) |

#### commands/help.md

| Line(s) | Operation | Deterministic? |
|---------|-----------|---------------|
| 12 | Plugin root resolution | Yes |
| 22 | `yolo help-output` | Yes (Rust CLI) |
| 42 | `yolo help-output ${CLAUDE_PLUGIN_ROOT} $ARGUMENTS` | Yes (Rust CLI) |

#### commands/init.md

| Line(s) | Operation | Deterministic? |
|---------|-----------|---------------|
| 16 | Plugin root resolution | Yes |
| 22 | `ls -la .yolo-planning` | Yes |
| 27 | `ls package.json pyproject.toml ...` (project files) | Yes |
| 33 | `ls skills/ dirs` | Yes |
| 45-46 | `git ls-files --error-unmatch . | head -5` (brownfield) | Yes |
| 165 | `jq` config write (planning_tracking + auto_push) | Yes |
| 171 | `yolo planning-git sync-ignore` | Yes (Rust CLI) |
| 177 | `git rev-parse --git-dir` | Yes |
| 178 | `yolo install-hooks` | Yes (Rust CLI) |
| 185 | `yolo install-mcp` | Yes (Rust CLI) |
| 129 | `yolo generate-gsd-index` | Yes (Rust CLI) |
| 215 | `yolo detect-stack "$(pwd)"` | Yes (Rust CLI) |
| 322 | `find .yolo-planning/gsd-archive -type f | wc -l` | Yes |
| 380 | `yolo infer .yolo-planning/codebase/ "$(pwd)"` | Yes (Rust CLI) |
| 397 | `yolo gsd-summary .yolo-planning/gsd-archive/` | Yes (Rust CLI) |
| 472-496 | `yolo bootstrap project/requirements/roadmap/state` | Yes (Rust CLI) |
| 502 | `yolo bootstrap` (CLAUDE.md) | Yes (Rust CLI) |
| 516 | `yolo planning-git commit-boundary` | Yes (Rust CLI) |

#### commands/list-todos.md

| Line(s) | Operation | Deterministic? |
|---------|-----------|---------------|
| 13 | Plugin root resolution | Yes |
| 14 | `cat .yolo-planning/ACTIVE` | Yes |
| 21 | `yolo list-todos [priority]` | Yes (Rust CLI) |
| 26-27 | `yolo suggest-next list-todos` | Yes (Rust CLI) |

#### commands/map.md

| Line(s) | Operation | Deterministic? |
|---------|-----------|---------------|
| 13 | Plugin root resolution | Yes |
| 14 | `ls .yolo-planning/codebase/` | Yes |
| 17 | `cat .yolo-planning/codebase/META.md` | Yes |
| 19 | `ls package.json ...` (project files) | Yes |
| 20 | `git rev-parse HEAD` | Yes |
| 21 | `echo $CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` | Yes |
| 78 | `yolo resolve-turns scout config effort` | Yes (Rust CLI) |

#### commands/pause.md

| Line(s) | Operation | Deterministic? |
|---------|-----------|---------------|
| 11 | `pwd` | Yes |
| 12 | `cat .yolo-planning/ACTIVE` | Yes |

#### commands/profile.md

| Line(s) | Operation | Deterministic? |
|---------|-----------|---------------|
| 14 | `cat .yolo-planning/config.json` | Yes |

#### commands/release.md

| Line(s) | Operation | Deterministic? |
|---------|-----------|---------------|
| 11 | `pwd` | Yes |
| 12 | `cat VERSION` | Yes |
| 16 | `git status --short` | Yes |
| 23 | `git status --porcelain` | Yes |
| 25 | `yolo bump-version --verify` | Yes (Rust CLI) |
| 31 | `git log --oneline --grep="chore: release" -1` | Yes |
| 36 | `ls commands/*.md | wc -l` (command count) | Yes |
| 62 | `yolo bump-version` | Yes (Rust CLI) |
| 75-78 | `git add/commit/tag/push` | Yes |
| 87 | `gh release create` | Yes (external tool) |

#### commands/research.md

| Line(s) | Operation | Deterministic? |
|---------|-----------|---------------|
| 11 | Plugin root resolution | Yes |
| 16 | `cat .yolo-planning/PROJECT.md` | Yes |
| 28 | `yolo resolve-model researcher` | Yes (Rust CLI) |

#### commands/resume.md

| Line(s) | Operation | Deterministic? |
|---------|-----------|---------------|
| 13 | Plugin root resolution | Yes |
| 14 | `cat .yolo-planning/ACTIVE` | Yes |
| 27 | `yolo suggest-next resume` | Yes (Rust CLI) |

**Unique gap:** Progress computation (counting PLANs vs SUMMARYs per phase, percentage calculation).

#### commands/skills.md

| Line(s) | Operation | Deterministic? |
|---------|-----------|---------------|
| 11 | `pwd` | Yes |
| 15 | `yolo detect-stack "$(pwd)"` | Yes (Rust CLI) |

#### commands/status.md

| Line(s) | Operation | Deterministic? |
|---------|-----------|---------------|
| 12 | Plugin root resolution | Yes |
| 16 | `head -40 .yolo-planning/STATE.md` | Yes |
| 22 | `head -50 .yolo-planning/ROADMAP.md` | Yes |
| 28 | `ls .yolo-planning/phases/` | Yes |
| 32 | `cat .yolo-planning/ACTIVE` | Yes |
| 51 | `.cost-ledger.json` read + jq aggregate | Yes |
| 97 | `yolo suggest-next status` | Yes (Rust CLI) |

**Unique gaps:** Progress bar rendering (PLANs vs SUMMARYs counting + percentage), velocity computation, cost ledger aggregation.

#### commands/teach.md

| Line(s) | Operation | Deterministic? |
|---------|-----------|---------------|
| 13 | Plugin root resolution | Yes |
| 18 | `ls .yolo-planning/codebase/INDEX.md` | Yes |
| 16 | `cat .yolo-planning/conventions.json` | Yes |

#### commands/todo.md

| Line(s) | Operation | Deterministic? |
|---------|-----------|---------------|
| 12 | Plugin root resolution | Yes |
| 14 | `cat .yolo-planning/ACTIVE` | Yes |
| 24 | `yolo persist-state` (conditional) | Yes (Rust CLI) |
| 25 | `yolo migrate-orphaned-state` (conditional) | Yes (Rust CLI) |

#### commands/uninstall.md

| Line(s) | Operation | Deterministic? |
|---------|-----------|---------------|
| 14 | `cat settings.json` | Yes |
| 15-16 | `ls -d .yolo-planning`, `ls CLAUDE.md` | Yes |

#### commands/update.md

| Line(s) | Operation | Deterministic? |
|---------|-----------|---------------|
| 12 | Plugin root resolution | Yes |
| 22-23 | `cat .../plugins/cache/.../VERSION | sort -V | tail -1` | Yes |
| 35 | `curl -sf --max-time 5 "https://raw.githubusercontent.com/..."` | Yes (network) |
| 43 | `yolo cache-nuke` | Yes (Rust CLI) |
| 55-61 | `claude plugin marketplace update/uninstall/install` | Yes (external) |
| 67-68 | `rm -rf "$CLAUDE_DIR/commands/yolo"` | Yes |
| 73-76 | `jq` settings.json statusline check + update | Yes |
| 82-83 | VERSION file read + version comparison | Yes |

#### commands/verify.md

| Line(s) | Operation | Deterministic? |
|---------|-----------|---------------|
| 12 | Plugin root resolution | Yes |
| 16 | `head -40 .yolo-planning/STATE.md` | Yes |
| 22 | `ls .yolo-planning/phases/` | Yes |
| 28 | `yolo phase-detect` | Yes (Rust CLI) |

#### commands/vibe.md

| Line(s) | Operation | Deterministic? |
|---------|-----------|---------------|
| 14 | Plugin root resolution | Yes |
| 18 | `yolo phase-detect` | Yes (Rust CLI) |
| 23 | `cat .yolo-planning/config.json` | Yes |

#### commands/whats-new.md

| Line(s) | Operation | Deterministic? |
|---------|-----------|---------------|
| 12 | Plugin root resolution | Yes |

### Skill Files

#### skills/execute-protocol/SKILL.md

| Line(s) | Operation | Deterministic? |
|---------|-----------|---------------|
| 17 | `git log --oneline -20` | Yes |
| 23-26 | `jq -r '.correlation_id'` + `uuidgen` | Yes |
| 53 | `yolo validate-plan` | Yes (Rust CLI) |
| 66 | `jq -r '.review_gate // "on_request"' config.json` | Yes |
| 79 | `jq -r '.review_max_cycles // 3' config.json` | Yes |
| 84-86 | `yolo review-plan` + `jq -r '.verdict'` | Yes (Rust CLI) |
| 108-112 | `jq` execution-state.json manipulation | Yes |
| 117 | `yolo log-event review_loop_start` | Yes (Rust CLI) |
| 121-123 | `yolo resolve-model architect` + `yolo resolve-turns architect` | Yes (Rust CLI) |
| 136-156 | Delta findings extraction via jq | Yes |
| 193-196 | `yolo review-plan` re-run | Yes (Rust CLI) |
| 201-206 | `jq` execution-state cycle tracking | Yes |
| 210-211 | `jq` high_count extraction + `yolo log-event` | Yes (Rust CLI) |
| 278 | `jq -r '.prefer_teams // "always"' config.json` | Yes |
| 349 | `yolo compile-context` | Yes (Rust CLI) |
| 386-388 | `yolo token-budget` | Yes (Rust CLI) |
| 417-420 | `yolo resolve-model dev` + `yolo resolve-turns dev` | Yes (Rust CLI) |
| 509-528 | `yolo hard-gate` x6 (pre/post-task/plan gates) | Yes (Rust CLI) |
| 511-524 | `yolo lease-lock` / `yolo lock-lite` acquire/release | Yes (Rust CLI) |
| 516 | `yolo auto-repair` | Yes (Rust CLI) |
| 544 | `yolo two-phase-complete` | Yes (Rust CLI) |
| 552 | `yolo artifact-registry register` | Yes (Rust CLI) |
| 589 | `jq -r '.qa_gate // "on_request"' config.json` | Yes |
| 604-630 | `yolo verify-plan-completion/commit-lint/diff-against-plan/validate-requirements/check-regression` | Yes (Rust CLI) |
| 636-637 | `jq -r '.qa_max_cycles // 3'` | Yes |
| 840 | `jq -r '.autonomy // "standard"' config.json` | Yes |
| 879 | `yolo metrics-report` | Yes (Rust CLI) |
| 891-901 | `yolo planning-git commit-boundary/push-after-phase` | Yes (Rust CLI) |

#### skills/execute-protocol/V3-EXTENSIONS.md

| Line(s) | Operation | Deterministic? |
|---------|-----------|---------------|
| 11 | `yolo recover-state` | Yes (Rust CLI) |
| 23 | `yolo snapshot-resume restore` | Yes (Rust CLI) |
| 42-43 | `yolo assess-plan-risk` + `grep -c '^### Task'` | Yes |
| 47-49 | `yolo collect-metrics smart_route` | Yes (Rust CLI) |
| 57 | `yolo route-monorepo` | Yes (Rust CLI) |
| 69-71 | `yolo assess-plan-risk` + `yolo resolve-gate-policy` | Yes (Rust CLI) |
| 82-87 | `yolo log-event` x6 event types | Yes (Rust CLI) |
| 100 | `yolo artifact-registry register` | Yes (Rust CLI) |
| 114 | `yolo snapshot-resume save` | Yes (Rust CLI) |
| 121-123 | `yolo collect-metrics` x3 instrumentation | Yes (Rust CLI) |
| 131-137 | `yolo generate-contract` + `yolo validate-contract` | Yes (Rust CLI) |
| 145-148 | `yolo lock-lite acquire/release` | Yes (Rust CLI) |
| 157-161 | `yolo lease-lock acquire/release/renew/check` | Yes (Rust CLI) |
| 172 | `yolo compile-rolling-summary` | Yes (Rust CLI) |
| 184 | `yolo log-event phase_end` | Yes (Rust CLI) |

#### skills/vibe-modes/plan.md

| Line(s) | Operation | Deterministic? |
|---------|-----------|---------------|
| 16 | `yolo compile-context` | Yes (Rust CLI) |
| 21-23 | `yolo resolve-model lead` + `yolo resolve-turns lead` | Yes (Rust CLI) |
| 30-31 | `jq -r '.prefer_teams // "always"' config.json` | Yes |
| 57-58 | `jq -r '.model_profile // "quality"' config.json` | Yes |
| 69-70 | `yolo planning-git commit-boundary` | Yes (Rust CLI) |

#### skills/vibe-modes/bootstrap.md

| Line(s) | Operation | Deterministic? |
|---------|-----------|---------------|
| 17-19 | `yolo bootstrap project` | Yes (Rust CLI) |
| 47-48 | `yolo bootstrap requirements` | Yes (Rust CLI) |
| 51-53 | `yolo bootstrap roadmap` | Yes (Rust CLI) |
| 56-58 | `yolo bootstrap state` | Yes (Rust CLI) |
| 62-64 | `yolo bootstrap` (CLAUDE.md) | Yes (Rust CLI) |
| 67-70 | `yolo planning-git commit-boundary` | Yes (Rust CLI) |

#### skills/vibe-modes/archive.md

| Line(s) | Operation | Deterministic? |
|---------|-----------|---------------|
| 31-33 | `yolo persist-state` | Yes (Rust CLI) |
| 37-38 | `yolo planning-git commit-boundary` | Yes (Rust CLI) |
| 41-43 | `yolo prune-completed` | Yes (Rust CLI) |
| 52-53 | `jq -r '.auto_push // "never"' config.json` | Yes |
| 58-73 | Version bump: `cat VERSION`, arithmetic, `yolo bump-version` | Yes |
| 84-88 | `git add/commit -m "chore: release v..."` | Yes |
| 92-94 | `git tag -a "v${NEW_VERSION}"` | Yes |
| 99-101 | `git push && git push --tags` | Yes |

#### skills/vibe-modes/assumptions.md

| Line(s) | Operation | Deterministic? |
|---------|-----------|---------------|
| 10 | `yolo suggest-next vibe` | Yes (Rust CLI) |

## Part 3: Gap Analysis

### Section A: Covered (MD operations with existing Rust CLI equivalent)

| Operation | Source MD Files | Rust CLI Command |
|-----------|----------------|-----------------|
| Phase detection | vibe.md, verify.md, discuss.md | `yolo phase-detect` |
| Model resolution | config.md, debug.md, fix.md, plan.md, execute SKILL.md | `yolo resolve-model` |
| Turn resolution | debug.md, fix.md, map.md, plan.md, execute SKILL.md | `yolo resolve-turns` |
| Stack detection | init.md, skills.md | `yolo detect-stack` |
| Config migration | config.md | `yolo migrate-config` |
| Plan validation | execute SKILL.md | `yolo validate-plan` |
| Plan review | execute SKILL.md | `yolo review-plan` |
| Regression check | execute SKILL.md | `yolo check-regression` |
| Commit lint | execute SKILL.md | `yolo commit-lint` |
| Diff against plan | execute SKILL.md | `yolo diff-against-plan` |
| Requirements validation | execute SKILL.md | `yolo validate-requirements` |
| Plan completion verify | execute SKILL.md | `yolo verify-plan-completion` |
| Version bump | release.md, archive.md | `yolo bump-version` |
| Help output | help.md | `yolo help-output` |
| Todo listing | list-todos.md | `yolo list-todos` |
| Git planning ops | init.md, config.md, plan.md, archive.md, execute SKILL.md | `yolo planning-git` |
| Bootstrap files | init.md, bootstrap.md | `yolo bootstrap (project/requirements/roadmap/state)` |
| Context compilation | plan.md, execute SKILL.md | `yolo compile-context` |
| Token budget | execute SKILL.md | `yolo token-budget` |
| Hard gates | execute SKILL.md | `yolo hard-gate` |
| Auto-repair | execute SKILL.md | `yolo auto-repair` |
| Lock operations | execute SKILL.md, V3-EXTENSIONS.md | `yolo lock-lite`, `yolo lease-lock` |
| Two-phase completion | execute SKILL.md | `yolo two-phase-complete` |
| Artifact registry | execute SKILL.md, V3-EXTENSIONS.md | `yolo artifact` |
| Contract generation | V3-EXTENSIONS.md | `yolo generate-contract` |
| Event logging | execute SKILL.md, V3-EXTENSIONS.md | `yolo log-event` |
| Metrics collection | V3-EXTENSIONS.md | `yolo collect-metrics` |
| Snapshot resume | V3-EXTENSIONS.md | `yolo snapshot-resume` |
| Rolling summary | V3-EXTENSIONS.md, archive.md | `yolo rolling-summary` |
| GSD index/summary | init.md | `yolo gsd-index`, `yolo gsd-summary` |
| State persistence | todo.md, archive.md | `yolo persist-state` |
| State recovery | V3-EXTENSIONS.md | `yolo recover-state` |
| Orphaned state migration | todo.md | `yolo migrate-orphaned-state` |
| Risk assessment | V3-EXTENSIONS.md | `yolo assess-risk` |
| Gate policy | V3-EXTENSIONS.md | `yolo gate-policy` |
| Smart routing | V3-EXTENSIONS.md | `yolo smart-route` |
| Monorepo routing | V3-EXTENSIONS.md | `yolo route-monorepo` |
| Suggest next | config.md, fix.md, list-todos.md, resume.md, status.md, vibe.md | `yolo suggest-next` |
| Metrics report | execute SKILL.md | `yolo metrics-report` |
| Session start | (hook) | `yolo session-start` |
| Doctor/cleanup | doctor.md | `yolo doctor` |
| Cache nuke | update.md | `yolo cache-nuke` |
| Prune completed | archive.md | `yolo prune-completed` |
| Project inference | init.md | `yolo infer` |

### Section B: Needs Enhancement (existing Rust commands needing new flags)

| Operation | Source MD File | Existing Command | Enhancement | Complexity |
|-----------|---------------|-----------------|-------------|-----------|
| Resolve model with cost weight | config.md:128-148 | `resolve-model` | `--with-cost` flag: return `{"model":"opus","cost_weight":100}` instead of bare model name. Eliminates 8 resolve-model calls + shell arithmetic per config display | S |
| Batch resolve all agent models | config.md:54-57, 131-136, 153-155 | `resolve-model` | `--all` flag: return JSON object with all agent models at once `{"lead":"opus","dev":"sonnet",...}`. Eliminates 4-8 sequential resolve-model calls | S |
| Phase-detect with suggest-route | vibe.md:18 | `phase-detect` | `--suggest-route` flag: include suggested mode (plan/execute/archive) in output. Eliminates MD-side state->mode matching | S |
| Detect-stack with brownfield | init.md:45-46 | `detect-stack` | `--brownfield` flag: include `"brownfield": true/false` in JSON output. Eliminates `git ls-files` shell pipe | S |
| Config read helper | config.md:49, debug.md:36, execute SKILL.md:278,589,840 | (none -- jq) | New flag on existing command or new `config-read` command to read single key with default: `yolo config-read prefer_teams always` -> "always". Eliminates jq dependency for simple reads | M |

### Section C: Needs New Command (no Rust equivalent)

| Operation | Source MD File(s) | Description | Suggested Command | Complexity |
|-----------|------------------|-------------|-------------------|-----------|
| Plugin root resolution | **18 command files**, **7 skill files** | Resolve `CLAUDE_PLUGIN_ROOT` with version-sort fallback. Most-called deterministic operation in the entire codebase | `yolo plugin-root` | S |
| Cost calculation | config.md:128-224, archive.md:58-73 | Model cost weights (opus=100, sonnet=20, haiku=2), batch cost, percentage diff. Used in profile switching + config display + archive release | `yolo cost-estimate` | S |
| Config key read | config.md:49,63-66,103, debug.md:36, execute SKILL.md:66,79,278,589,636,840 | `jq -r '.key // "default"' config.json` -- used ~15 times across MD files. Simple key extraction with default | `yolo config-read` | S |
| Config key write | config.md:181-198,264-298 | `jq '.key = "value"' config.json > tmp && mv tmp config.json` -- atomic JSON update. Used ~10 times in config.md alone | `yolo config-write` | S |
| Config feature flag list | config.md:103-104 | `jq 'to_entries[] | select(.key | startswith("v3_") or startswith("v2_"))` -- enumerate feature flags with values | `yolo config-read --flags` | S |
| Progress counting | status.md, resume.md | Count `*-PLAN.md` vs `*-SUMMARY.md` per phase directory, compute percentage. Used in status dashboard + resume context | `yolo progress` | M |
| Git state snapshot | debug.md:15, release.md:16,23,31, execute SKILL.md:17 | `git log --oneline -N`, `git status --short`, `git status --porcelain`, `git log --grep`. Multiple git read ops combined | `yolo git-state` | M |
| Frontmatter extraction | (implicit in plan.md, execute SKILL.md) | Parse YAML frontmatter from PLAN.md/SUMMARY.md files. Currently done by LLM reading files | `yolo frontmatter` | S |
| File existence check | init.md:22,27,33, doctor.md, status.md:28,32 | `ls -la .yolo-planning`, `ls .yolo-planning/phases/`, `cat .yolo-planning/ACTIVE`. Multiple file/dir existence checks | `yolo check-exists` | S |
| Version comparison | update.md:82-83 | Compare cached version vs remote version string. Currently shell string comparison | `yolo version-compare` | S |
| UUID generation | execute SKILL.md:26 | `uuidgen \| tr '[:upper:]' '[:lower:]'` with fallback. Used for correlation IDs | `yolo uuid` | S |
| Execution state JSON update | execute SKILL.md:108-112, 199-206, etc. | Atomic jq updates to `.execution-state.json` (cycle tracking, loop state, status). ~15 distinct update patterns | `yolo exec-state` | M |
| Cost ledger aggregation | status.md:51 | Read `.cost-ledger.json`, aggregate per-agent costs, compute totals + percentages | `yolo cost-ledger` (or extend `yolo report-tokens`) | M |
| Active milestone read | pause.md:12, todo.md:14, list-todos.md:14, status.md:32, resume.md:14 | `cat .yolo-planning/ACTIVE` -- 5+ command files read the active milestone slug | `yolo active-milestone` (or part of `yolo config-read`) | S |

## Summary Statistics

- **Total Rust CLI commands:** 69 (65 unique + 4 bootstrap subcommands)
- **Total MD-side deterministic operations:** ~95 unique occurrences across 33 files
- **Covered (Rust CLI exists):** ~60 operations (63%)
- **Needs Enhancement:** 5 existing commands
- **Needs New Command:** 14 new commands/flags
- **Most impactful new commands:** `plugin-root` (25+ call sites), `config-read`/`config-write` (25+ jq calls), `progress` (status/resume dashboards)
