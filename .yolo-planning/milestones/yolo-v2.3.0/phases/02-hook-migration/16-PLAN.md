---
phase: 2
plan: 16
title: "Migrate verification scripts to native Rust (pre-push-hook, verify-claude-bootstrap, verify-init-todo, verify-vibe)"
wave: 3
depends_on: [1, 14]
must_haves:
  - "pre_push_hook enforces version file consistency before git push"
  - "verify_init_todo validates STATE.md template and bootstrap output contracts"
  - "verify_vibe validates all 25 vibe command requirements"
  - "verify_claude_bootstrap delegates to cargo test"
  - "All verification scripts are callable as yolo verify <name>"
---

## Task 1: Implement pre_push_hook module

**Files:** `yolo-mcp-server/src/commands/pre_push_hook.rs` (new)

**Acceptance:** `pre_push_hook::execute() -> Result<(String, i32), String>`. Find repo root via `Command::new("git").args(["rev-parse", "--show-toplevel"])`. Guard: skip if `scripts/bump-version.sh` doesn't exist (not a YOLO repo). Call `bump_version::execute(["--verify"])` (from Plan 14). On mismatch: output error message with MISMATCH details, exit 1. On sync: exit 0 silently. This replaces the bash pre-push-hook.sh delegation chain.

## Task 2: Implement verify_init_todo module

**Files:** `yolo-mcp-server/src/commands/verify_init_todo.rs` (new)

**Acceptance:** `verify_init_todo::execute() -> Result<(String, i32), String>`. Check contracts: (1) templates/STATE.md has `## Todos` section, (2) no `### Pending Todos` subsection, (3) commands/todo.md anchors on `## Todos`, (4) todo command doesn't reference `Pending Todos`. Bootstrap checks: run `bootstrap_state::execute()` to temp dir, verify output has `## Todos`, no `### Pending Todos`, has `None.` placeholder. Output PASS/FAIL per check with totals. Exit 0 if all pass, exit 1 if any fail. Use `str::contains()` and `str::lines()` for checks.

## Task 3: Implement verify_vibe module

**Files:** `yolo-mcp-server/src/commands/verify_vibe.rs` (new)

**Acceptance:** `verify_vibe::execute() -> Result<(String, i32), String>`. Validates 25 requirements (REQ-01 through REQ-25) across 6 groups. Read-only: never modifies files. Checks include: vibe.md contains required sections, execute-protocol.md alignment, command presence in commands dir, README.md mentions, CLAUDE.md consistency, marketplace.json entries. Each check: `PASS REQ-XX: description` or `FAIL REQ-XX: description`. Group summaries. Final summary with total pass/fail. Exit 0 if all pass, exit 1 if any fail. All file reads via `std::fs::read_to_string`, pattern matching via `str::contains()`.

## Task 4: Implement verify_claude_bootstrap and unified verify dispatcher

**Files:** `yolo-mcp-server/src/commands/verify_claude_bootstrap.rs` (new), `yolo-mcp-server/src/commands/verify.rs` (new)

**Acceptance:** `verify_claude_bootstrap::execute() -> Result<(String, i32), String>`: run `Command::new("cargo").args(["test"])` in the yolo-mcp-server directory. Pass through output and exit code. `verify::execute(name) -> Result<(String, i32), String>`: dispatch to specific verify module by name: "vibe" -> verify_vibe, "init-todo" -> verify_init_todo, "bootstrap" -> verify_claude_bootstrap, "pre-push" -> pre_push_hook. Unknown names return error.

## Task 5: Register CLI commands and add tests

**Files:** `yolo-mcp-server/src/commands/mod.rs`, `yolo-mcp-server/src/cli/router.rs`, `yolo-mcp-server/src/commands/verify_init_todo.rs` (append tests), `yolo-mcp-server/src/commands/verify_vibe.rs` (append tests)

**Acceptance:** Register `yolo verify <name>` in router (dispatch to verify::execute). Tests cover: pre-push version sync detection, init-todo section presence checks, init-todo bootstrap output validation, verify dispatcher routing. Note: verify-vibe tests require fixture files mimicking commands/vibe.md structure. `cargo test` passes.
