---
phase: 1
plan: 02
title: "Dead Code & Unused Imports"
wave: 1
depends_on: []
must_haves:
  - REQ-01
---

# Plan 02: Dead Code & Unused Imports

Remove all unused imports, dead code, and fix minor logic warnings (never-read assignment, unnecessary mut).

## Files Modified (7 — disjoint from Plans 01/03/04)
- `src/cli/router.rs`
- `src/commands/hard_gate.rs`
- `src/commands/list_todos.rs`
- `src/commands/token_baseline.rs`
- `src/commands/resolve_model.rs`
- `src/commands/commit_lint.rs`
- `src/commands/bootstrap_claude.rs`

## Task 1: Remove unused imports from router.rs and hard_gate.rs

**Description:**
- `router.rs:5` — remove `use std::sync::atomic::Ordering;`
- `hard_gate.rs:3` — remove `PathBuf` from `use std::path::{Path, PathBuf};`

**Files:** `src/cli/router.rs`, `src/commands/hard_gate.rs`
**Commit:** `fix(imports): remove unused Ordering and PathBuf imports`
**Verify:** `cargo clippy 2>&1 | grep -E "(router|hard_gate).*unused import"` returns empty

## Task 2: Remove unused imports from list_todos.rs and token_baseline.rs

**Description:**
- `list_todos.rs:4` — remove `Datelike` from `use chrono::{NaiveDate, Utc, Datelike};`
- `token_baseline.rs:3` — remove `DateTime` from `use chrono::{DateTime, Utc};`

**Files:** `src/commands/list_todos.rs`, `src/commands/token_baseline.rs`
**Commit:** `fix(imports): remove unused Datelike and DateTime imports`
**Verify:** `cargo clippy 2>&1 | grep -E "(list_todos|token_baseline).*unused import"` returns empty

## Task 3: Remove dead code in resolve_model.rs and commit_lint.rs

**Description:**
- `resolve_model.rs:64` — `Model::as_str()` is never used. Remove the method.
- `commit_lint.rs:88` — `validate_subject()` is never used. Remove the function.

**Files:** `src/commands/resolve_model.rs`, `src/commands/commit_lint.rs`
**Commit:** `refactor(commands): remove dead code as_str and validate_subject`
**Verify:** `cargo clippy 2>&1 | grep -E "(resolve_model|commit_lint).*(never used|dead_code)"` returns empty

## Task 4: Fix never-read assignment in bootstrap_claude.rs

**Description:** At line 161, `rows_inserted = true` is assigned but never read afterward (overwritten or unused before next read). Remove the assignment or restructure the logic to eliminate the warning.

**Files:** `src/commands/bootstrap_claude.rs:161`
**Commit:** `fix(commands): remove never-read rows_inserted assignment in bootstrap_claude`
**Verify:** `cargo clippy 2>&1 | grep "bootstrap_claude.*never read"` returns empty

## Task 5: Remove unnecessary mut in list_todos.rs

**Description:** At line 150, `let mut text = ...` — the variable is never mutated. Remove the `mut` qualifier.

**Files:** `src/commands/list_todos.rs:150`
**Commit:** `fix(commands): remove unnecessary mut in list_todos`
**Verify:** `cargo clippy 2>&1 | grep "list_todos.*does not need to be mutable"` returns empty
