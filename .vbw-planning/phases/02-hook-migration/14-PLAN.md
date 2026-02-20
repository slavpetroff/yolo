---
phase: 2
plan: 14
title: "Migrate utility scripts to native Rust (bump-version, help-output, doctor-cleanup, auto-repair, rollout-stage)"
wave: 3
depends_on: [1, 2, 8]
must_haves:
  - "bump_version bumps patch version across 4 files with GitHub version check"
  - "help_output generates formatted help from command frontmatter"
  - "doctor_cleanup scans and cleans stale teams, orphans, dangling PIDs, stale markers"
  - "auto_repair attempts bounded auto-repair on gate failure with max 2 retries"
  - "rollout_stage manages V3 flag rollout through 3 stages"
---

## Task 1: Implement bump_version module

**Files:** `yolo-mcp-server/src/commands/bump_version.rs` (new)

**Acceptance:** `bump_version::execute(args) -> Result<(String, i32), String>`. `--verify` mode: read VERSION, plugin.json, marketplace.json (both locations), compare all 4 versions, report mismatch and exit 1 if any differ. `--offline` mode: skip GitHub fetch. Default mode: fetch remote VERSION via `reqwest` or `ureq` crate (with 5s timeout, graceful fallback to local), take max of local/remote as base, increment patch, write to all 4 files. JSON files updated via serde_json (read, modify `.version` / `.plugins[0].version`, write back). Also expose CLI entry point.

## Task 2: Implement help_output module

**Files:** `yolo-mcp-server/src/commands/help_output.rs` (new)

**Acceptance:** `help_output::execute(plugin_root) -> Result<(String, i32), String>`. Resolve plugin_root: arg, CLAUDE_PLUGIN_ROOT env, or latest cached plugin dir. Scan `commands/*.md` files, parse YAML frontmatter for name, description, category, argument-hint. Group by category (lifecycle, monitoring, supporting, advanced, other). Format: box header with version, category sections with 42-char padded entries, footer with Getting Started. Output directly to stdout. Use `std::fs::read_dir` + `str::lines()` for parsing -- no awk/sed. Also expose CLI entry point.

## Task 3: Implement doctor_cleanup module

**Files:** `yolo-mcp-server/src/commands/doctor_cleanup.rs` (new)

**Acceptance:** `doctor_cleanup::execute(action, planning_dir) -> Result<(String, i32), String>`. Two modes: `scan` (report issues) and `cleanup` (fix issues). Scan functions: stale teams (reuse `clean_stale_teams` logic from Plan 08), orphaned processes (`Command::new("ps").args(["-eo", "pid,ppid,comm"])` then filter PPID=1 + "claude"), dangling PIDs (read `.agent-pids`, check liveness via `libc::kill`), stale markers (.watchdog-pid, .compaction-marker, .active-agent). Cleanup: delegate to respective clean functions, SIGTERM/SIGKILL for orphans, prune dead PIDs, remove stale markers. Output `category|item|detail` format. Also expose CLI entry point.

## Task 4: Implement auto_repair and rollout_stage modules

**Files:** `yolo-mcp-server/src/commands/auto_repair.rs` (new), `yolo-mcp-server/src/commands/rollout_stage.rs` (new)

**Acceptance:** `auto_repair::execute(gate_type, phase, plan, task, contract_path) -> Result<(String, i32), String>`. Gated by `v2_hard_gates`. Repairable gates: contract_compliance (regenerate contract), required_checks (re-run). Non-repairable: protected_file, commit_hygiene, artifact_persistence, verification_threshold (emit blocker event immediately). Max 2 retries. On final failure: emit `task_blocked` event via `log_event::log()`. Output JSON. `rollout_stage::execute(action, force_stage, dry_run) -> Result<(String, i32), String>`. Actions: check (report current stage), advance (enable flags for target stage), status (show all flags). Read `rollout-stages.json` for stage definitions. Count completed phases from event log. Apply flags to config.json. Also expose CLI entry points.

## Task 5: Register CLI commands and add tests

**Files:** `yolo-mcp-server/src/commands/mod.rs`, `yolo-mcp-server/src/cli/router.rs`, `yolo-mcp-server/src/commands/bump_version.rs` (append tests), `yolo-mcp-server/src/commands/doctor_cleanup.rs` (append tests), `yolo-mcp-server/src/commands/rollout_stage.rs` (append tests)

**Acceptance:** Register `yolo bump-version`, `yolo help`, `yolo doctor`, `yolo auto-repair`, `yolo rollout` in router. Tests cover: version verify sync check (pass/fail), version bump arithmetic, doctor scan output format, doctor cleanup stale marker removal, auto-repair repairable vs non-repairable gates, rollout stage detection from phase count, rollout advance dry-run. `cargo test` passes.
