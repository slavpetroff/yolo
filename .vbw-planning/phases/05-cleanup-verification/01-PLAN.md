---
phase: 5
plan: 01
title: "Delete all obsolete bash scripts from scripts/ and scripts/bootstrap/"
wave: 1
depends_on: []
must_haves:
  - "All 63 .sh files in scripts/ are deleted"
  - "All 4 .sh files in scripts/bootstrap/ are deleted"
  - "scripts/bootstrap/ directory is removed"
  - "scripts/ directory is either removed entirely or empty (no .sh files remain)"
  - "git rm used for tracked files so deletions are staged"
---

## Task 1: Delete all scripts/*.sh files (batch 1: agent/artifact/planning)

**Files:** `scripts/agent-health.sh`, `scripts/agent-pid-tracker.sh`, `scripts/agent-start.sh`, `scripts/agent-stop.sh`, `scripts/artifact-registry.sh`, `scripts/assess-plan-risk.sh`, `scripts/auto-repair.sh`, `scripts/blocker-notify.sh`, `scripts/bump-version.sh`, `scripts/cache-context.sh`, `scripts/cache-nuke.sh`, `scripts/clean-stale-teams.sh`, `scripts/collect-metrics.sh` (all deleted)

**Acceptance:** All 13 files above are deleted via `git rm`. `ls scripts/agent-*.sh scripts/artifact-registry.sh scripts/assess-plan-risk.sh scripts/auto-repair.sh scripts/blocker-notify.sh scripts/bump-version.sh scripts/cache-*.sh scripts/clean-stale-teams.sh scripts/collect-metrics.sh 2>/dev/null` returns empty.

## Task 2: Delete all scripts/*.sh files (batch 2: compile/contract/delta through lock)

**Files:** `scripts/compaction-instructions.sh`, `scripts/compile-rolling-summary.sh`, `scripts/contract-revision.sh`, `scripts/delta-files.sh`, `scripts/doctor-cleanup.sh`, `scripts/generate-contract.sh`, `scripts/generate-gsd-index.sh`, `scripts/generate-incidents.sh`, `scripts/help-output.sh`, `scripts/hook-wrapper.sh`, `scripts/infer-gsd-summary.sh`, `scripts/install-hooks.sh`, `scripts/lease-lock.sh`, `scripts/lock-lite.sh`, `scripts/log-event.sh` (all deleted)

**Acceptance:** All 15 files above are deleted via `git rm`. None exist on disk.

## Task 3: Delete all scripts/*.sh files (batch 3: map through session)

**Files:** `scripts/map-staleness.sh`, `scripts/migrate-config.sh`, `scripts/migrate-orphaned-state.sh`, `scripts/notification-log.sh`, `scripts/persist-state-after-ship.sh`, `scripts/planning-git.sh`, `scripts/post-compact.sh`, `scripts/pre-push-hook.sh`, `scripts/prompt-preflight.sh`, `scripts/recover-state.sh`, `scripts/resolve-agent-max-turns.sh`, `scripts/resolve-agent-model.sh`, `scripts/resolve-claude-dir.sh`, `scripts/resolve-gate-policy.sh`, `scripts/rollout-stage.sh`, `scripts/route-monorepo.sh`, `scripts/security-filter.sh`, `scripts/session-stop.sh` (all deleted)

**Acceptance:** All 18 files above are deleted via `git rm`. None exist on disk.

## Task 4: Delete all scripts/*.sh files (batch 4: skill through verify) and bootstrap/

**Files:** `scripts/skill-hook-dispatch.sh`, `scripts/smart-route.sh`, `scripts/snapshot-resume.sh`, `scripts/tmux-watchdog.sh`, `scripts/token-budget.sh`, `scripts/two-phase-complete.sh`, `scripts/update-state.sh`, `scripts/validate-contract.sh`, `scripts/validate-frontmatter.sh`, `scripts/validate-message.sh`, `scripts/validate-schema.sh`, `scripts/validate-summary.sh`, `scripts/verify-claude-bootstrap.sh`, `scripts/verify-init-todo.sh`, `scripts/verify-vibe.sh` (all deleted), `scripts/bootstrap/bootstrap-project.sh`, `scripts/bootstrap/bootstrap-requirements.sh`, `scripts/bootstrap/bootstrap-roadmap.sh`, `scripts/bootstrap/bootstrap-state.sh` (all deleted), `scripts/bootstrap/` (directory removed)

**Acceptance:** All 19 files above are deleted via `git rm`. `scripts/bootstrap/` directory no longer exists. `find scripts/ -name '*.sh' 2>/dev/null` returns empty.

## Task 5: Verify scripts/ directory is clean and commit

**Files:** `scripts/` (verify only)

**Acceptance:** `find scripts/ -name '*.sh' | wc -l` returns 0. `git status` shows all 67 .sh files as deleted and staged. No non-.sh files in scripts/ were accidentally removed. If scripts/ directory is now empty, remove it entirely. Single atomic commit: `chore(scripts): delete all obsolete bash scripts replaced by Rust`.
