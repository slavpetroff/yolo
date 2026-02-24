---
phase: 01
plan: 01
title: "Add toml_edit dep and sync Cargo.toml version to 2.9.5"
wave: 1
depends_on: []
must_haves:
  - "toml_edit added to Cargo.toml dependencies"
  - "Cargo.toml package version synced from 2.7.1 to 2.9.5"
  - "cargo check passes with new dependency"
---

# Plan 01: Add toml_edit dep and sync Cargo.toml version

**Files modified:** `yolo-mcp-server/Cargo.toml`

This plan touches only Cargo.toml. It adds the toml_edit dependency and fixes the out-of-sync version field.

## Task 1: Add toml_edit dependency to Cargo.toml

**Files:** `yolo-mcp-server/Cargo.toml`

**What to do:**
1. In `yolo-mcp-server/Cargo.toml`, change line 3 from `version = "2.7.1"` to `version = "2.9.5"`.
2. Add `toml_edit = "0.22"` to the `[dependencies]` section (alphabetical order, after `sysinfo`).
3. Run `cargo check` from the `yolo-mcp-server/` directory to verify the dependency resolves and the project compiles.

**Commit:** `fix(cargo): sync Cargo.toml version to 2.9.5 and add toml_edit dep`
