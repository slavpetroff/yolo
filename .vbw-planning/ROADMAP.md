# YOLO Plugin Roadmap

**Goal:** YOLO Plugin

**Scope:** 5 phases

## Progress
| Phase | Status | Plans | Tasks | Commits |
|-------|--------|-------|-------|---------|
| 1 | Complete | 4 | 18 | 16 |
| 2 | Pending | 0 | 0 | 0 |
| 3 | Pending | 0 | 0 | 0 |
| 4 | Pending | 0 | 0 | 0 |
| 5 | Pending | 0 | 0 | 0 |

---

## Phase List
- [x] [Phase 1: Core CLI Commands](#phase-1-core-cli-commands)
- [ ] [Phase 2: Hook Migration](#phase-2-hook-migration)
- [ ] [Phase 3: Internal Shell-out Elimination](#phase-3-internal-shell-out-elimination)
- [ ] [Phase 4: Feature & Validation Scripts](#phase-4-feature-validation-scripts)
- [ ] [Phase 5: Cleanup & Verification](#phase-5-cleanup-verification)

---

## Phase 1: Core CLI Commands

**Goal:** Migrate the most frequently called scripts to Rust CLI subcommands: resolve-agent-model, resolve-agent-max-turns, planning-git, and bootstrap-*.sh (4 scripts). Update vibe.md, init.md, config.md, fix.md to call Rust CLI instead of bash.

**Requirements:** REQ-01, REQ-02, REQ-06

**Success Criteria:**
- yolo resolve-model <agent> replaces resolve-agent-model.sh
- yolo resolve-turns <agent> replaces resolve-agent-max-turns.sh
- yolo planning-git <subcommand> replaces planning-git.sh
- yolo bootstrap project|requirements|roadmap|state replaces 4 bootstrap-*.sh scripts
- All command .md files updated to call Rust CLI, zero bash script references for these 7 scripts

**Dependencies:** None

---

## Phase 2: Hook Migration

**Goal:** Migrate all hook scripts to Rust: validate-summary, validate-frontmatter, agent-start/stop, agent-health, security-filter, prompt-preflight, compaction-instructions, post-compact, session-stop, notification-log, skill-hook-dispatch, blocker-notify. Implement missing hooks (bash-guard, validate-commit, file-guard, qa-gate, task-verify). Replace hook-wrapper.sh with Rust hook dispatcher.

**Requirements:** REQ-03, REQ-05

**Success Criteria:**
- All hooks in hooks.json call yolo hook <event> instead of hook-wrapper.sh
- Missing hooks (bash-guard, validate-commit, file-guard, qa-gate, task-verify) implemented in Rust
- hook-wrapper.sh no longer needed
- All SubagentStart/Stop/TeammateIdle/TaskCompleted hooks handled by Rust

**Dependencies:** Phase 1

---

## Phase 3: Internal Shell-out Elimination

**Goal:** Remove all Command::new("bash") calls from existing Rust code. session-start.rs still shells out to migrate-config.sh, install-hooks.sh, clean-stale-teams.sh, tmux-watchdog.sh, migrate-orphaned-state.sh. hard_gate.rs shells out to log-event.sh and collect-metrics.sh. Rewrite these as native Rust.

**Requirements:** REQ-04, REQ-06

**Success Criteria:**
- Zero Command::new("bash") calls in yolo-mcp-server/src/
- session_start.rs handles config migration, hook install, cleanup, watchdog natively
- Telemetry (log-event, collect-metrics) is native Rust
- grep -r 'Command::new' yolo-mcp-server/src/ returns only non-bash commands

**Dependencies:** Phase 2

---

## Phase 4: Feature & Validation Scripts

**Goal:** Migrate remaining feature scripts: lock-lite/lease-lock, validate-contract/message/schema, assess-plan-risk/resolve-gate-policy, smart-route/route-monorepo, compile-rolling-summary/persist-state-after-ship, snapshot-resume/recover-state, two-phase-complete, map-staleness, delta-files, cache-context/cache-nuke, generate-incidents, artifact-registry, bump-version, token-budget.

**Requirements:** REQ-01, REQ-06

**Success Criteria:**
- All feature scripts have Rust CLI or MCP equivalents
- Commands referencing these scripts updated to use Rust
- v3 flag-gated features work through Rust

**Dependencies:** Phase 3

---

## Phase 5: Cleanup & Verification

**Goal:** Delete all obsolete bash scripts from scripts/. Remove hook-wrapper.sh. Update CLAUDE.md, references, and documentation. Verify all workflows end-to-end: init, vibe (bootstrap/scope/plan/execute/archive), fix, verify, status, config. Run full test suite.

**Requirements:** REQ-01, REQ-02, REQ-03, REQ-04, REQ-05, REQ-06

**Success Criteria:**
- scripts/ directory contains zero .sh files (or only truly needed utilities)
- All /yolo:* commands work without any bash script dependencies
- Full init -> vibe -> plan -> execute -> archive workflow passes
- No regressions in existing functionality

**Dependencies:** Phase 4

