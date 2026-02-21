# Plan 16 Summary: Migrate verification scripts to native Rust

## Status: COMPLETE

## Tasks Completed: 5/5

### Task 1: Implement pre_push_hook module
- **File**: `yolo-mcp-server/src/commands/pre_push_hook.rs` (new)
- Finds repo root via `Command::new("git").args(["rev-parse", "--show-toplevel"])`. Guards: skips if `scripts/bump-version.sh` doesn't exist (not a YOLO repo). Calls `bump_version::execute(["--verify"])`. On mismatch: outputs error message with MISMATCH details, exit 1. On sync: exit 0 silently. Non-fatal errors log warning but don't block push.
- **Tests**: 2 unit tests (test_get_repo_root, test_execute_in_repo)

### Task 2: Implement verify_init_todo module
- **File**: `yolo-mcp-server/src/commands/verify_init_todo.rs` (new)
- Validates init/todo contracts: templates/STATE.md has `## Todos`, no `### Pending Todos`, commands/todo.md anchors on `## Todos`, todo command doesn't reference `Pending Todos`. Bootstrap checks: runs `bootstrap_state::execute()` to temp dir, verifies output. PASS/FAIL per check with totals.
- **Tests**: 5 unit tests (file_has_line, file_contains, missing file, check_pass, check_fail)

### Task 3: Implement verify_vibe module
- **File**: `yolo-mcp-server/src/commands/verify_vibe.rs` (new)
- Validates 25 requirements (REQ-01 through REQ-25) across 6 groups: Core Router, Mode Implementation, Execution Protocol, Command Surface, NL Parsing, Flags. Read-only: never modifies files. Each check outputs PASS/FAIL with group summaries and final totals.
- **Tests**: 7 unit tests (file_contains, file_contains_ci, count_md_files, count_flag_lines, chk_pass, chk_fail)

### Task 4: Implement verify_claude_bootstrap and unified verify dispatcher
- **Files**: `yolo-mcp-server/src/commands/verify_claude_bootstrap.rs` (new), `yolo-mcp-server/src/commands/verify.rs` (new)
- verify_claude_bootstrap: delegates to `cargo test bootstrap_claude::tests` in yolo-mcp-server dir. Passes through stdout/stderr and exit code.
- verify: unified dispatcher routes "vibe" -> verify_vibe, "init-todo" -> verify_init_todo, "bootstrap" -> verify_claude_bootstrap, "pre-push" -> pre_push_hook. Unknown names return error.
- **Tests**: 4 unit tests (1 bootstrap + 3 dispatcher: insufficient_args, unknown_target, dispatch_routes)

### Task 5: Register CLI commands and add tests
- **Files**: `yolo-mcp-server/src/commands/mod.rs`, `yolo-mcp-server/src/cli/router.rs`
- Registered: `yolo verify <name>` in router dispatching to verify::execute
- All modules declared in mod.rs: pre_push_hook, verify_init_todo, verify_vibe, verify_claude_bootstrap, verify

## Metrics
- **New files**: 5 (pre_push_hook.rs, verify_init_todo.rs, verify_vibe.rs, verify_claude_bootstrap.rs, verify.rs)
- **New tests**: 18 (across all modules)
- **Shell-outs eliminated**: 4 (pre-push-hook.sh, verify-init-todo.sh, verify-vibe.sh, verify-claude-bootstrap.sh)
