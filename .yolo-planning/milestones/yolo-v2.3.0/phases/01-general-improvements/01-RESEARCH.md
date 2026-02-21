# Phase 1 Research: CLI/MCP Audit & Fix

## Findings

### A. Non-Existent CLI Subcommands (9 broken calls across 4 commands)

| Command | CLI call that FAILS | Correct subcommand | Fix type |
|---------|--------------------|--------------------|----------|
| `init.md` L179 | `yolo install-hooks` | Module exists, NOT wired in router | Wire in router |
| `init.md` L187 | `yolo install-mcp` | No implementation anywhere | Implement or remove |
| `init.md` L399 | `yolo infer-gsd-summary` | `yolo gsd-summary` | Fix name in command |
| `config.md` L32 | `yolo migrate-config` | Module exists, NOT wired in router | Wire in router |
| `todo.md` L26 | `yolo persist-state-after-ship` | `yolo persist-state` | Fix name in command |
| `todo.md` L27 | `yolo migrate-orphaned-state` | Module exists, NOT wired in router | Wire in router |
| `vibe.md` L214,284,285 | `yolo compile-context` | Only MCP tool, no CLI | Add CLI subcommand |
| `vibe.md` L377 | `yolo compile-rolling-summary` | `yolo rolling-summary` | Fix name in command |
| `vibe.md` L385 | `yolo persist-state-after-ship` | `yolo persist-state` | Fix name in command |

### B. Modules Compiled But Not Routed (3 modules)

In `src/commands/mod.rs` but missing `match` arm in `src/cli/router.rs`:
1. `install_hooks.rs` — needs `"install-hooks"` entry
2. `migrate_config.rs` — needs `"migrate-config"` entry
3. `migrate_orphaned_state.rs` — needs `"migrate-orphaned-state"` entry

### C. MCP Tool vs CLI Gap

`compile_context` MCP tool takes only `phase: integer`. Commands call it as CLI with 3-4 args: `{phase} {role} {phases_dir} [plan_path]`. **Either** add CLI subcommand or extend MCP tool interface.

### D. Missing Implementation

`yolo install-mcp` has no Rust module, no router entry, no script. The init flow step 1.6 is completely dead. The `install-yolo-mcp.sh` script at repo root exists but is never called by the CLI.

### E. Help Command Status

`/yolo:help` exists and calls `yolo help-output` (valid). But it only shows available commands — it does NOT provide contextual error recovery guidance (e.g., "if init fails at step X, try Y").

## Relevant Patterns

- Router at `src/cli/router.rs` dispatches on first CLI arg via `match`
- Each command module exposes `pub fn run(args: &[String]) -> Result<()>`
- MCP tools in `src/mcp/tools.rs` are separate from CLI routing
- Command markdown files reference CLI subcommands with `"$HOME/.cargo/bin/yolo" subcommand args`

## Risks

- Changing router.rs requires recompilation of the Rust binary
- Users on older versions will still have the broken binary
- MCP tool interface changes need coordination with tools.rs registrations

## Recommendations

1. **Quick wins**: Fix 4 wrong subcommand names in command files (no Rust changes)
2. **Medium effort**: Wire 3 existing modules into router.rs (simple match arm additions)
3. **Larger effort**: Add compile-context CLI subcommand, implement install-mcp
4. **Enhancement**: Extend help command with error recovery guidance
