---
phase: 1
plan: 04
title: "Update command .md files to call Rust CLI instead of bash scripts"
wave: 2
depends_on: [1, 2, 3]
must_haves:
  - "vibe.md references `yolo resolve-model`, `yolo resolve-turns`, `yolo planning-git`, and `yolo bootstrap project|requirements|roadmap|state`"
  - "init.md references Rust CLI commands instead of bash scripts"
  - "config.md references `yolo resolve-model` instead of bash scripts"
  - "fix.md references `yolo resolve-model` and `yolo resolve-turns` instead of bash scripts"
  - "Zero remaining `bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-model.sh` or equivalent references in updated files"
---

## Task 1: Update vibe.md to use Rust CLI commands

**Files:** `commands/vibe.md`

**Acceptance:** All references to the 7 migrated bash scripts are replaced with equivalent `yolo` CLI calls. No `bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-model.sh`, `resolve-agent-max-turns.sh`, `planning-git.sh`, or `bootstrap/*.sh` references remain.

Replace all bash script calls in vibe.md:

1. `bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-model.sh lead .yolo-planning/config.json ${CLAUDE_PLUGIN_ROOT}/config/model-profiles.json` -> `"$HOME/.cargo/bin/yolo" resolve-model lead .yolo-planning/config.json ${CLAUDE_PLUGIN_ROOT}/config/model-profiles.json`
2. `bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-max-turns.sh lead .yolo-planning/config.json "{effort}"` -> `"$HOME/.cargo/bin/yolo" resolve-turns lead .yolo-planning/config.json "{effort}"`
3. `bash ${CLAUDE_PLUGIN_ROOT}/scripts/bootstrap/bootstrap-project.sh` -> `"$HOME/.cargo/bin/yolo" bootstrap project`
4. `bash ${CLAUDE_PLUGIN_ROOT}/scripts/bootstrap/bootstrap-requirements.sh` -> `"$HOME/.cargo/bin/yolo" bootstrap requirements`
5. `bash ${CLAUDE_PLUGIN_ROOT}/scripts/bootstrap/bootstrap-roadmap.sh` -> `"$HOME/.cargo/bin/yolo" bootstrap roadmap`
6. `bash ${CLAUDE_PLUGIN_ROOT}/scripts/bootstrap/bootstrap-state.sh` -> `"$HOME/.cargo/bin/yolo" bootstrap state`
7. `bash ${CLAUDE_PLUGIN_ROOT}/scripts/planning-git.sh` -> `"$HOME/.cargo/bin/yolo" planning-git`

Preserve argument order and all surrounding context/comments.

## Task 2: Update init.md to use Rust CLI commands

**Files:** `commands/init.md`

**Acceptance:** All references to the 7 migrated bash scripts replaced. Comments referencing script names updated. Zero bash script references for these 7 scripts remain.

Replace all bash script calls in init.md:

1. `bash ${CLAUDE_PLUGIN_ROOT}/scripts/planning-git.sh sync-ignore` -> `"$HOME/.cargo/bin/yolo" planning-git sync-ignore`
2. `bash ${CLAUDE_PLUGIN_ROOT}/scripts/bootstrap/bootstrap-project.sh` -> `"$HOME/.cargo/bin/yolo" bootstrap project`
3. `bash ${CLAUDE_PLUGIN_ROOT}/scripts/bootstrap/bootstrap-requirements.sh` -> `"$HOME/.cargo/bin/yolo" bootstrap requirements`
4. `bash ${CLAUDE_PLUGIN_ROOT}/scripts/bootstrap/bootstrap-roadmap.sh` -> `"$HOME/.cargo/bin/yolo" bootstrap roadmap`
5. `bash ${CLAUDE_PLUGIN_ROOT}/scripts/bootstrap/bootstrap-state.sh` -> `"$HOME/.cargo/bin/yolo" bootstrap state`
6. `bash ${CLAUDE_PLUGIN_ROOT}/scripts/planning-git.sh commit-boundary` -> `"$HOME/.cargo/bin/yolo" planning-git commit-boundary`
7. Update HTML comments that reference script names (lines 441-446) to reference Rust CLI equivalents

## Task 3: Update config.md to use Rust CLI commands

**Files:** `commands/config.md`

**Acceptance:** All 13 references to `resolve-agent-model.sh` replaced with `yolo resolve-model`. The `planning-git.sh sync-ignore` reference replaced. Zero bash script references remain.

Replace all bash script calls in config.md:

1. All `bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-model.sh <agent> .yolo-planning/config.json ${CLAUDE_PLUGIN_ROOT}/config/model-profiles.json` -> `"$HOME/.cargo/bin/yolo" resolve-model <agent> .yolo-planning/config.json ${CLAUDE_PLUGIN_ROOT}/config/model-profiles.json`
2. `bash ${CLAUDE_PLUGIN_ROOT}/scripts/planning-git.sh sync-ignore` -> `"$HOME/.cargo/bin/yolo" planning-git sync-ignore`

This covers lines 56-59 (display section), 135-138 (cost calculation), 155-156 (Round 1), 169-170 (Round 2), 336 (per-agent override), and 245 (sync-ignore).

## Task 4: Update fix.md and other command files to use Rust CLI commands

**Files:** `commands/fix.md`, `commands/debug.md`, `commands/map.md`, `references/execute-protocol.md`

**Acceptance:** All references to `resolve-agent-model.sh`, `resolve-agent-max-turns.sh`, and `planning-git.sh` replaced with Rust CLI equivalents in fix.md, debug.md, map.md, and execute-protocol.md.

Replace all bash script calls:

1. **fix.md** (2 references):
   - `bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-model.sh dev` -> `"$HOME/.cargo/bin/yolo" resolve-model dev`
   - `bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-max-turns.sh dev` -> `"$HOME/.cargo/bin/yolo" resolve-turns dev`

2. **debug.md** (4 references):
   - All `bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-model.sh debugger` -> `"$HOME/.cargo/bin/yolo" resolve-model debugger`
   - All `bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-max-turns.sh debugger` -> `"$HOME/.cargo/bin/yolo" resolve-turns debugger`

3. **map.md** (1 reference):
   - `bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-max-turns.sh scout` -> `"$HOME/.cargo/bin/yolo" resolve-turns scout`

4. **execute-protocol.md** (3 references):
   - `bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-model.sh dev` -> `"$HOME/.cargo/bin/yolo" resolve-model dev`
   - `bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-max-turns.sh dev` -> `"$HOME/.cargo/bin/yolo" resolve-turns dev`
   - `bash ${CLAUDE_PLUGIN_ROOT}/scripts/planning-git.sh` -> `"$HOME/.cargo/bin/yolo" planning-git`

## Task 5: Verify zero remaining bash script references and commit

**Files:** (verification only, no new files)

**Acceptance:** `grep -r` across commands/ and references/ confirms zero remaining references to the 7 migrated scripts. `cargo build` succeeds.

1. Run: `grep -rn 'resolve-agent-model\.sh\|resolve-agent-max-turns\.sh\|planning-git\.sh\|bootstrap-project\.sh\|bootstrap-requirements\.sh\|bootstrap-roadmap\.sh\|bootstrap-state\.sh' commands/ references/execute-protocol.md`
2. Expected output: no matches
3. Run `cargo build --release` to verify binary compiles
4. Commit: `refactor(commands): replace bash script references with Rust CLI commands`
