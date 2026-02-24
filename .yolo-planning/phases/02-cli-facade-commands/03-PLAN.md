---
phase: 02
plan: 03
title: "release-suite facade command"
wave: 1
depends_on: []
must_haves:
  - "Orchestrates bump, changelog, git add, commit, tag, push"
  - "Supports --dry-run that writes nothing"
  - "Supports --no-push to skip push step"
  - "Partial failure reports and stops"
  - "Auto-includes Cargo.toml and Cargo.lock in git add"
---

# Plan 03: release-suite facade command

**Files modified:** `yolo-mcp-server/src/commands/release_suite.rs`

Implements `yolo release-suite [--major|--minor] [--dry-run] [--no-push]` that orchestrates the full release workflow.

## Task 1: Create release_suite.rs with flag parsing

**Files:** `yolo-mcp-server/src/commands/release_suite.rs`

**What to do:**
1. Create `yolo-mcp-server/src/commands/release_suite.rs`
2. Add imports: `use std::path::Path; use std::time::Instant; use std::process::Command; use serde_json::{json, Value};`
3. Import: `use crate::commands::bump_version;`
4. Implement `pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String>`
5. Parse flags from args: `--major`, `--minor`, `--dry-run`, `--no-push`, `--offline`
6. Validate: `--major` and `--minor` are mutually exclusive (return Err)

## Task 2: Implement bump-version step

**Files:** `yolo-mcp-server/src/commands/release_suite.rs`

**What to do:**
1. Build args for bump_version: `["yolo", "bump-version"]` + conditionally add `--major`, `--minor`, `--offline`
2. In dry-run mode: call `bump_version::execute` with `--verify` instead to check current state, then compute what the new version WOULD be without writing
3. In normal mode: call `bump_version::execute` to actually bump
4. Parse the JSON response, extract `delta.new_version` and `delta.old_version`
5. If bump fails, build error response and return immediately (partial failure = stop)
6. Track step results in a `Vec<Value>` for the final response

## Task 3: Implement git operations (add, commit, tag, push)

**Files:** `yolo-mcp-server/src/commands/release_suite.rs`

**What to do:**
1. Define the release files to stage: `VERSION`, `.claude-plugin/plugin.json`, `marketplace.json`, `yolo-mcp-server/Cargo.toml`, `yolo-mcp-server/Cargo.lock`, `CHANGELOG.md`
2. In dry-run mode: report what WOULD happen for each step without executing
3. In normal mode, execute sequentially with partial-failure stops:
   a. `git add` all release files that exist in cwd
   b. `git commit -m "chore: release v{new_version}"`
   c. `git tag v{new_version}`
   d. If `--no-push` NOT set: `git push && git push --tags`
4. For each git command: run via `std::process::Command`, check exit code
5. If any step fails: record the step name and stderr in response, set ok=false, return immediately
6. Build step-by-step results tracking which steps completed

## Task 4: Build unified response and add tests

**Files:** `yolo-mcp-server/src/commands/release_suite.rs`

**What to do:**
1. Build final response:
```json
{
  "ok": all_steps_passed,
  "cmd": "release-suite",
  "delta": {
    "old_version": "X.Y.Z",
    "new_version": "X.Y.Z+1",
    "bump_type": "patch|minor|major",
    "dry_run": true|false,
    "steps": [
      {"name": "bump-version", "status": "ok|fail|skipped", "detail": "..."},
      {"name": "git-add", "status": "...", "files": [...]},
      {"name": "git-commit", "status": "...", "message": "..."},
      {"name": "git-tag", "status": "...", "tag": "..."},
      {"name": "git-push", "status": "...|skipped"}
    ]
  },
  "elapsed_ms": elapsed
}
```
2. Add `#[cfg(test)] mod tests`:
   - Test: `--dry-run` returns ok=true with all steps showing "skipped" or "dry-run"
   - Test: `--major --minor` returns Err
   - Test: missing VERSION file returns error in bump step
   - Test: response schema has `cmd: "release-suite"`, `elapsed_ms`, `delta.steps`
   - Test: `--no-push` skips push step

**Commit:** `feat(yolo): add release-suite facade command`
