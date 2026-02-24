use serde_json::{json, Value};
use std::path::Path;
use std::process::Command;
use std::time::Instant;

use crate::commands::bump_version;

fn s(v: &str) -> String {
    v.to_string()
}

/// Files that should be staged in a release commit.
const RELEASE_FILES: &[&str] = &[
    "VERSION",
    ".claude-plugin/plugin.json",
    "marketplace.json",
    "yolo-mcp-server/Cargo.toml",
    "yolo-mcp-server/Cargo.lock",
    "CHANGELOG.md",
];

/// Run a git command in the given working directory, returning (stdout, stderr, exit_code).
fn run_git(cwd: &Path, git_args: &[&str]) -> (String, String, i32) {
    match Command::new("git")
        .args(git_args)
        .current_dir(cwd)
        .output()
    {
        Ok(output) => {
            let stdout = String::from_utf8_lossy(&output.stdout).to_string();
            let stderr = String::from_utf8_lossy(&output.stderr).to_string();
            let code = output.status.code().unwrap_or(1);
            (stdout, stderr, code)
        }
        Err(e) => (String::new(), format!("Failed to run git: {}", e), 1),
    }
}

/// Facade command that orchestrates a full release: bump-version, git add, commit, tag, push.
///
/// Usage: yolo release-suite [--major|--minor] [--dry-run] [--no-push] [--offline]
///
/// Exit codes: 0=all pass, 1=any step failed
pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    let start = Instant::now();

    // Parse flags
    let dry_run = args.iter().any(|a| a == "--dry-run");
    let no_push = args.iter().any(|a| a == "--no-push");
    let major = args.iter().any(|a| a == "--major");
    let minor = args.iter().any(|a| a == "--minor");
    let offline = args.iter().any(|a| a == "--offline");

    if major && minor {
        return Err("Cannot use both --major and --minor".to_string());
    }

    let bump_type = if major {
        "major"
    } else if minor {
        "minor"
    } else {
        "patch"
    };

    let mut steps: Vec<Value> = Vec::new();

    // --- Step 1: bump-version ---
    let (old_version, new_version) = if dry_run {
        // In dry-run mode, call --verify to read current state, then compute what would happen
        let verify_args = vec![s("yolo"), s("bump-version"), s("--verify")];
        let verify_result = bump_version::execute(&verify_args, cwd);

        match verify_result {
            Ok((json_str, code)) => {
                let parsed: Value = serde_json::from_str(&json_str).unwrap_or(json!({}));
                let version_str = parsed["delta"]["versions"]
                    .as_array()
                    .and_then(|arr| arr.first())
                    .and_then(|v| v["version"].as_str());

                if code != 0 || version_str.is_none() {
                    steps.push(json!({
                        "name": "bump-version",
                        "status": "fail",
                        "detail": parsed
                    }));
                    let response = json!({
                        "ok": false,
                        "cmd": "release-suite",
                        "delta": {
                            "old_version": null,
                            "new_version": null,
                            "bump_type": bump_type,
                            "dry_run": dry_run,
                            "steps": steps
                        },
                        "elapsed_ms": start.elapsed().as_millis() as u64
                    });
                    return Ok((response.to_string(), 1));
                }

                let old = version_str.unwrap().to_string();
                let new = compute_next_version(&old, major, minor);
                steps.push(json!({
                    "name": "bump-version",
                    "status": "dry-run",
                    "detail": format!("Would bump {} -> {}", old, new)
                }));
                (old, new)
            }
            Err(e) => {
                steps.push(json!({
                    "name": "bump-version",
                    "status": "fail",
                    "detail": e
                }));
                let response = json!({
                    "ok": false,
                    "cmd": "release-suite",
                    "delta": {
                        "old_version": null,
                        "new_version": null,
                        "bump_type": bump_type,
                        "dry_run": dry_run,
                        "steps": steps
                    },
                    "elapsed_ms": start.elapsed().as_millis() as u64
                });
                return Ok((response.to_string(), 1));
            }
        }
    } else {
        // Normal mode: actually bump
        let mut bump_args = vec![s("yolo"), s("bump-version")];
        if major {
            bump_args.push(s("--major"));
        }
        if minor {
            bump_args.push(s("--minor"));
        }
        if offline {
            bump_args.push(s("--offline"));
        }

        match bump_version::execute(&bump_args, cwd) {
            Ok((json_str, code)) => {
                if code != 0 {
                    let parsed: Value = serde_json::from_str(&json_str).unwrap_or(json!({}));
                    steps.push(json!({
                        "name": "bump-version",
                        "status": "fail",
                        "detail": parsed
                    }));
                    let response = json!({
                        "ok": false,
                        "cmd": "release-suite",
                        "delta": {
                            "old_version": null,
                            "new_version": null,
                            "bump_type": bump_type,
                            "dry_run": false,
                            "steps": steps
                        },
                        "elapsed_ms": start.elapsed().as_millis() as u64
                    });
                    return Ok((response.to_string(), 1));
                }
                let parsed: Value = serde_json::from_str(&json_str).unwrap_or(json!({}));
                let old = parsed["delta"]["old_version"]
                    .as_str()
                    .unwrap_or("unknown")
                    .to_string();
                let new = parsed["delta"]["new_version"]
                    .as_str()
                    .unwrap_or("unknown")
                    .to_string();
                steps.push(json!({
                    "name": "bump-version",
                    "status": "ok",
                    "detail": format!("Bumped {} -> {}", old, new)
                }));
                (old, new)
            }
            Err(e) => {
                steps.push(json!({
                    "name": "bump-version",
                    "status": "fail",
                    "detail": e
                }));
                let response = json!({
                    "ok": false,
                    "cmd": "release-suite",
                    "delta": {
                        "old_version": null,
                        "new_version": null,
                        "bump_type": bump_type,
                        "dry_run": false,
                        "steps": steps
                    },
                    "elapsed_ms": start.elapsed().as_millis() as u64
                });
                return Ok((response.to_string(), 1));
            }
        }
    };

    // --- Step 2: git add ---
    let existing_files: Vec<&str> = RELEASE_FILES
        .iter()
        .filter(|f| cwd.join(f).exists())
        .copied()
        .collect();

    if dry_run {
        steps.push(json!({
            "name": "git-add",
            "status": "dry-run",
            "files": existing_files
        }));
    } else if existing_files.is_empty() {
        steps.push(json!({
            "name": "git-add",
            "status": "ok",
            "files": [],
            "detail": "No release files found to stage"
        }));
    } else {
        let mut git_args: Vec<&str> = vec!["add"];
        git_args.extend(&existing_files);
        let (_, stderr, code) = run_git(cwd, &git_args);
        if code != 0 {
            steps.push(json!({
                "name": "git-add",
                "status": "fail",
                "detail": stderr.trim()
            }));
            return Ok((build_fail_response(
                bump_type, dry_run, &old_version, &new_version, &steps, &start,
            ), 1));
        }
        steps.push(json!({
            "name": "git-add",
            "status": "ok",
            "files": existing_files
        }));
    }

    // --- Step 3: git commit ---
    let commit_msg = format!("chore: release v{}", new_version);
    if dry_run {
        steps.push(json!({
            "name": "git-commit",
            "status": "dry-run",
            "message": commit_msg
        }));
    } else {
        let (_, stderr, code) = run_git(cwd, &["commit", "-m", &commit_msg]);
        if code != 0 {
            steps.push(json!({
                "name": "git-commit",
                "status": "fail",
                "detail": stderr.trim()
            }));
            return Ok((build_fail_response(
                bump_type, dry_run, &old_version, &new_version, &steps, &start,
            ), 1));
        }
        steps.push(json!({
            "name": "git-commit",
            "status": "ok",
            "message": commit_msg
        }));
    }

    // --- Step 4: git tag ---
    let tag_name = format!("v{}", new_version);
    if dry_run {
        steps.push(json!({
            "name": "git-tag",
            "status": "dry-run",
            "tag": tag_name
        }));
    } else {
        let (_, stderr, code) = run_git(cwd, &["tag", &tag_name]);
        if code != 0 {
            steps.push(json!({
                "name": "git-tag",
                "status": "fail",
                "detail": stderr.trim()
            }));
            return Ok((build_fail_response(
                bump_type, dry_run, &old_version, &new_version, &steps, &start,
            ), 1));
        }
        steps.push(json!({
            "name": "git-tag",
            "status": "ok",
            "tag": tag_name
        }));
    }

    // --- Step 5: git push (unless --no-push) ---
    if no_push || dry_run {
        let status = if dry_run { "dry-run" } else { "skipped" };
        steps.push(json!({
            "name": "git-push",
            "status": status
        }));
    } else {
        let (_, stderr, code) = run_git(cwd, &["push"]);
        if code != 0 {
            steps.push(json!({
                "name": "git-push",
                "status": "fail",
                "detail": stderr.trim()
            }));
            return Ok((build_fail_response(
                bump_type, dry_run, &old_version, &new_version, &steps, &start,
            ), 1));
        }
        let (_, stderr2, code2) = run_git(cwd, &["push", "--tags"]);
        if code2 != 0 {
            steps.push(json!({
                "name": "git-push",
                "status": "fail",
                "detail": format!("push --tags failed: {}", stderr2.trim())
            }));
            return Ok((build_fail_response(
                bump_type, dry_run, &old_version, &new_version, &steps, &start,
            ), 1));
        }
        steps.push(json!({
            "name": "git-push",
            "status": "ok"
        }));
    }

    // --- Build success response ---
    let response = json!({
        "ok": true,
        "cmd": "release-suite",
        "delta": {
            "old_version": old_version,
            "new_version": new_version,
            "bump_type": bump_type,
            "dry_run": dry_run,
            "steps": steps
        },
        "elapsed_ms": start.elapsed().as_millis() as u64
    });

    Ok((response.to_string(), 0))
}

