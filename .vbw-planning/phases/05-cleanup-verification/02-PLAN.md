---
phase: 5
plan: 02
title: "Update command .md files to remove bash script references"
wave: 1
depends_on: []
must_haves:
  - "All 12 command .md files with bash/scripts references are updated"
  - "References to `bash scripts/` or `bash ${CLAUDE_PLUGIN_ROOT}/scripts/` replaced with `yolo` CLI equivalents"
  - "No command .md file references any .sh file or scripts/ path"
  - "Command semantics preserved (same inputs/outputs, just different invocation)"
---

## Task 1: Update commands/init.md to use Rust CLI calls

**Files:** `commands/init.md`

**Acceptance:** All `bash ${CLAUDE_PLUGIN_ROOT}/scripts/generate-gsd-index.sh` replaced with `yolo generate-gsd-index`. All `bash ${CLAUDE_PLUGIN_ROOT}/scripts/install-hooks.sh` replaced with `yolo install-hooks`. All `bash ${CLAUDE_PLUGIN_ROOT}/scripts/infer-gsd-summary.sh` replaced with `yolo infer-gsd-summary`. Comment references to `scripts/generate-gsd-index.sh` and `infer-gsd-summary.sh` updated to reference the Rust equivalents. References to `Skills.sh` registry (proper noun, not a script) are left unchanged. `grep -c '\.sh' commands/init.md` returns 0 (excluding Skills.sh proper noun references if any). Command behavior description unchanged.

## Task 2: Update commands/vibe.md to use Rust CLI calls

**Files:** `commands/vibe.md`

**Acceptance:** All `bash ${CLAUDE_PLUGIN_ROOT}/scripts/compile-context.sh` replaced with `yolo compile-context`. All `bash ${CLAUDE_PLUGIN_ROOT}/scripts/compile-rolling-summary.sh` replaced with `yolo compile-rolling-summary`. All `bash ${CLAUDE_PLUGIN_ROOT}/scripts/persist-state-after-ship.sh` replaced with `yolo persist-state-after-ship`. References to `phase-detect.sh` and `suggest-next.sh` updated to reference Rust equivalents (phase-detect, suggest-next). No `.sh` extension or `scripts/` path remains. Command flow logic preserved exactly.

## Task 3: Update commands/todo.md, commands/config.md, commands/help.md

**Files:** `commands/todo.md`, `commands/config.md`, `commands/help.md`

**Acceptance:** In todo.md: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/persist-state-after-ship.sh` → `yolo persist-state-after-ship`, `bash ${CLAUDE_PLUGIN_ROOT}/scripts/migrate-orphaned-state.sh` → `yolo migrate-orphaned-state`. In config.md: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/migrate-config.sh` → `yolo migrate-config`. In help.md: `bash ${CLAUDE_PLUGIN_ROOT}/...scripts/help-output.sh` → `yolo help-output`. `grep -l '\.sh' commands/todo.md commands/config.md commands/help.md` returns empty.

## Task 4: Update commands/release.md, commands/doctor.md, commands/update.md

**Files:** `commands/release.md`, `commands/doctor.md`, `commands/update.md`

**Acceptance:** In release.md: `bash scripts/bump-version.sh` → `yolo bump-version` (all 3 occurrences). In doctor.md: `bash scripts/bump-version.sh --verify` → `yolo bump-version --verify`, `scripts/*.sh` permission check removed or updated to reference Rust binary, `bash scripts/doctor-cleanup.sh` → `yolo doctor-cleanup`. In update.md: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/cache-nuke.sh` → `yolo cache-nuke`. `grep -l '\.sh' commands/release.md commands/doctor.md commands/update.md` returns empty.

## Task 5: Update commands/skills.md and verify all commands/ are clean

**Files:** `commands/skills.md`, all `commands/*.md` (verify)

**Acceptance:** In skills.md: `detect-stack.sh` reference in error string updated to `detect-stack`. `skills.sh` as proper noun reference to the Skills.sh registry is allowed to remain (it's a service name, not a local script). Final verification: `grep -rl 'scripts/' commands/` returns empty. `grep -rl '\.sh' commands/ | grep -v Skills.sh` returns empty (only Skills.sh proper noun allowed). Single atomic commit: `refactor(commands): replace all bash script references with Rust CLI calls`.
