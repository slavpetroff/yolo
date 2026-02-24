---
phase: "03"
plan: "01"
title: "commit_hashes git existence validation"
wave: 1
depends_on: []
must_haves:
  - "git rev-parse --verify validates each commit hash exists in repo"
  - "Non-git-repo gracefully skips validation with warn status"
  - "Existing regex check preserved as first-pass filter"
  - "Existing tests still pass"
---

# Plan 01: commit_hashes git existence validation

Add `git rev-parse --verify {hash}^{commit}` existence check to verify-plan-completion Check 4, after the existing regex filter passes.

## Task 1

**Files:** `yolo-mcp-server/src/commands/verify_plan_completion.rs`

**What to do:**

1. Add `use std::process::Command;` to the imports at the top of the file.
2. Rename the `_cwd` parameter in `pub fn execute(...)` to `cwd` (remove underscore prefix) so it can be used for git calls.

## Task 2

**Files:** `yolo-mcp-server/src/commands/verify_plan_completion.rs`

**What to do:**

1. Inside Check 4, in the branch where `invalid.is_empty()` is true (line 148), before pushing the pass check, add a git existence validation loop:
   - For each hash in `hashes`, run `Command::new("git").args(["rev-parse", "--verify", &format!("{}^{{commit}}", h)]).current_dir(cwd).output()`.
   - First check if we are in a git repo: run `git rev-parse --is-inside-work-tree` with `current_dir(cwd)`. If this fails (not a git repo), push a `"warn"` status check with detail "Not a git repo, skipping existence check" and `fixable_by: "none"`, then skip the per-hash loop.
   - Collect hashes where rev-parse fails (non-zero exit or command error) into a `not_found` vec.
   - If `not_found` is empty, push the existing pass check (N valid hashes).
   - If `not_found` is non-empty, push a fail check with detail listing the not-found hashes and `fixable_by: "dev"`, set `all_pass = false`.

## Task 3

**Files:** `yolo-mcp-server/src/commands/verify_plan_completion.rs`

**What to do:**

1. Add a test `test_commit_hash_not_in_repo` that:
   - Creates a tempdir, writes a valid SUMMARY with `commit_hashes: ["abc1234"]` and a matching PLAN.
   - Calls `execute(...)` with the tempdir as cwd (not a git repo).
   - Asserts exit code 0 (warn, not fail — non-git-repo is graceful skip).
   - Asserts the `commit_hashes` check has status `"warn"` in the JSON output.
2. Add a test `test_commit_hash_in_real_git_repo` that:
   - Creates a tempdir, runs `git init`, creates a file, runs `git add . && git commit`.
   - Captures the real commit hash via `git rev-parse HEAD`.
   - Writes a SUMMARY with that real hash, writes a matching PLAN.
   - Calls `execute(...)` and asserts exit code 0, commit_hashes status `"pass"`.

## Task 4

**Files:** `yolo-mcp-server/src/commands/verify_plan_completion.rs`

**What to do:**

1. Run `cargo test -p yolo-mcp-server --lib commands::verify_plan_completion` and confirm all tests pass (existing + new).
2. Fix any compilation or test failures.

**Commit:** `feat(03-01): add git rev-parse existence check for commit_hashes`
