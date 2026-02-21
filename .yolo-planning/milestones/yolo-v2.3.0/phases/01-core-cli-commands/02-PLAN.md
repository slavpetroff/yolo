---
phase: 1
plan: 02
title: "Migrate planning-git.sh to Rust CLI"
wave: 1
depends_on: []
must_haves:
  - "`yolo planning-git sync-ignore [config]` replicates sync-ignore behavior"
  - "`yolo planning-git commit-boundary <action> [config]` replicates commit-boundary behavior"
  - "`yolo planning-git push-after-phase [config]` replicates push-after-phase behavior"
  - "All 3 subcommands handle non-git-repo gracefully (exit 0)"
  - "Unit tests covering config parsing, gitignore management, and commit logic"
---

## Task 1: Implement planning-git command with sync-ignore subcommand

**Files:** `yolo-mcp-server/src/commands/planning_git.rs`

**Acceptance:** `yolo planning-git sync-ignore .yolo-planning/config.json` correctly manages root .gitignore and transient .yolo-planning/.gitignore entries, matching bash script behavior.

Implement `pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String>`:

1. Parse first arg as subcommand: sync-ignore, commit-boundary, push-after-phase
2. `sync-ignore [config_file]`:
   - Check if in a git repo (`git rev-parse --git-dir`)
   - Read config: `planning_tracking` (default "manual"), `auto_push` (default "never")
   - If mode="ignore": ensure `.yolo-planning/` line in root .gitignore
   - If mode="commit": remove `.yolo-planning/` from root .gitignore, then write transient ignore entries to `.yolo-planning/.gitignore` (execution-state, context files, session tracking, metrics, caching, artifacts, events, snapshots, logging, baselines, codebase mapping)
   - If mode="manual": no .gitignore changes
3. Non-git-repo: exit 0 silently

Include unit tests for: ignore mode adds line, commit mode removes line and creates transient ignore, manual mode is no-op, non-git-repo returns Ok.

## Task 2: Implement commit-boundary subcommand

**Files:** `yolo-mcp-server/src/commands/planning_git.rs` (extend)

**Acceptance:** `yolo planning-git commit-boundary "plan phase 1" .yolo-planning/config.json` stages and commits planning artifacts when `planning_tracking=commit`, and pushes when `auto_push=always`.

Add commit-boundary handling:

1. Parse: action (required), config_file (optional, defaults to .yolo-planning/config.json)
2. Check git repo, read config
3. If `planning_tracking != "commit"`: exit 0
4. Write transient ignore file (ensure_transient_ignore)
5. `git add .yolo-planning` and `git add CLAUDE.md` (if exists)
6. If no staged changes (`git diff --cached --quiet`): exit 0
7. `git commit -m "chore(yolo): {action}"`
8. If `auto_push=always` and branch has upstream: `git push`

Use `std::process::Command` for git operations. Include tests for: commit mode stages+commits, non-commit mode is no-op, no staged changes is no-op.

## Task 3: Implement push-after-phase subcommand

**Files:** `yolo-mcp-server/src/commands/planning_git.rs` (extend)

**Acceptance:** `yolo planning-git push-after-phase .yolo-planning/config.json` pushes when `auto_push=after_phase` and branch has upstream.

Add push-after-phase handling:

1. Parse: config_file (optional, defaults to .yolo-planning/config.json)
2. Check git repo, read config
3. If `auto_push=after_phase` and branch has upstream (`git rev-parse --abbrev-ref --symbolic-full-name @{u}`): `git push`
4. Otherwise: exit 0

Include tests for: after_phase mode triggers push check, never mode is no-op.

## Task 4: Register planning-git in CLI router and module registry

**Files:** `yolo-mcp-server/src/commands/mod.rs`, `yolo-mcp-server/src/cli/router.rs`

**Acceptance:** `yolo planning-git <subcommand>` is routable from the CLI. `cargo test` and `cargo build` pass.

1. Add `pub mod planning_git;` to `commands/mod.rs`
2. Add import in router.rs
3. Add match arm: `"planning-git"` -> `planning_git::execute(&args, &cwd)`
4. Run `cargo test` and `cargo build`
