---
phase: 01
plan: 04
title: "Extend bump_version.rs with TOML support and --major/--minor flags"
status: complete
tasks_completed: 5
tasks_total: 5
commit_hashes: ["de9af75"]
files_changed:
  - yolo-mcp-server/src/commands/bump_version.rs
---

# Summary: Plan 04 — Extend bump_version.rs with TOML and flags

## What Was Built

Extended `bump_version.rs` with TOML read/write support for Cargo.toml via `toml_edit`, added `--major`/`--minor` CLI flags, removed deleted `.claude-plugin/marketplace.json` from version tracking, and added 6 new tests (16 total per binary).

## Files Modified

- `yolo-mcp-server/src/commands/bump_version.rs` — +202 / -23 lines

## Changes

### Task 1: TOML read/write helpers
- `read_toml_version()` — reads `package.version` from TOML via `toml_edit::DocumentMut`
- `write_toml_version()` — writes version preserving TOML formatting

### Task 2: VersionFiles updated
- Added `toml_files: Vec<&'static str>` field to `VersionFiles` struct
- Added `yolo-mcp-server/Cargo.toml` to tracked files
- Removed `.claude-plugin/marketplace.json` from `json_files`

### Task 3: TOML integrated into verify and bump flows
- `verify_versions()` now checks Cargo.toml version alongside JSON files
- `bump_version()` now writes new version to Cargo.toml

### Task 4: --major and --minor flags
- `increment_major()`: X.Y.Z → (X+1).0.0
- `increment_minor()`: X.Y.Z → X.(Y+1).0
- `execute()` parses flags, rejects both together
- Response includes `bump_type` field ("patch", "minor", or "major")

### Task 5: Tests (32 total, 6 new)
- Updated `setup_test_env()`, `test_bump_offline` for new signature and Cargo.toml
- New: `test_increment_major`, `test_increment_minor`, `test_bump_major_flag`, `test_bump_minor_flag`, `test_toml_read_write`, `test_major_minor_conflict`

## Deviations

None. All 5 tasks implemented as specified in the plan.

## Verification
- `cargo test -- bump_version`: 32 passed, 0 failed
- `cargo clippy`: no new warnings from bump_version.rs
