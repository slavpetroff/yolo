---
phase: 01
plan: 03
title: "Enhance help command with per-command help and error recovery"
wave: 1
depends_on: []
must_haves:
  - yolo help-output supports per-command help (e.g., yolo help-output init)
  - Error recovery guidance is included for common failure scenarios
---

## Tasks

### Task 1: Add per-command help dispatch to help_output.rs
**Files:** yolo-mcp-server/src/commands/help_output.rs
**Action:** Update the `execute` function to check if a subcommand argument is provided (e.g., `yolo help-output init`). If a subcommand is given, output command-specific help text instead of the general help listing. Add a lookup table or match block mapping each major command (init, vibe, config, todo, map, status, help) to a brief description + common flags + example usage.
**Acceptance:** `yolo help-output init` outputs init-specific help text; `yolo help-output` (no args) still outputs the full command listing.

### Task 2: Add error recovery guidance to help_output.rs
**Files:** yolo-mcp-server/src/commands/help_output.rs
**Action:** Add a "Troubleshooting" section to the general help output (when no subcommand is given). Include common error scenarios and recovery steps:
- "Not initialized" -> Run /yolo:init
- "No plans found" -> Run /yolo:vibe --plan N
- "MCP server not responding" -> Run yolo install-mcp or check claude mcp list
- "Build failed" -> Check Rust toolchain with rustc --version
- "Config migration failed" -> Check .yolo-planning/config.json is valid JSON
**Acceptance:** `yolo help-output` includes a "Troubleshooting" section with at least 4 error recovery entries.

### Task 3: Update help.md to document per-command help
**Files:** commands/help.md
**Action:** Update the help command markdown to mention that users can get per-command help. Add examples showing `/yolo:help init`, `/yolo:help vibe`, etc. Document that the help command now accepts an optional subcommand argument.
**Acceptance:** commands/help.md mentions per-command help capability and shows example usage.
