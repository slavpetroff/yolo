# Plan 14 Summary: Migrate utility scripts to native Rust

## Status: COMPLETE

## Tasks Completed: 5/5

### Task 1: Implement bump_version module
- **File**: `yolo-mcp-server/src/commands/bump_version.rs` (new)
- **Commit**: `feat(commands): implement bump_version module with verify and offline modes`
- Reads VERSION, plugin.json, marketplace.json; compares all versions in --verify mode. Default mode: fetch remote VERSION via reqwest (5s timeout), take max, increment patch, write to all files via serde_json. --offline skips fetch.
- **Tests**: unit tests for version parsing, comparison, increment, verify sync/mismatch

### Task 2: Implement help_output module
- **File**: `yolo-mcp-server/src/commands/help_output.rs` (new)
- **Commit**: `feat(commands): implement help_output module with CLI registration`
- Scans `commands/*.md` files, parses YAML frontmatter (name, category, description, argument-hint). Groups by category, formats box output with version. Pure Rust (no awk/sed).
- **Tests**: 13 unit tests

### Task 3: Implement doctor_cleanup module
- **File**: `yolo-mcp-server/src/commands/doctor_cleanup.rs` (new)
- **Commit**: (included in help_output commit)
- Two modes: scan (report issues) and cleanup (fix issues). Scans stale teams, orphaned processes (ps -eo), dangling PIDs (libc::kill), stale markers. Delegates to clean_stale_teams for team cleanup.
- **Tests**: 13 unit tests

### Task 4: Implement auto_repair and rollout_stage modules
- **Files**: `yolo-mcp-server/src/commands/auto_repair.rs` (new), `yolo-mcp-server/src/commands/rollout_stage.rs` (new)
- **Commit**: `feat(commands): implement auto_repair and rollout_stage modules`
- auto_repair: Gated by v2_hard_gates. Repairable: contract_compliance, required_checks. Non-repairable: escalate immediately. Max 2 retries. Emits task_blocked event on final failure.
- rollout_stage: 3 actions (check/advance/status). Default stages: canary/partial/full. Counts completed phases from event log. Applies stage-specific flags to config.json.
- **Tests**: 9 + 15 = 24 unit tests

### Task 5: Register CLI commands and add tests
- **Files**: `yolo-mcp-server/src/commands/mod.rs`, `yolo-mcp-server/src/cli/router.rs`
- **Commit**: (wired in help_output and auto_repair commits)
- Registered: `yolo help-output`, `yolo bump-version`, `yolo doctor`, `yolo auto-repair`, `yolo rollout`
- All modules in mod.rs, all CLI routes in router.rs

## Metrics
- **New files**: 5 (bump_version.rs, help_output.rs, doctor_cleanup.rs, auto_repair.rs, rollout_stage.rs)
- **New tests**: 50+ (across all modules)
- **Commits**: 3
- **Shell-outs eliminated**: 5 (bump-version.sh, help-output.sh, doctor-cleanup.sh, auto-repair.sh, rollout-stage.sh)
