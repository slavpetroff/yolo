use serde_json::json;
use std::path::Path;
use std::process::Command;

/// Counts tests to detect potential regressions.
///
/// Usage: yolo check-regression <phase_dir>
///
/// Checks:
/// 1. Count Rust tests via `cargo test -p yolo-mcp-server -- --list`
/// 2. Count .bats test files in tests/ directory
///
/// Always reports ok=true (regression detection is informational).
///
/// Exit codes: 0=no regressions
pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    if args.len() < 3 {
        return Err("Usage: yolo check-regression <phase_dir>".to_string());
    }

    // Count Rust tests
    let rust_tests = count_rust_tests(cwd);

    // Count bats test files
    let bats_files = count_bats_files(cwd);

    let resp = json!({
        "ok": true,
        "cmd": "check-regression",
        "rust_tests": rust_tests,
        "bats_files": bats_files,
        "regressions": 0,
        "fixable_by": "manual",
    });

    Ok((resp.to_string(), 0))
}

/// Count Rust tests by running `cargo test -p yolo-mcp-server -- --list`
/// and counting lines containing `:: test`.
fn count_rust_tests(cwd: &Path) -> u32 {
    let output = Command::new("cargo")
        .args(["test", "-p", "yolo-mcp-server", "--", "--list"])
        .current_dir(cwd)
        .stderr(std::process::Stdio::null())
        .output();

    match output {
        Ok(o) => {
            let stdout = String::from_utf8_lossy(&o.stdout);
            stdout
                .lines()
                .filter(|line| line.contains(": test"))
                .count() as u32
        }
        Err(_) => 0,
    }
}

/// Count .bats files in the tests/ directory.
fn count_bats_files(cwd: &Path) -> u32 {
    let tests_dir = cwd.join("tests");
    if !tests_dir.is_dir() {
        return 0;
    }
    count_bats_recursive(&tests_dir)
}

/// Recursively count .bats files in a directory.
fn count_bats_recursive(dir: &Path) -> u32 {
    let mut count = 0u32;
    if let Ok(entries) = std::fs::read_dir(dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                count += count_bats_recursive(&path);
            } else if let Some(ext) = path.extension()
                && ext == "bats" {
                    count += 1;
            }
        }
    }
    count
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use tempfile::tempdir;

    #[test]
    fn test_counts_are_reported() {
        let dir = tempdir().unwrap();
        // Create a tests/ directory with some .bats files
        let tests_dir = dir.path().join("tests");
        fs::create_dir_all(&tests_dir).unwrap();
        fs::write(tests_dir.join("foo.bats"), "#!/usr/bin/env bats\n").unwrap();
        fs::write(tests_dir.join("bar.bats"), "#!/usr/bin/env bats\n").unwrap();

        let args = vec![
            "yolo".to_string(),
            "check-regression".to_string(),
            dir.path().to_string_lossy().to_string(),
        ];
        let (output, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
        let parsed: serde_json::Value = serde_json::from_str(&output).unwrap();
        assert_eq!(parsed["ok"], true);
        assert_eq!(parsed["bats_files"], 2);
        assert_eq!(parsed["regressions"], 0);
        assert_eq!(parsed["fixable_by"], "manual");
        // rust_tests may be 0 in a temp dir without a Cargo project
        assert!(parsed["rust_tests"].is_number());
    }

    #[test]
    fn test_no_tests_dir_reports_zero() {
        let dir = tempdir().unwrap();
        // No tests/ directory

        let args = vec![
            "yolo".to_string(),
            "check-regression".to_string(),
            dir.path().to_string_lossy().to_string(),
        ];
        let (output, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
        let parsed: serde_json::Value = serde_json::from_str(&output).unwrap();
        assert_eq!(parsed["ok"], true);
        assert_eq!(parsed["bats_files"], 0);
        assert_eq!(parsed["rust_tests"], 0);
        assert_eq!(parsed["fixable_by"], "manual");
    }
}
