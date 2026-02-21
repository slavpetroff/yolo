---
phase: 1
plan: 02
title: "Fix hard-gate broken git commands and exit codes"
wave: 1
depends_on: []
must_haves:
  - "hard-gate protected_file gate calls git diff --name-only --cached (not bare git)"
  - "hard-gate commit_hygiene gate calls git log -1 --pretty=%s (not bare git)"
  - "hard-gate with insufficient args returns exit code 2 (not 0)"
---

## Task 1: Fix protected_file gate broken git command
**Files:** `yolo-mcp-server/src/commands/hard_gate.rs`
**Acceptance:** The `protected_file` gate at line 181-184 calls `git diff --name-only --cached` instead of bare `git` with no arguments. The gate correctly detects staged files that match forbidden_paths and returns `fail` with exit code 2.

### Implementation Details

Line 181-184 currently reads:
```rust
let output = Command::new("git")
    .current_dir(cwd)
    .output()
    .ok();
```

This invokes bare `git` (which just prints help text), so `staged_files` is always garbage. Fix to:
```rust
let output = Command::new("git")
    .args(["diff", "--name-only", "--cached"])
    .current_dir(cwd)
    .output()
    .ok();
```

## Task 2: Fix commit_hygiene gate broken git command
**Files:** `yolo-mcp-server/src/commands/hard_gate.rs`
**Acceptance:** The `commit_hygiene` gate at lines 269-273 calls `git log -1 --pretty=%s` instead of bare `git`. It correctly extracts the last commit message subject line and validates the conventional commit format.

### Implementation Details

Lines 269-273 currently read:
```rust
let output = Command::new("git")
    .current_dir(cwd)
    .output()
    .ok();
```

Fix to:
```rust
let output = Command::new("git")
    .args(["log", "-1", "--pretty=%s"])
    .current_dir(cwd)
    .output()
    .ok();
```

## Task 3: Fix insufficient-args exit code from 0 to 2
**Files:** `yolo-mcp-server/src/commands/hard_gate.rs`
**Acceptance:** When `execute_gate` is called with fewer than 7 args, it returns exit code 2 (hard failure) instead of 0. The JSON output still contains `"result": "error"`.

### Implementation Details

Lines 20-29 currently return exit code 0:
```rust
if args.len() < 7 {
    return Ok((
        json!({ ... "result": "error" ... }).to_string(),
        0  // <-- BUG: should be 2
    ));
}
```

Change `0` to `2`.

## Task 4: Add/update unit tests for fixed gates
**Files:** `yolo-mcp-server/src/commands/hard_gate.rs`
**Acceptance:** (a) `test_execute_gate_missing_args` asserts exit code 2, (b) new test for commit_hygiene with conventional commit verifies pass, (c) new test for protected_file with staged forbidden file verifies fail. All existing tests still pass.

### Implementation Details

Update `test_execute_gate_missing_args` at line 469: change `assert_eq!(code, 0)` to `assert_eq!(code, 2)`.

The existing `test_commit_hygiene_valid` test already creates a git repo and makes a commit. It should now actually work correctly since the git command is fixed (it was passing before by accident because bare `git` returned success on some platforms).
