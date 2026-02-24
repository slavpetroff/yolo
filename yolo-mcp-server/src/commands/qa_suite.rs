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
/// 1. verify-plan-completion — cross-references SUMMARY vs PLAN
/// 2. commit-lint — validates conventional commit format
/// 3. check-regression — counts tests for regression detection
/// 4. diff-against-plan — cross-references declared files vs git diffs
/// 5. validate-requirements — checks must_haves are evidenced
///
/// Exit codes: 0=all pass, 1=any fail
pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    let start = Instant::now();

    if args.len() < 4 {
        return Err(
            "Usage: yolo qa-suite <summary_path> <plan_path> [--commit-range R] [--phase-dir D]"
                .to_string(),
        );
    }

    let summary_path = args[2].clone();
    let plan_path = args[3].clone();

    // Parse optional flags
    let mut commit_range = "HEAD~1..HEAD".to_string();
    let mut phase_dir = String::new();

    let mut i = 4;
    while i < args.len() {
        match args[i].as_str() {
            "--commit-range" if i + 1 < args.len() => {
                commit_range = args[i + 1].clone();
                i += 2;
            }
            "--phase-dir" if i + 1 < args.len() => {
                phase_dir = args[i + 1].clone();
                i += 2;
            }
            _ => {
                i += 1;
            }
        }
    }

    // Default phase_dir to parent of summary_path
    if phase_dir.is_empty() {
        if let Some(parent) = Path::new(&summary_path).parent() {
            phase_dir = parent.to_string_lossy().to_string();
        }
    }

    // Run all 5 checks
    let checks: Vec<(&str, Result<(String, i32), String>)> = vec![
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
                results.insert(name.to_string(), json!({"error": e}));
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

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use tempfile::tempdir;

    fn create_fixtures(dir: &std::path::Path) -> (String, String) {
        let summary = dir.join("01-01-SUMMARY.md");
        fs::write(
            &summary,
            "---\nphase: 01\nplan: 01\ntitle: \"test\"\nstatus: complete\ntasks_completed: 1\ntasks_total: 1\ncommit_hashes: [\"abc1234\"]\n---\n\n# Plan 01 Summary\n\n## What Was Built\ntest feature\n\n## Files Modified\n- test.rs\n",
        )
        .unwrap();

        let plan = dir.join("01-PLAN.md");
        fs::write(
            &plan,
            "---\nphase: 01\nplan: 01\ntitle: \"test\"\nwave: 1\ndepends_on: []\nmust_haves:\n  - \"test feature\"\n---\n\n# Plan 01: test\n\n## Task 1: test\n\n**Files:** `test.rs`\n\nDo something.\n",
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

        let (out, _code) = execute(&[s("yolo"), s("qa-suite"), summary, plan], dir.path()).unwrap();

        let parsed: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(parsed["cmd"], "qa-suite");
        assert!(parsed["elapsed_ms"].is_number());
        assert!(parsed["delta"]["results"].is_object());

        let results = parsed["delta"]["results"].as_object().unwrap();
        assert!(results.contains_key("verify-plan-completion"));
        assert!(results.contains_key("commit-lint"));
        assert!(results.contains_key("check-regression"));
        assert!(results.contains_key("diff-against-plan"));
        assert!(results.contains_key("validate-requirements"));
    }

    #[test]
    fn test_checks_run_count() {
        let dir = tempdir().unwrap();
        let (summary, plan) = create_fixtures(dir.path());

        let (out, _) = execute(&[s("yolo"), s("qa-suite"), summary, plan], dir.path()).unwrap();

        let parsed: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(parsed["delta"]["checks_run"], 5);
    }

    #[test]
    fn test_optional_flags() {
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
    }
}
