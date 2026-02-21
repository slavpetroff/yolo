---
phase: 1
plan: 05
title: "CLI audit: identify and fix remaining stubs, silent failures, and error handling gaps"
wave: 2
depends_on: [1, 2, 3, 4]
must_haves:
  - "All 56+ CLI commands audited for stubs and silent failures"
  - "Audit report written to phase directory documenting findings"
  - "Any critical stubs found are fixed or documented with TODO markers"
---

## Task 1: Audit all CLI commands for stubs and silent failures
**Files:** `yolo-mcp-server/src/cli/router.rs` (read-only), all command files (read-only)
**Acceptance:** A comprehensive audit checklist is written to `.yolo-planning/phases/01-incomplete-cli-mcp-fixes/AUDIT.md` documenting each CLI command's status: (a) routed in router.rs, (b) handles --help flag, (c) returns meaningful error on bad input, (d) has at least 1 unit test. Commands with issues are flagged.

### Implementation Details

Systematically check each of the ~56 commands:
1. Cross-reference router.rs match arms against mod.rs modules
2. For each routed command, verify:
   - Does it handle `--help` / `-h`?
   - Does it return `Err(...)` on missing required args (not silent empty output)?
   - Does it have `#[cfg(test)]` section with at least one test?
3. Write findings to AUDIT.md with status table

After Plans 01-04 complete, this audit verifies everything is wired up.

## Task 2: Fix any critical stubs or silent failures found in audit
**Files:** Various command files as identified by audit
**Acceptance:** Any command that returns empty string on error (silent failure) is fixed to return a proper error message. Any command that accepts invalid input silently is fixed to validate. Maximum 5 fixes in this task (scope-limited).

### Implementation Details

Known candidates for silent failure based on code review:
- Commands that use `unwrap_or_default()` on required inputs may silently produce garbage output
- Commands using `Ok(("".to_string(), 0))` for error conditions should return `Err(...)` instead

Focus on the most impactful: commands used in the execution workflow (suggest-next, phase-detect, resolve-model, resolve-turns).

## Task 3: Verify end-to-end: yolo infer on a realistic project structure
**Files:** `yolo-mcp-server/src/commands/infer_project_context.rs` (test only)
**Acceptance:** An integration test creates a project structure mimicking alpine-notetaker (pyproject.toml with fastapi+redis, README.md with description) and runs `yolo infer` against it. The test asserts: (a) tech_stack includes "Python", "fastapi", (b) purpose is non-null, (c) name is derived correctly.

### Implementation Details

This is the end-to-end acceptance test from the phase spec. Create in the existing test module:

```rust
#[test]
fn test_infer_alpine_notetaker_e2e() {
    let dir = tempdir().unwrap();
    let codebase_dir = dir.path().join("codebase");
    fs::create_dir_all(&codebase_dir).unwrap();

    // Simulate a project with pyproject.toml (at repo_root, not codebase_dir)
    fs::write(dir.path().join("pyproject.toml"), r#"
[project]
name = "alpine-notetaker"
dependencies = ["fastapi", "redis", "uvicorn"]
"#).unwrap();

    fs::write(dir.path().join("README.md"), r#"
# Alpine Notetaker

A lightweight note-taking API built with FastAPI and Redis for fast, ephemeral storage.
"#).unwrap();

    // No STACK.md, no CONCERNS.md — force fallbacks
    let (out, code) = execute(
        &["yolo".to_string(), "infer".to_string(),
          codebase_dir.to_string_lossy().to_string(),
          dir.path().to_string_lossy().to_string()],
        dir.path()
    ).unwrap();

    assert_eq!(code, 0);
    let parsed: serde_json::Value = serde_json::from_str(&out).unwrap();

    // Tech stack should detect Python and fastapi
    let stack = parsed["tech_stack"]["value"].as_array().unwrap();
    assert!(stack.iter().any(|v| v.as_str().unwrap().to_lowercase().contains("python")));
    assert!(stack.iter().any(|v| v.as_str().unwrap().to_lowercase().contains("fastapi")));

    // Purpose should be extracted from README
    let purpose = parsed["purpose"]["value"].as_str().unwrap();
    assert!(!purpose.is_empty());
    assert!(purpose.to_lowercase().contains("note") || purpose.to_lowercase().contains("api"));
}
```
