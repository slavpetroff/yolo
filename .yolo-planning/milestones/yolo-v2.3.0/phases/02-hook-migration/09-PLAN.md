---
phase: 2
plan: 09
title: "Migrate state management scripts to native Rust (snapshot-resume, persist-state, recover-state, compile-rolling-summary)"
wave: 2
depends_on: [1, 2]
must_haves:
  - "snapshot_resume save/restore with max 10 snapshots per phase and pruning"
  - "persist_state extracts project-level sections from archived STATE.md"
  - "recover_state rebuilds execution-state.json from event log + SUMMARY.md files"
  - "compile_rolling_summary generates condensed digest from completed SUMMARY.md files"
  - "All use std::fs and serde — no jq, no awk, no sed, no Command::new(bash)"
---

## Task 1: Implement snapshot_resume module

**Files:** `yolo-mcp-server/src/commands/snapshot_resume.rs` (new)

**Acceptance:** Two public functions: `save(phase, state_path, agent_role, trigger, planning_dir) -> Result<String, String>` and `restore(phase, preferred_role, planning_dir) -> Result<String, String>`. Save: check `v3_snapshot_resume` flag in config.json, read execution state JSON, get git log via `Command::new("git").args(["log", "--oneline", "-5"])`, build snapshot JSON (snapshot_ts, phase, execution_state, recent_commits, agent_role, trigger), write to `.snapshots/{phase}-{timestamp}.json`, prune oldest when >10 per phase. Restore: find latest snapshot matching phase (prefer matching role), return path. Also expose CLI entry point for `yolo snapshot-resume <save|restore> <phase> [args...]`.

## Task 2: Implement persist_state module

**Files:** `yolo-mcp-server/src/commands/persist_state.rs` (new)

**Acceptance:** `persist_state::execute(archived_path, output_path, project_name) -> Result<String, String>`. Extract project-level sections from archived STATE.md: `## Decisions` (including `### Skills`), `## Todos`, `## Blockers`, `## Codebase Profile`. Section extraction via `str::lines()` iterator: find `## Heading` (case-insensitive), collect until next `## `. Special handling for `## Decisions` and `## Key Decisions` (merge both). Write minimal root STATE.md with header, project name, and preserved sections. Empty sections get placeholder text. Pure `std::fs::read_to_string` + `std::fs::write`.

## Task 3: Implement recover_state module

**Files:** `yolo-mcp-server/src/commands/recover_state.rs` (new)

**Acceptance:** `recover_state::execute(phase, phases_dir) -> Result<String, String>`. Check `v3_event_recovery` flag. Find phase directory by padded phase number. Collect plan IDs from `*-PLAN.md` files, extract title/wave from frontmatter. Check SUMMARY.md existence for completion status. Cross-reference with event-log.jsonl for `plan_end` events. Build execution state JSON: phase, phase_name, status (complete/failed/running/pending), wave, total_waves, plans array. Output JSON to stdout. Also expose CLI entry point for `yolo recover-state <phase> [phases-dir]`.

## Task 4: Implement compile_rolling_summary module

**Files:** `yolo-mcp-server/src/commands/compile_rolling_summary.rs` (new)

**Acceptance:** `compile_rolling_summary::execute(phases_dir, output_path) -> Result<String, String>`. Discover completed `*-SUMMARY.md` files (status: complete/completed in YAML frontmatter). Single-phase no-op: if total SUMMARY count <= 1, write placeholder. Extract from each: phase, plan, title, deviations, commit_hashes (first only), `## What Was Built` (first 3 lines), `## Files Modified` (up to 5 entries). Build condensed entries: `## Phase N Plan M: Title\nBuilt: ...\nFiles: ...\nDeviations: N\nCommit: hash`. Assemble with 200-line cap. Write atomically (temp + rename). Also expose CLI entry point.

## Task 5: Register CLI commands and add tests

**Files:** `yolo-mcp-server/src/commands/mod.rs`, `yolo-mcp-server/src/cli/router.rs`, `yolo-mcp-server/src/commands/snapshot_resume.rs` (append tests), `yolo-mcp-server/src/commands/persist_state.rs` (append tests), `yolo-mcp-server/src/commands/recover_state.rs` (append tests)

**Acceptance:** Register `yolo snapshot-resume`, `yolo recover-state`, `yolo rolling-summary` in router. Tests cover: snapshot save creates file with correct fields, snapshot prune keeps max 10, snapshot restore prefers matching role, section extraction from STATE.md, decisions merge (both heading variants), recover-state with mixed plan statuses, rolling summary with 3 completed plans, 200-line cap enforcement. `cargo test` passes.