/// Compute the next version without writing anything.
fn compute_next_version(current: &str, major: bool, minor: bool) -> String {
    let parts: Vec<&str> = current.split('.').collect();
    if parts.len() != 3 {
        return format!("{}.1", current);
    }
    let maj: u64 = parts[0].parse().unwrap_or(0);
    let min: u64 = parts[1].parse().unwrap_or(0);
    let pat: u64 = parts[2].parse().unwrap_or(0);

    if major {
        format!("{}.0.0", maj + 1)
    } else if minor {
        format!("{}.{}.0", maj, min + 1)
    } else {
        format!("{}.{}.{}", maj, min, pat + 1)
    }
}

/// Build a failure response JSON string.
fn build_fail_response(
    bump_type: &str,
    dry_run: bool,
    old_version: &str,
    new_version: &str,
    steps: &[Value],
    start: &Instant,
) -> String {
    json!({
        "ok": false,
        "cmd": "release-suite",
        "delta": {
            "old_version": old_version,
            "new_version": new_version,
            "bump_type": bump_type,
            "dry_run": dry_run,
            "steps": steps
        },
        "elapsed_ms": start.elapsed().as_millis() as u64
    })
    .to_string()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use tempfile::tempdir;

    /// Set up a minimal test env with VERSION file and git repo.
    fn setup_test_env() -> tempfile::TempDir {
        let dir = tempdir().unwrap();

        // VERSION file
        fs::write(dir.path().join("VERSION"), "1.2.3\n").unwrap();

        // .claude-plugin/plugin.json
        let plugin_dir = dir.path().join(".claude-plugin");
        fs::create_dir_all(&plugin_dir).unwrap();
        fs::write(
            plugin_dir.join("plugin.json"),
            serde_json::to_string_pretty(&json!({
                "name": "test",
                "version": "1.2.3"
            }))
            .unwrap(),
        )
        .unwrap();

        // marketplace.json
        fs::write(
            dir.path().join("marketplace.json"),
            serde_json::to_string_pretty(&json!({
                "plugins": [{"name": "test", "version": "1.2.3"}]
            }))
            .unwrap(),
        )
        .unwrap();

        // yolo-mcp-server/Cargo.toml
        let cargo_dir = dir.path().join("yolo-mcp-server");
        fs::create_dir_all(&cargo_dir).unwrap();
        fs::write(
            cargo_dir.join("Cargo.toml"),
            "[package]\nname = \"yolo-mcp-server\"\nversion = \"1.2.3\"\nedition = \"2024\"\n",
        )
        .unwrap();

        // Initialize git repo so git commands work
        run_git(dir.path(), &["init"]);
        run_git(dir.path(), &["add", "."]);
        run_git(
            dir.path(),
            &[
                "-c", "user.email=test@test.com",
                "-c", "user.name=Test",
                "commit", "-m", "initial",
            ],
        );

        dir
    }

    #[test]
    fn test_major_minor_conflict() {
        let dir = tempdir().unwrap();
        let result = execute(
            &[s("yolo"), s("release-suite"), s("--major"), s("--minor")],
            dir.path(),
        );
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Cannot use both"));
    }

    #[test]
    fn test_dry_run_returns_ok() {
        let dir = setup_test_env();
        let (out, code) = execute(
            &[
                s("yolo"),
                s("release-suite"),
                s("--dry-run"),
                s("--offline"),
            ],
            dir.path(),
        )
        .unwrap();
        assert_eq!(code, 0);
        let parsed: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(parsed["ok"], true);
        assert_eq!(parsed["cmd"], "release-suite");
        assert_eq!(parsed["delta"]["dry_run"], true);

        let steps = parsed["delta"]["steps"].as_array().unwrap();
        // All steps should be "dry-run"
        for step in steps {
            assert_eq!(step["status"], "dry-run", "Step {} not dry-run", step["name"]);
        }
    }

    #[test]
    fn test_missing_version_file() {
        let dir = tempdir().unwrap();
        // No VERSION file — bump should fail
        let (out, code) = execute(
            &[
                s("yolo"),
                s("release-suite"),
                s("--dry-run"),
                s("--offline"),
            ],
            dir.path(),
        )
        .unwrap();
        assert_eq!(code, 1);
        let parsed: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(parsed["ok"], false);
        let steps = parsed["delta"]["steps"].as_array().unwrap();
        assert_eq!(steps[0]["name"], "bump-version");
        assert_eq!(steps[0]["status"], "fail");
    }

    #[test]
    fn test_response_schema() {
        let dir = setup_test_env();
        let (out, _) = execute(
            &[
                s("yolo"),
                s("release-suite"),
                s("--dry-run"),
                s("--offline"),
            ],
            dir.path(),
        )
        .unwrap();
        let parsed: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(parsed["cmd"], "release-suite");
        assert!(parsed["elapsed_ms"].is_number());
        assert!(parsed["delta"]["steps"].is_array());
        assert!(parsed["delta"]["old_version"].is_string());
        assert!(parsed["delta"]["new_version"].is_string());
        assert!(parsed["delta"]["bump_type"].is_string());
    }

    #[test]
    fn test_no_push_skips_push() {
        let dir = setup_test_env();
        let (out, code) = execute(
            &[
                s("yolo"),
                s("release-suite"),
                s("--no-push"),
                s("--offline"),
            ],
            dir.path(),
        )
        .unwrap();
        assert_eq!(code, 0);
        let parsed: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(parsed["ok"], true);
        let steps = parsed["delta"]["steps"].as_array().unwrap();
        let push_step = steps.iter().find(|s| s["name"] == "git-push").unwrap();
        assert_eq!(push_step["status"], "skipped");
    }

    #[test]
    fn test_compute_next_version_patch() {
        assert_eq!(compute_next_version("1.2.3", false, false), "1.2.4");
        assert_eq!(compute_next_version("0.0.0", false, false), "0.0.1");
    }

    #[test]
    fn test_compute_next_version_major() {
        assert_eq!(compute_next_version("1.2.3", true, false), "2.0.0");
    }

    #[test]
    fn test_compute_next_version_minor() {
        assert_eq!(compute_next_version("1.2.3", false, true), "1.3.0");
    }

    #[test]
    fn test_full_release_no_push() {
        let dir = setup_test_env();
        let (out, code) = execute(
            &[
                s("yolo"),
                s("release-suite"),
                s("--no-push"),
                s("--offline"),
            ],
            dir.path(),
        )
        .unwrap();
        assert_eq!(code, 0);
        let parsed: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(parsed["ok"], true);
        assert_eq!(parsed["delta"]["old_version"], "1.2.3");
        assert_eq!(parsed["delta"]["new_version"], "1.2.4");
        assert_eq!(parsed["delta"]["bump_type"], "patch");

        let steps = parsed["delta"]["steps"].as_array().unwrap();
        assert_eq!(steps.len(), 5);
        assert_eq!(steps[0]["name"], "bump-version");
        assert_eq!(steps[0]["status"], "ok");
        assert_eq!(steps[1]["name"], "git-add");
        assert_eq!(steps[1]["status"], "ok");
        assert_eq!(steps[2]["name"], "git-commit");
        assert_eq!(steps[2]["status"], "ok");
        assert_eq!(steps[3]["name"], "git-tag");
        assert_eq!(steps[3]["status"], "ok");
        assert_eq!(steps[4]["name"], "git-push");
        assert_eq!(steps[4]["status"], "skipped");

        // Verify VERSION was actually bumped
        let ver = fs::read_to_string(dir.path().join("VERSION")).unwrap();
        assert_eq!(ver.trim(), "1.2.4");

        // Verify tag exists
        let (tag_out, _, tag_code) = run_git(dir.path(), &["tag", "-l", "v1.2.4"]);
        assert_eq!(tag_code, 0);
        assert!(tag_out.contains("v1.2.4"));
    }
}
