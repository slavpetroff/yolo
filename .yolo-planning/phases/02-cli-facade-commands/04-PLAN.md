---
phase: 02
plan: 04
title: "bootstrap-all facade command"
wave: 1
depends_on: []
must_haves:
  - "Calls project, requirements, roadmap, state sequentially"
  - "Returns aggregated results from all 4 sub-commands"
  - "Follows standard JSON schema with ok, cmd, delta, elapsed_ms"
  - "Optional args for core-value, research file, milestone name"
  - "Cargo clippy clean"
---

# Plan 04: bootstrap-all facade command

**Files modified:** `yolo-mcp-server/src/commands/bootstrap_all.rs`

Implements `yolo bootstrap-all <output_dir> <name> <description> <phases_json> <discovery_json> [--core-value V] [--research R] [--milestone M]` that orchestrates all 4 bootstrap sub-commands.

## Task 1: Create bootstrap_all.rs with argument parsing

**Files:** `yolo-mcp-server/src/commands/bootstrap_all.rs`

**What to do:**
1. Create `yolo-mcp-server/src/commands/bootstrap_all.rs`
2. Add imports: `use std::path::Path; use std::time::Instant; use serde_json::{json, Value};`
3. Import: `use crate::commands::{bootstrap_project, bootstrap_requirements, bootstrap_roadmap, bootstrap_state};`
4. Implement `pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String>`
5. Parse positional args: `args[2]` = output_dir, `args[3]` = name, `args[4]` = description, `args[5]` = phases_json_path, `args[6]` = discovery_json_path
6. Parse optional flags: scan for `--core-value` (next arg), `--research` (next arg), `--milestone` (next arg, default to name)
7. Validate: at least 7 positional+command args required

## Task 2: Call bootstrap sub-commands sequentially

**Files:** `yolo-mcp-server/src/commands/bootstrap_all.rs`

**What to do:**
1. Derive output paths from output_dir:
   - project_path = `{output_dir}/PROJECT.md`
   - requirements_path = `{output_dir}/REQUIREMENTS.md`
   - roadmap_path = `{output_dir}/ROADMAP.md`
   - state_path = `{output_dir}/STATE.md`
2. Call each in order (each depends on prior output):
   a. `bootstrap_project::execute(&["project", project_path, name, description, core_value?], cwd)`
   b. `bootstrap_requirements::execute(&["requirements", requirements_path, discovery_json, research?], cwd)`
   c. Count phases from phases_json to get phase_count
   d. `bootstrap_roadmap::execute(&["roadmap", roadmap_path, name, phases_json], cwd)`
   e. `bootstrap_state::execute(&["state", state_path, name, milestone, phase_count_str], cwd)`
3. For each call: parse JSON response, check ok field. If any fails, stop and report partial failure
4. Collect results from each sub-command

## Task 3: Build unified response and add tests

**Files:** `yolo-mcp-server/src/commands/bootstrap_all.rs`

**What to do:**
1. Build final response:
```json
{
  "ok": all_passed,
  "cmd": "bootstrap-all",
  "delta": {
    "name": name,
    "output_dir": output_dir,
    "steps": {
      "project": { sub-response delta },
      "requirements": { sub-response delta },
      "roadmap": { sub-response delta },
      "state": { sub-response delta }
    },
    "files_created": ["PROJECT.md", "REQUIREMENTS.md", "ROADMAP.md", "STATE.md"],
    "phase_count": N
  },
  "elapsed_ms": elapsed
}
```
2. Add `#[cfg(test)] mod tests`:
   - Test: full success with valid inputs creates all 4 files and returns ok=true
   - Test: missing args returns Err with usage
   - Test: invalid phases_json returns error at roadmap step
   - Test: response has `cmd: "bootstrap-all"` and `elapsed_ms`
   - Test: --milestone flag sets custom milestone name in state output
3. Use tempfile::tempdir. Create discovery.json and phases.json fixtures in test

**Commit:** `feat(yolo): add bootstrap-all facade command`
