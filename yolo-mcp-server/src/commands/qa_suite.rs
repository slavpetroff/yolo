use serde_json::{json, Value};
use std::path::Path;
use std::time::Instant;

use crate::commands::{
    check_regression, commit_lint, diff_against_plan, validate_requirements,
    verify_plan_completion,
};

fn s(v: &str) -> String {
    v.to_string()
}

/// Facade command that runs all 5 QA checks and returns unified JSON.
///
/// Usage: yolo qa-suite <summary_path> <plan_path> [--commit-range R] [--phase-dir D]
///
/// Runs:
/// 1. verify-plan-completion -- cross-references SUMMARY vs PLAN
/// 2. commit-lint -- validates conventional commit format
/// 3. check-regression -- counts tests for regression detection
/// 4. diff-against-plan -- cross-references declared files vs git diffs
/// 5. validate-requirements -- checks must_haves are evidenced
///
/// Exit codes: 0=all pass, 1=any fail
pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    let start = Instant::now();

    // Filter positional args (skip flags and their values)
    let positional: Vec<&String> = args.iter().filter(|a| !a.starts_with("--")).collect();

    if positional.len() < 4 {
        return Err(
            "Usage: yolo qa-suite <summary_path> <plan_path> [--commit-range R] [--phase-dir D]"
                .to_string(),
        );
    }

    let summary_path = positional[2].clone();
    let plan_path = positional[3].clone();

    // Parse optional flags
    let commit_range = parse_flag(args, "--commit-range").unwrap_or_else(|| s("HEAD~1..HEAD"));
    let phase_dir = parse_flag(args, "--phase-dir").unwrap_or_else(|| {
        Path::new(&summary_path)
            .parent()
            .map(|p| p.to_string_lossy().to_string())
            .unwrap_or_else(|| s("."))
    });

    // Run all 5 checks
    type CheckResult = Result<(String, i32), String>;
    let checks: Vec<(&str, CheckResult)> = vec![
        (
            "verify-plan-completion",
            verify_plan_completion::execute(
                &[
                    s("yolo"),
                    s("verify-plan-completion"),
                    summary_path.clone(),
                    plan_path.clone(),
                ],
                cwd,
            ),
        ),
        (
            "commit-lint",
            commit_lint::execute(
                &[s("yolo"), s("commit-lint"), commit_range.clone()],
                cwd,
            ),
        ),
        (
            "check-regression",
            check_regression::execute(
                &[s("yolo"), s("check-regression"), phase_dir.clone()],
                cwd,
            ),
        ),
        (
            "diff-against-plan",
            diff_against_plan::execute(
                &[s("yolo"), s("diff-against-plan"), summary_path.clone()],
                cwd,
            ),
        ),
        (
            "validate-requirements",
            validate_requirements::execute(
                &[
                    s("yolo"),
                    s("validate-requirements"),
                    plan_path.clone(),
                    phase_dir.clone(),
                ],
                cwd,
            ),
        ),
    ];

    let mut results = serde_json::Map::new();
    let mut checks_passed = 0u32;
    let mut checks_failed = 0u32;

    for (name, result) in checks {
        match result {
            Ok((json_str, code)) => {
                let parsed: Value =
                    serde_json::from_str(&json_str).unwrap_or(json!({"raw": json_str.trim()}));
                if code == 0 {
                    checks_passed += 1;
                } else {
                    checks_failed += 1;
                }
                results.insert(name.to_string(), parsed);
            }
            Err(e) => {
                checks_failed += 1;
                results.insert(name.to_string(), json!({"ok": false, "error": e}));
            }
        }
    }

    let all_pass = checks_failed == 0;
    let response = json!({
        "ok": all_pass,
        "cmd": "qa-suite",
        "delta": {
            "checks_run": 5,
            "checks_passed": checks_passed,
            "checks_failed": checks_failed,
            "results": Value::Object(results)
        },
        "elapsed_ms": start.elapsed().as_millis() as u64
    });

    Ok((response.to_string(), if all_pass { 0 } else { 1 }))
}

