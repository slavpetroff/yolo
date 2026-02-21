---
phase: 1
plan: 03
title: "Fix lock exit code and delta-files empty response ambiguity"
wave: 1
depends_on: []
must_haves:
  - "yolo lock acquire exits 2 on conflict (not 1)"
  - "yolo delta-files returns distinguishable JSON for empty vs no-strategy-worked"
---

## Task 1: Fix lock_lite conflict exit code from 1 to 2
**Files:** `yolo-mcp-server/src/commands/lock_lite.rs`
**Acceptance:** When `yolo lock acquire <resource>` encounters a conflict (resource already held by another owner), the command exits with code 2 instead of code 1. The `check` action with conflicts also exits 2. Release with wrong owner stays at exit code 1 (non-fatal).

### Implementation Details

In `execute()` at line 184, change:
```rust
Err(v) => Ok((v.to_string(), 1)),
```
to:
```rust
Err(v) => Ok((v.to_string(), 2)),
```

For `check` action at line 200, change:
```rust
let code = if result.get("has_conflicts")... { 1 } else { 0 };
```
to:
```rust
let code = if result.get("has_conflicts")... { 2 } else { 0 };
```

Leave the `release` wrong-owner error at exit code 1 (it's a different class of error).

## Task 2: Update lock_lite unit tests for exit code 2
**Files:** `yolo-mcp-server/src/commands/lock_lite.rs`
**Acceptance:** `test_cli_acquire_release` and any test asserting conflict exit code 1 are updated to expect exit code 2. All tests pass.

### Implementation Details

The existing `test_acquire_conflict` test uses the `acquire()` function directly (returns `Result`), so it doesn't test exit codes. Add a new test `test_cli_acquire_conflict_exit_code`:
```rust
#[test]
fn test_cli_acquire_conflict_exit_code() {
    let dir = setup_test_env(true);
    // First acquire
    let args1 = vec!["yolo".into(), "lock".into(), "acquire".into(), "res".into(), "--owner=dev-1".into()];
    let (_, code1) = execute(&args1, dir.path()).unwrap();
    assert_eq!(code1, 0);
    // Conflict
    let args2 = vec!["yolo".into(), "lock".into(), "acquire".into(), "res".into(), "--owner=dev-2".into()];
    let (_, code2) = execute(&args2, dir.path()).unwrap();
    assert_eq!(code2, 2);
}
```

## Task 3: Make delta-files return structured JSON for empty results
**Files:** `yolo-mcp-server/src/commands/delta_files.rs`
**Acceptance:** When delta-files returns no files: (a) if git strategies ran but found nothing → return `{"files":[],"strategy":"git","note":"no uncommitted or recent changes"}` with exit code 0; (b) if no git and no SUMMARY.md files → return `{"files":[],"strategy":"none","note":"no sources available"}` with exit code 0. When files are found, return newline-separated file list as before (backward compatible).

### Implementation Details

Modify `execute()` (lines 14-39) to return JSON when no files are found:

```rust
// Strategy 1: git-based
if is_git_repo(cwd) {
    if let Some(files) = git_strategy(cwd) {
        if !files.is_empty() {
            return Ok((files, 0));
        }
    }
    // Git ran but found nothing
    if phase_dir.is_dir() {
        let files = summary_strategy(&phase_dir);
        if !files.is_empty() {
            return Ok((files, 0));
        }
    }
    return Ok((r#"{"files":[],"strategy":"git","note":"no uncommitted or recent changes"}"#.to_string(), 0));
}

// Strategy 2: SUMMARY.md extraction (no git)
if phase_dir.is_dir() {
    let files = summary_strategy(&phase_dir);
    if !files.is_empty() {
        return Ok((files, 0));
    }
}

// No sources available
Ok((r#"{"files":[],"strategy":"none","note":"no sources available"}"#.to_string(), 0))
```

## Task 4: Update delta-files tests for structured empty responses
**Files:** `yolo-mcp-server/src/commands/delta_files.rs`
**Acceptance:** `test_execute_empty_non_git` updated to check for JSON output with `"strategy":"none"`. New test `test_execute_empty_git_repo` creates a git repo with no changes and verifies JSON output with `"strategy":"git"`. All tests pass.

### Implementation Details

Update `test_execute_empty_non_git`:
```rust
#[test]
fn test_execute_empty_non_git() {
    let dir = TempDir::new().unwrap();
    let args: Vec<String> = vec!["yolo".into(), "delta-files".into()];
    let (output, code) = execute(&args, dir.path()).unwrap();
    assert_eq!(code, 0);
    let parsed: serde_json::Value = serde_json::from_str(&output).unwrap();
    assert_eq!(parsed["strategy"], "none");
}
```
