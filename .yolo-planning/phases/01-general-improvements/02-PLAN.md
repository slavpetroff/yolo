---
phase: 01
plan: 02
title: "Wire unrouted modules and add missing CLI subcommands"
wave: 1
depends_on: []
must_haves:
  - install-hooks, migrate-config, and migrate-orphaned-state are routed in router.rs
  - compile-context CLI subcommand exists and delegates to MCP compile_context logic
  - install-mcp CLI subcommand exists and delegates to install-yolo-mcp.sh
---

## Tasks

### Task 1: Wire install-hooks into router.rs
**Files:** yolo-mcp-server/src/cli/router.rs
**Action:** Add a match arm `"install-hooks"` that calls `install_hooks::install_hooks()`. The function returns `Result<String, String>` (not the standard `(String, i32)` tuple), so wrap the result: `install_hooks::install_hooks().map(|s| (s, 0))`. Add `install_hooks` to the `use` import list at line 6.
**Acceptance:** `yolo install-hooks` succeeds in a git repo (returns "Installed" or "already installed").

### Task 2: Wire migrate-config into router.rs
**Files:** yolo-mcp-server/src/cli/router.rs
**Action:** Add a match arm `"migrate-config"` that parses args for config_path and defaults_path, then calls `migrate_config::migrate_config(config_path, defaults_path)`. The function signature is `migrate_config(config_path: &Path, defaults_path: &Path) -> Result<usize, String>`. Support `--print-added` flag to print the count. Expected usage from config.md: `yolo migrate-config --print-added .yolo-planning/config.json`. The defaults_path should resolve to `${CLAUDE_PLUGIN_ROOT}/config/defaults.json` or be passed as a second arg.
**Acceptance:** `yolo migrate-config .yolo-planning/config.json` runs without "Unknown command" error.

### Task 3: Wire migrate-orphaned-state into router.rs
**Files:** yolo-mcp-server/src/cli/router.rs
**Action:** Add a match arm `"migrate-orphaned-state"` that takes a planning dir path arg and calls `migrate_orphaned_state::migrate_orphaned_state(planning_dir)`. The function signature is `migrate_orphaned_state(planning_dir: &Path) -> Result<bool, String>`. Output "Migrated" if true, "No migration needed" if false.
**Acceptance:** `yolo migrate-orphaned-state .yolo-planning` runs without "Unknown command" error.

### Task 4: Add compile-context CLI subcommand
**Files:** yolo-mcp-server/src/cli/router.rs
**Action:** Add a match arm `"compile-context"` that accepts args: `{phase} {role} {phases_dir} [plan_path]`. For now, implement a minimal version that reads the same files as the MCP tool (ARCHITECTURE.md, STACK.md, CONVENTIONS.md, ROADMAP.md, REQUIREMENTS.md from .yolo-planning/) and writes the output to `.context-{role}.md` in the phases_dir. This mirrors what the MCP `compile_context` tool does but as a CLI command. The phase arg filters to phase-specific plan files if provided.
**Acceptance:** `yolo compile-context 1 lead .yolo-planning/phases/01-setup/` produces a `.context-lead.md` file (or outputs context to stdout).

### Task 5: Add install-mcp CLI subcommand
**Files:** yolo-mcp-server/src/cli/router.rs
**Action:** Add a match arm `"install-mcp"` that locates the `install-yolo-mcp.sh` script relative to the plugin root (using CLAUDE_PLUGIN_ROOT env var or finding it via the binary's own path) and executes it via `std::process::Command`. Pass through any args. The script already handles the full install flow (build, register, verify).
**Acceptance:** `yolo install-mcp` invokes the shell script without "Unknown command" error.