/// Parse a --flag value pair from args.
fn parse_flag(args: &[String], flag: &str) -> Option<String> {
    let mut iter = args.iter();
    while let Some(arg) = iter.next() {
        if arg == flag {
            return iter.next().cloned();
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use tempfile::tempdir;

    fn create_fixtures(dir: &std::path::Path) -> (String, String) {
        let summary = dir.join("01-01-SUMMARY.md");
        fs::write(
            &summary,
            "\
---
phase: \"01\"
plan: \"01\"
title: \"test\"
status: complete
tasks_completed: 1
tasks_total: 1
commit_hashes: [\"abc1234\"]
---

# Plan 01 Summary

## What Was Built

test feature

## Files Modified

- test.rs
",
        )
        .unwrap();

        let plan = dir.join("01-PLAN.md");
        fs::write(
            &plan,
            "\
---
phase: \"01\"
plan: \"01\"
title: \"test\"
wave: 1
depends_on: []
must_haves:
  - \"test feature\"
---

# Plan 01: test

### Task 1: test

**Files:** `test.rs`

Do something.
",
        )
        .unwrap();

        (
            summary.to_string_lossy().to_string(),
            plan.to_string_lossy().to_string(),
        )
    }

    #[test]
    fn test_missing_args() {
        let dir = tempdir().unwrap();
        let result = execute(&[s("yolo"), s("qa-suite"), s("only-one")], dir.path());
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Usage:"));
    }

    #[test]
    fn test_response_schema() {
        let dir = tempdir().unwrap();
        let (summary, plan) = create_fixtures(dir.path());

        let (out, _code) =
            execute(&[s("yolo"), s("qa-suite"), summary, plan], dir.path()).unwrap();

        let parsed: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(parsed["cmd"], "qa-suite");
        assert!(parsed["elapsed_ms"].is_number());
        assert!(parsed["ok"].is_boolean());
        assert!(parsed["delta"]["results"].is_object());
    }

    #[test]
    fn test_all_five_checks_in_results() {
        let dir = tempdir().unwrap();
        let (summary, plan) = create_fixtures(dir.path());

        let (out, _code) =
            execute(&[s("yolo"), s("qa-suite"), summary, plan], dir.path()).unwrap();

        let parsed: Value = serde_json::from_str(&out).unwrap();
        let results = parsed["delta"]["results"].as_object().unwrap();

        let expected = [
            "verify-plan-completion",
            "commit-lint",
            "check-regression",
            "diff-against-plan",
            "validate-requirements",
        ];
        for key in &expected {
            assert!(results.contains_key(*key), "Missing result key: {}", key);
        }
    }

    #[test]
    fn test_checks_run_count() {
        let dir = tempdir().unwrap();
        let (summary, plan) = create_fixtures(dir.path());

        let (out, _) =
            execute(&[s("yolo"), s("qa-suite"), summary, plan], dir.path()).unwrap();

        let parsed: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(parsed["delta"]["checks_run"], 5);

        let passed = parsed["delta"]["checks_passed"].as_u64().unwrap();
        let failed = parsed["delta"]["checks_failed"].as_u64().unwrap();
        assert_eq!(passed + failed, 5);
    }

    #[test]
    fn test_optional_flags_accepted() {
        let dir = tempdir().unwrap();
        let (summary, plan) = create_fixtures(dir.path());

        let (out, _) = execute(
            &[
                s("yolo"),
                s("qa-suite"),
                summary,
                plan,
                s("--commit-range"),
                s("HEAD~3..HEAD"),
                s("--phase-dir"),
                dir.path().to_string_lossy().to_string(),
            ],
            dir.path(),
        )
        .unwrap();

        let parsed: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(parsed["cmd"], "qa-suite");
        assert_eq!(parsed["delta"]["checks_run"], 5);
    }
}
