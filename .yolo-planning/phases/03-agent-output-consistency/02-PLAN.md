---
phase: "03"
plan: "02"
title: "diff-against-plan --commits override flag"
wave: 1
depends_on: []
must_haves:
  - "--commits hash1,hash2 fully overrides frontmatter commit_hashes"
  - "Without --commits flag, existing behavior unchanged"
  - "Empty --commits value treated as flag-not-passed"
  - "Usage string updated to document the new flag"
---

# Plan 02: diff-against-plan --commits override flag

Add a `--commits` flag to diff-against-plan that overrides frontmatter `commit_hashes` with user-supplied comma-separated hashes.

## Task 1

**Files:** `yolo-mcp-server/src/commands/diff_against_plan.rs`

**What to do:**

1. Add a `parse_flag` helper function (copy the pattern from `qa_suite.rs` lines 141-148):
   ```rust
   fn parse_flag(args: &[String], flag: &str) -> Option<String> {
       let mut iter = args.iter();
       while let Some(arg) = iter.next() {
           if arg == flag {
               return iter.next().cloned();
           }
       }
       None
   }
   ```

## Task 2

**Files:** `yolo-mcp-server/src/commands/diff_against_plan.rs`

**What to do:**

1. In `execute()`, after the frontmatter-based `commit_hashes` extraction (around line 51) and before the `get_git_files()` call (line 54), add the `--commits` override logic:
   - Call `parse_flag(args, "--commits")` to get the optional override value.
   - If `Some(val)` and `val` is non-empty: split on `,`, trim each element, filter out empties, collect into a `Vec<String>`, and replace `commit_hashes` with this vec.
   - If `None` or empty string: keep the frontmatter-derived `commit_hashes` unchanged.
2. Update the usage error string to: `"Usage: yolo diff-against-plan <summary_path> [--commits hash1,hash2]"`.
3. Update the doc comment at the top of `execute()` to document the `--commits` flag.

## Task 3

**Files:** `yolo-mcp-server/src/commands/diff_against_plan.rs`

**What to do:**

1. Add a test `test_commits_flag_overrides_frontmatter` that:
   - Creates a SUMMARY with `commit_hashes: ["aaa1111"]` in frontmatter and a `## Files Modified` section.
   - Calls `execute()` with args including `--commits bbb2222,ccc3333`.
   - Asserts the response does NOT use the frontmatter hash `aaa1111` (the actual files come from git show on the override hashes, not the frontmatter ones).
2. Add a test `test_empty_commits_flag_uses_frontmatter` that:
   - Creates a SUMMARY with `commit_hashes: []` in frontmatter.
   - Calls `execute()` with args including `--commits ""` (empty value).
   - Asserts behavior is same as no flag (empty commit_hashes from frontmatter).

## Task 4

**Files:** `yolo-mcp-server/src/commands/diff_against_plan.rs`

**What to do:**

1. Run `cargo test -p yolo-mcp-server --lib commands::diff_against_plan` and confirm all tests pass (existing + new).
2. Fix any compilation or test failures.

**Commit:** `feat(03-02): add --commits override flag to diff-against-plan`
