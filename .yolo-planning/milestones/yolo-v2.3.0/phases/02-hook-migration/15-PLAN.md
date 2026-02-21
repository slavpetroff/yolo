---
phase: 2
plan: 15
title: "Migrate archive and index scripts to native Rust (generate-gsd-index, generate-incidents, artifact-registry, infer-gsd-summary)"
wave: 2
depends_on: [1, 2]
must_haves:
  - "generate_gsd_index produces INDEX.json for archived GSD projects"
  - "generate_incidents produces INCIDENTS.md from event log blocker/rejection events"
  - "artifact_registry provides register/query/list for JSONL artifact tracking"
  - "All use serde_json for JSON, std::fs for file I/O — no jq, no Command::new(bash)"
---

## Task 1: Implement generate_gsd_index module

**Files:** `yolo-mcp-server/src/commands/generate_gsd_index.rs` (new)

**Acceptance:** `generate_gsd_index::execute(archive_dir) -> Result<(String, i32), String>`. Guard: exit if `gsd-archive/` doesn't exist. Extract GSD version from `config.json`. Scan `phases/` subdirectories: extract phase number and slug from dir name, count `*-PLAN.md` and `*-SUMMARY.md` files, determine status (complete if plan_count == summary_count > 0). Extract milestones from `ROADMAP.md` `## ` headings. Build and write `INDEX.json` with imported_at, gsd_version, phases_total, phases_complete, milestones, quick_paths, phases array. Also expose CLI entry point.

## Task 2: Implement generate_incidents module

**Files:** `yolo-mcp-server/src/commands/generate_incidents.rs` (new)

**Acceptance:** `generate_incidents::execute(phase) -> Result<(String, i32), String>`. Read event-log.jsonl, filter `task_blocked` and `task_completion_rejected` events for given phase. Build markdown report: `# Phase N Incidents`, total count, `## Blockers` table (Time, Task, Reason, Next Action), `## Rejections` table (Time, Task, Reason). Write to `{phase_dir}/{padded}-INCIDENTS.md`. Output path or empty if no incidents. Exit 0 always. Also expose CLI entry point.

## Task 3: Implement artifact_registry module

**Files:** `yolo-mcp-server/src/commands/artifact_registry.rs` (new)

**Acceptance:** `artifact_registry::execute(command, args) -> Result<(String, i32), String>`. Gated by `v2_two_phase_completion`. Commands: `register` (compute SHA-256 checksum via sha2 crate, append JSON line to `.artifacts/registry.jsonl`), `query` (read registry, filter by path, return all matching entries), `list` (read all entries, optional phase filter). Output JSON: `{result, count, entries}` for query/list, `{result, path, checksum}` for register. Also expose CLI entry point.

## Task 4: Implement infer_gsd_summary module

**Files:** `yolo-mcp-server/src/commands/infer_gsd_summary.rs` (new)

**Acceptance:** `infer_gsd_summary::execute(archive_dir) -> Result<(String, i32), String>`. Read GSD archive structure. Extract: project name from PROJECT.md, milestone info from ROADMAP.md, phase count and completion status from INDEX.json (if exists) or scan phases directly. Build condensed summary string: project name, total phases, completed phases, key milestones. Output summary to stdout. Also expose CLI entry point.

## Task 5: Register CLI commands and add tests

**Files:** `yolo-mcp-server/src/commands/mod.rs`, `yolo-mcp-server/src/cli/router.rs`, `yolo-mcp-server/src/commands/generate_gsd_index.rs` (append tests), `yolo-mcp-server/src/commands/generate_incidents.rs` (append tests), `yolo-mcp-server/src/commands/artifact_registry.rs` (append tests)

**Acceptance:** Register `yolo gsd-index`, `yolo incidents`, `yolo artifact`, `yolo gsd-summary` in router. Tests cover: GSD index generation with mixed phase statuses, incident report from blocked/rejected events, artifact register with checksum, artifact query by path, artifact list with phase filter, empty incident report (no events). `cargo test` passes.
