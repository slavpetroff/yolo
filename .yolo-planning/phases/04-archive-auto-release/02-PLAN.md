---
phase: "04"
plan: "02"
title: "gh release create step in release-suite"
wave: 1
depends_on: ["04-01"]
must_haves:
  - "release-suite adds Step 6: gh release create after push"
  - "Changelog body passed via --notes flag from extract-changelog output"
  - "Gated by auto_push config: never = skip release, always/after_phase = create release"
  - "dry-run mode reports what would happen without creating release"
  - "--no-push also skips gh release (can't release without pushing)"
  - "Missing gh CLI handled gracefully (warn, continue)"
  - "Tests cover: gh-release step in dry-run, gh-release skipped when no-push"
---

# Plan 02: gh release create step in release-suite

Add a GitHub Release creation step (Step 6) to release-suite that runs `gh release create` after push, using changelog body as release notes.

## Task 1

**Files:** `yolo-mcp-server/src/commands/release_suite.rs`

**What to do:**

1. Add `use crate::commands::extract_changelog;` import.
2. After the existing Step 5 (git push) success block and before the success response, add Step 6 — GitHub Release:
   - Skip if `dry_run`, `no_push`, or push step was skipped/failed. Push step status in `steps` array: check last step's status.
   - Call `extract_changelog::execute(&["yolo".into(), "extract-changelog".into()], cwd)` to get changelog body.
   - Parse the JSON result. Extract `delta.body` and `delta.version`.
   - If `delta.found == false` or body is empty: use a default body like `"Release v{new_version}"`.
   - Run `gh release create v{new_version} --title "v{new_version}" --notes "{body}"` via `Command::new("gh")`.
   - If `gh` is not found (command error): push a warn step `{"name":"gh-release","status":"warn","detail":"gh CLI not found"}` and continue (don't fail the release).
   - If `gh` exits non-zero: push a warn step with stderr detail and continue.
   - If success: push `{"name":"gh-release","status":"ok","url":"..."}` — extract URL from gh stdout if available.
3. For `dry_run` mode: push `{"name":"gh-release","status":"dry-run","detail":"Would create release v{new_version}"}`.
4. For `no_push` mode: push `{"name":"gh-release","status":"skipped","detail":"Skipped (no push)"}`.

## Task 2

**Files:** `yolo-mcp-server/src/commands/release_suite.rs`

**What to do:**

1. Add/update tests:
   - `test_dry_run_returns_ok` — verify gh-release step appears in steps array with "dry-run" status.
   - `test_no_push_skips_gh_release` — new test confirming gh-release has "skipped" status when --no-push.
   - `test_response_schema` — update to expect 6 steps instead of 5.
   - `test_full_release_no_push` — update to expect 6 steps.

## Task 3

**Files:** `yolo-mcp-server/src/commands/release_suite.rs`

**What to do:**

1. Run `cargo test -p yolo-mcp-server release_suite` and confirm all tests pass.
2. Run `cargo build --release -p yolo-mcp-server` and confirm clean build.
3. Fix any compilation or test failures.

**Commit:** `feat(04-02): add gh release create step to release-suite`
