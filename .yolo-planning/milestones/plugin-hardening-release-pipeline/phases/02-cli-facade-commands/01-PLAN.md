---
phase: 02
plan: 01
title: "qa-suite facade command"
wave: 1
depends_on: []
must_haves:
  - "Single command runs all 5 QA checks"
  - "Unified JSON response with ok, cmd, delta, elapsed_ms"
  - "Individual check results preserved in delta"
  - "Exit code 0 only if ALL checks pass"
  - "Cargo clippy clean"
---

# Plan 01: qa-suite facade command

**Files modified:** `yolo-mcp-server/src/commands/qa_suite.rs`

Implements `yolo qa-suite <summary_path> <plan_path> [--commit-range R] [--phase-dir D]` that internally calls all 5 QA check execute() functions and returns unified JSON.

## Task 1: Create qa_suite.rs with argument parsing

**Files:** `yolo-mcp-server/src/commands/qa_suite.rs`

**What to do:**
1. Create `yolo-mcp-server/src/commands/qa_suite.rs`
2. Add `use std::path::Path; use std::time::Instant; use serde_json::json;`
3. Import sibling modules: `use crate::commands::{verify_plan_completion, commit_lint, check_regression, diff_against_plan, validate_requirements};`
4. Implement `pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String>`
5. Parse args: `args[2]` = summary_path, `args[3]` = plan_path. Scan for `--commit-range` flag (next arg = range) and `--phase-dir` flag (next arg = dir). Default commit-range to `HEAD~1..HEAD`, default phase-dir to parent of summary_path

## Task 2: Call all 5 QA checks internally

**Files:** `yolo-mcp-server/src/commands/qa_suite.rs`

**What to do:**
1. Build args for each sub-command and call their execute() functions directly (no shell):
   - `verify_plan_completion::execute(&["yolo", "verify-plan-completion", summary, plan], cwd)`
   - `commit_lint::execute(&["yolo", "commit-lint", commit_range], cwd)`
   - `check_regression::execute(&["yolo", "check-regression", phase_dir], cwd)`
   - `diff_against_plan::execute(&["yolo", "diff-against-plan", summary], cwd)`
   - `validate_requirements::execute(&["yolo", "validate-requirements", plan, phase_dir], cwd)`
2. For each result: parse the JSON output, extract `ok` and the check-specific fields
3. Track overall `all_pass` = all 5 checks returned exit code 0
4. If a check returns `Err`, record it as a failed check with `error` detail rather than propagating

## Task 3: Build unified JSON response

**Files:** `yolo-mcp-server/src/commands/qa_suite.rs`

**What to do:**
1. Build response following the standard schema:
```json
{
  "ok": all_pass,
  "cmd": "qa-suite",
  "delta": {
    "checks_run": 5,
    "checks_passed": N,
    "checks_failed": M,
    "results": {
      "verify-plan-completion": { parsed sub-result },
      "commit-lint": { parsed sub-result },
      "check-regression": { parsed sub-result },
      "diff-against-plan": { parsed sub-result },
      "validate-requirements": { parsed sub-result }
    }
  },
  "elapsed_ms": elapsed
}
```
2. Return exit code 0 if all_pass, 1 otherwise

## Task 4: Add unit tests

**Files:** `yolo-mcp-server/src/commands/qa_suite.rs`

**What to do:**
1. Add `#[cfg(test)] mod tests` at bottom of file
2. Test: missing args returns Err with usage message
3. Test: valid summary+plan with all checks passing returns `ok: true`, `checks_passed: 5`
4. Test: valid invocation returns all 5 check keys in `delta.results`
5. Test: response always includes `cmd: "qa-suite"` and `elapsed_ms`
6. Use tempfile::tempdir for test fixtures. Create minimal SUMMARY.md and PLAN.md with valid frontmatter

**Commit:** `feat(yolo): add qa-suite facade command`
