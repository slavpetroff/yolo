use std::fs;
use std::path::Path;
use std::process::Command;
use serde_json::{json, Value};
use std::time::Instant;

/// Read planning_tracking and auto_push from config JSON file.
fn read_config(config_path: &Path) -> (String, String) {
    let mut planning_tracking = "manual".to_string();
    let mut auto_push = "never".to_string();

    if config_path.exists() {
        if let Ok(content) = fs::read_to_string(config_path) {
            if let Ok(json) = serde_json::from_str::<Value>(&content) {
                if let Some(v) = json.get("planning_tracking").and_then(|v| v.as_str()) {
                    planning_tracking = v.to_string();
                }
                if let Some(v) = json.get("auto_push").and_then(|v| v.as_str()) {
                    auto_push = v.to_string();
                }
            }
        }
    }

    (planning_tracking, auto_push)
}

/// Check if cwd is inside a git repository.
fn is_git_repo(cwd: &Path) -> bool {
    Command::new("git")
        .args(["rev-parse", "--git-dir"])
        .current_dir(cwd)
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

/// Write the transient .gitignore inside .yolo-planning/ for commit mode.
fn ensure_transient_ignore(cwd: &Path) {
    let planning_dir = cwd.join(".yolo-planning");
    if !planning_dir.is_dir() {
        return;
    }

    let ignore_file = planning_dir.join(".gitignore");
    let content = r#"# YOLO transient runtime artifacts
.execution-state.json
.execution-state.json.tmp
.context-*.md
.contracts/
.locks/
.token-state/

# Session & agent tracking
.yolo-session
.active-agent
.active-agent-count
.active-agent-count.lock/
.agent-pids
.task-verify-seen

# Metrics & cost tracking
.metrics/
.cost-ledger.json

# Caching
.cache/

# Artifacts & events (v2/v3 feature-gated)
.artifacts/
.events/
.event-log.jsonl

# Snapshots & recovery
.snapshots/

# Logging & markers
.hook-errors.log
.compaction-marker
.session-log.jsonl
.session-log.jsonl.tmp
.notification-log.jsonl
.watchdog-pid
.watchdog.log
.claude-md-migrated
.tmux-mode-patched

# Baselines
.baselines/

# Codebase mapping
codebase/
"#;

    let _ = fs::write(ignore_file, content);
}

/// Ensure .yolo-planning/ is handled correctly in root .gitignore based on mode.
fn sync_root_ignore(cwd: &Path, mode: &str) {
    let root_ignore = cwd.join(".gitignore");

    if mode == "ignore" {
        if !root_ignore.exists() {
            let _ = fs::write(&root_ignore, ".yolo-planning/\n");
            return;
        }

        if let Ok(content) = fs::read_to_string(&root_ignore) {
            if !content.lines().any(|l| l == ".yolo-planning/") {
                let _ = fs::write(&root_ignore, format!("{}\n.yolo-planning/\n", content));
            }
        }
        return;
    }

    if mode == "commit" && root_ignore.exists() {
        if let Ok(content) = fs::read_to_string(&root_ignore) {
            let filtered: Vec<&str> = content.lines().filter(|l| *l != ".yolo-planning/").collect();
            let _ = fs::write(&root_ignore, filtered.join("\n") + "\n");
        }
    }
}

/// Check if current branch has an upstream tracking branch.
fn has_upstream(cwd: &Path) -> bool {
    Command::new("git")
        .args(["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"])
        .current_dir(cwd)
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

/// Push to remote.
fn git_push(cwd: &Path) -> Result<(), String> {
    let output = Command::new("git")
        .arg("push")
        .current_dir(cwd)
        .output()
        .map_err(|e| format!("git push failed: {}", e))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("git push failed: {}", stderr));
    }
    Ok(())
}

fn handle_sync_ignore(args: &[String], cwd: &Path, start: Instant) -> Result<(String, i32), String> {
    let default_config = ".yolo-planning/config.json".to_string();
    let config_file = args.get(3).unwrap_or(&default_config);
    let config_path = cwd.join(config_file);

    if !is_git_repo(cwd) {
        let response = json!({
            "ok": true,
            "cmd": "planning-git",
            "delta": { "subcommand": "sync-ignore", "skipped": true, "reason": "not a git repo" },
            "elapsed_ms": start.elapsed().as_millis() as u64
        });
        return Ok((response.to_string(), 0));
    }

    let (tracking, _) = read_config(&config_path);
    sync_root_ignore(cwd, &tracking);

    let mut transient_written = false;
    if tracking == "commit" {
        ensure_transient_ignore(cwd);
        transient_written = true;
    }

    let response = json!({
        "ok": true,
        "cmd": "planning-git",
        "delta": {
            "subcommand": "sync-ignore",
            "tracking_mode": tracking,
            "transient_ignore_written": transient_written
        },
        "elapsed_ms": start.elapsed().as_millis() as u64
    });
    Ok((response.to_string(), 0))
}

fn handle_commit_boundary(args: &[String], cwd: &Path, start: Instant) -> Result<(String, i32), String> {
    let action = args.get(3).ok_or_else(|| {
        "Usage: yolo planning-git commit-boundary <action> [CONFIG_FILE]".to_string()
    })?;
    let default_config = ".yolo-planning/config.json".to_string();
    let config_file = args.get(4).unwrap_or(&default_config);
    let config_path = cwd.join(config_file);

    if !is_git_repo(cwd) {
        let response = json!({
            "ok": true,
            "cmd": "planning-git",
            "delta": { "subcommand": "commit-boundary", "committed": false, "reason": "not a git repo" },
            "elapsed_ms": start.elapsed().as_millis() as u64
        });
        return Ok((response.to_string(), 0));
    }

    let (tracking, auto_push) = read_config(&config_path);

    if tracking != "commit" {
        let response = json!({
            "ok": true,
            "cmd": "planning-git",
            "delta": { "subcommand": "commit-boundary", "committed": false, "reason": "tracking mode is not commit" },
            "elapsed_ms": start.elapsed().as_millis() as u64
        });
        return Ok((response.to_string(), 0));
    }

    ensure_transient_ignore(cwd);

    // git add .yolo-planning
    let planning_dir = cwd.join(".yolo-planning");
    if planning_dir.is_dir() {
        let _ = Command::new("git")
            .args(["add", ".yolo-planning"])
            .current_dir(cwd)
            .output();
    }

    // git add CLAUDE.md (if exists)
    let claude_md = cwd.join("CLAUDE.md");
    if claude_md.exists() {
        let _ = Command::new("git")
            .args(["add", "CLAUDE.md"])
            .current_dir(cwd)
            .output();
    }

    // Check if there are staged changes
    let diff_result = Command::new("git")
        .args(["diff", "--cached", "--quiet"])
        .current_dir(cwd)
        .status();

    match diff_result {
        Ok(status) if status.success() => {
            // No staged changes
            let response = json!({
                "ok": true,
                "cmd": "planning-git",
                "delta": { "subcommand": "commit-boundary", "committed": false, "reason": "no staged changes" },
                "elapsed_ms": start.elapsed().as_millis() as u64
            });
            return Ok((response.to_string(), 0));
        }
        _ => {}
    }

    // Commit
    let commit_msg = format!("chore(yolo): {}", action);
    let commit_result = Command::new("git")
        .args(["commit", "-m", &commit_msg])
        .current_dir(cwd)
        .output()
        .map_err(|e| format!("git commit failed: {}", e))?;

    if !commit_result.status.success() {
        let stderr = String::from_utf8_lossy(&commit_result.stderr);
        return Err(format!("git commit failed: {}", stderr));
    }

    // Capture commit hash
    let commit_hash = Command::new("git")
        .args(["rev-parse", "--short", "HEAD"])
        .current_dir(cwd)
        .output()
        .ok()
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .map(|s| s.trim().to_string());

    // Push if auto_push=always and branch has upstream
    let mut pushed = false;
    if auto_push == "always" && has_upstream(cwd) {
        git_push(cwd)?;
        pushed = true;
    }

    let response = json!({
        "ok": true,
        "cmd": "planning-git",
        "delta": {
            "subcommand": "commit-boundary",
            "action": action,
            "committed": true,
            "commit_hash": commit_hash,
            "pushed": pushed
        },
        "elapsed_ms": start.elapsed().as_millis() as u64
    });

    Ok((response.to_string(), 0))
}

fn handle_push_after_phase(args: &[String], cwd: &Path, start: Instant) -> Result<(String, i32), String> {
    let default_config = ".yolo-planning/config.json".to_string();
    let config_file = args.get(3).unwrap_or(&default_config);
    let config_path = cwd.join(config_file);

    if !is_git_repo(cwd) {
        let response = json!({
            "ok": true,
            "cmd": "planning-git",
            "delta": { "subcommand": "push-after-phase", "pushed": false, "reason": "not a git repo" },
            "elapsed_ms": start.elapsed().as_millis() as u64
        });
        return Ok((response.to_string(), 0));
    }

    let (_, auto_push) = read_config(&config_path);

    let mut pushed = false;
    let mut reason = format!("auto_push is {}", auto_push);
    if auto_push == "after_phase" && has_upstream(cwd) {
        git_push(cwd)?;
        pushed = true;
        reason = "pushed to upstream".to_string();
    } else if auto_push == "after_phase" && !has_upstream(cwd) {
        reason = "no upstream branch".to_string();
    }

    let response = json!({
        "ok": true,
        "cmd": "planning-git",
        "delta": {
            "subcommand": "push-after-phase",
            "pushed": pushed,
            "reason": reason
        },
        "elapsed_ms": start.elapsed().as_millis() as u64
    });
    Ok((response.to_string(), 0))
}

pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    let start = Instant::now();
    let subcommand = args.get(2).map(|s| s.as_str()).unwrap_or("");

    match subcommand {
        "sync-ignore" => handle_sync_ignore(args, cwd, start),
        "commit-boundary" => handle_commit_boundary(args, cwd, start),
        "push-after-phase" => handle_push_after_phase(args, cwd, start),
        "" => Err("Usage: yolo planning-git sync-ignore [CONFIG_FILE] | commit-boundary <action> [CONFIG_FILE] | push-after-phase [CONFIG_FILE]".to_string()),
        other => Err(format!("Unknown subcommand: {}\nUsage: yolo planning-git sync-ignore [CONFIG_FILE] | commit-boundary <action> [CONFIG_FILE] | push-after-phase [CONFIG_FILE]", other)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    fn setup_git_repo(dir: &Path) {
        Command::new("git").args(["init"]).current_dir(dir).output().unwrap();
        Command::new("git").args(["config", "user.email", "test@test.com"]).current_dir(dir).output().unwrap();
        Command::new("git").args(["config", "user.name", "Test"]).current_dir(dir).output().unwrap();
        fs::write(dir.join("README.md"), "init").unwrap();
        Command::new("git").args(["add", "."]).current_dir(dir).output().unwrap();
        Command::new("git").args(["commit", "-m", "init"]).current_dir(dir).output().unwrap();
    }

    fn write_config(dir: &Path, tracking: &str, push: &str) {
        let planning_dir = dir.join(".yolo-planning");
        fs::create_dir_all(&planning_dir).unwrap();
        let config = format!(r#"{{"planning_tracking":"{}","auto_push":"{}"}}"#, tracking, push);
        fs::write(planning_dir.join("config.json"), config).unwrap();
    }

    #[test]
    fn test_read_config_defaults_when_missing() {
        let dir = tempdir().unwrap();
        let (tracking, push) = read_config(&dir.path().join("nonexistent.json"));
        assert_eq!(tracking, "manual");
        assert_eq!(push, "never");
    }

    #[test]
    fn test_read_config_parses_values() {
        let dir = tempdir().unwrap();
        let config_path = dir.path().join("config.json");
        fs::write(&config_path, r#"{"planning_tracking":"commit","auto_push":"always"}"#).unwrap();
        let (tracking, push) = read_config(&config_path);
        assert_eq!(tracking, "commit");
        assert_eq!(push, "always");
    }

    #[test]
    fn test_sync_ignore_mode_ignore_adds_line() {
        let dir = tempdir().unwrap();
        setup_git_repo(dir.path());
        write_config(dir.path(), "ignore", "never");

        let args = vec![
            "yolo".to_string(),
            "planning-git".to_string(),
            "sync-ignore".to_string(),
        ];
        let (output, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
        let j: Value = serde_json::from_str(&output).unwrap();
        assert_eq!(j["ok"], true);
        assert_eq!(j["delta"]["subcommand"], "sync-ignore");

        let gitignore = fs::read_to_string(dir.path().join(".gitignore")).unwrap();
        assert!(gitignore.contains(".yolo-planning/"));
    }

    #[test]
    fn test_sync_ignore_mode_commit_removes_line_creates_transient() {
        let dir = tempdir().unwrap();
        setup_git_repo(dir.path());
        fs::write(dir.path().join(".gitignore"), "node_modules/\n.yolo-planning/\n").unwrap();
        write_config(dir.path(), "commit", "never");

        let args = vec![
            "yolo".to_string(),
            "planning-git".to_string(),
            "sync-ignore".to_string(),
        ];
        let (output, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
        let j: Value = serde_json::from_str(&output).unwrap();
        assert_eq!(j["delta"]["transient_ignore_written"], true);
        assert_eq!(j["delta"]["tracking_mode"], "commit");

        let gitignore = fs::read_to_string(dir.path().join(".gitignore")).unwrap();
        assert!(!gitignore.lines().any(|l| l == ".yolo-planning/"));

        let transient = dir.path().join(".yolo-planning").join(".gitignore");
        assert!(transient.exists());
        let content = fs::read_to_string(transient).unwrap();
        assert!(content.contains(".execution-state.json"));
        assert!(content.contains("codebase/"));
    }

    #[test]
    fn test_sync_ignore_mode_manual_is_noop() {
        let dir = tempdir().unwrap();
        setup_git_repo(dir.path());
        write_config(dir.path(), "manual", "never");
        fs::write(dir.path().join(".gitignore"), "node_modules/\n").unwrap();

        let args = vec![
            "yolo".to_string(),
            "planning-git".to_string(),
            "sync-ignore".to_string(),
        ];
        let (output, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
        let j: Value = serde_json::from_str(&output).unwrap();
        assert_eq!(j["delta"]["tracking_mode"], "manual");
        assert_eq!(j["delta"]["transient_ignore_written"], false);

        let gitignore = fs::read_to_string(dir.path().join(".gitignore")).unwrap();
        assert_eq!(gitignore, "node_modules/\n");
    }

    #[test]
    fn test_sync_ignore_non_git_repo_returns_ok() {
        let dir = tempdir().unwrap();
        let args = vec![
            "yolo".to_string(),
            "planning-git".to_string(),
            "sync-ignore".to_string(),
        ];
        let (output, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
        let j: Value = serde_json::from_str(&output).unwrap();
        assert_eq!(j["ok"], true);
        assert_eq!(j["delta"]["skipped"], true);
    }

    // --- commit-boundary tests ---

    #[test]
    fn test_commit_boundary_non_commit_mode_is_noop() {
        let dir = tempdir().unwrap();
        setup_git_repo(dir.path());
        write_config(dir.path(), "manual", "never");

        let args = vec![
            "yolo".to_string(),
            "planning-git".to_string(),
            "commit-boundary".to_string(),
            "plan phase 1".to_string(),
        ];
        let (output, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
        let j: Value = serde_json::from_str(&output).unwrap();
        assert_eq!(j["delta"]["committed"], false);
        assert_eq!(j["delta"]["reason"], "tracking mode is not commit");
    }

    #[test]
    fn test_commit_boundary_commit_mode_stages_and_commits() {
        let dir = tempdir().unwrap();
        setup_git_repo(dir.path());
        write_config(dir.path(), "commit", "never");

        // Create a file in .yolo-planning to commit
        fs::write(dir.path().join(".yolo-planning").join("STATE.md"), "# State\n").unwrap();

        let args = vec![
            "yolo".to_string(),
            "planning-git".to_string(),
            "commit-boundary".to_string(),
            "plan phase 1".to_string(),
        ];
        let (output, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
        let j: Value = serde_json::from_str(&output).unwrap();
        assert_eq!(j["ok"], true);
        assert_eq!(j["delta"]["committed"], true);
        assert!(j["delta"]["commit_hash"].as_str().unwrap().len() >= 7);
        assert_eq!(j["delta"]["action"], "plan phase 1");

        // Verify a commit was made
        let log = Command::new("git")
            .args(["log", "--oneline", "-1"])
            .current_dir(dir.path())
            .output()
            .unwrap();
        let log_str = String::from_utf8_lossy(&log.stdout);
        assert!(log_str.contains("chore(yolo): plan phase 1"));
    }

    #[test]
    fn test_commit_boundary_no_staged_changes_is_noop() {
        let dir = tempdir().unwrap();
        setup_git_repo(dir.path());
        write_config(dir.path(), "commit", "never");

        // Write the transient ignore first, then commit everything so
        // the next commit-boundary has nothing new to stage.
        ensure_transient_ignore(dir.path());
        Command::new("git").args(["add", ".yolo-planning"]).current_dir(dir.path()).output().unwrap();
        Command::new("git").args(["commit", "-m", "add planning"]).current_dir(dir.path()).output().unwrap();

        let args = vec![
            "yolo".to_string(),
            "planning-git".to_string(),
            "commit-boundary".to_string(),
            "should not commit".to_string(),
        ];
        let (output, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
        let j: Value = serde_json::from_str(&output).unwrap();
        assert_eq!(j["delta"]["committed"], false);
        assert_eq!(j["delta"]["reason"], "no staged changes");

        // Verify last commit is NOT our action
        let log = Command::new("git")
            .args(["log", "--oneline", "-1"])
            .current_dir(dir.path())
            .output()
            .unwrap();
        let log_str = String::from_utf8_lossy(&log.stdout);
        assert!(!log_str.contains("should not commit"));
    }

    #[test]
    fn test_commit_boundary_missing_action_errors() {
        let dir = tempdir().unwrap();
        setup_git_repo(dir.path());

        let args = vec![
            "yolo".to_string(),
            "planning-git".to_string(),
            "commit-boundary".to_string(),
        ];
        let result = execute(&args, dir.path());
        assert!(result.is_err());
    }

    #[test]
    fn test_commit_boundary_non_git_repo_returns_ok() {
        let dir = tempdir().unwrap();
        let args = vec![
            "yolo".to_string(),
            "planning-git".to_string(),
            "commit-boundary".to_string(),
            "some action".to_string(),
        ];
        let (output, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
        let j: Value = serde_json::from_str(&output).unwrap();
        assert_eq!(j["delta"]["committed"], false);
        assert_eq!(j["delta"]["reason"], "not a git repo");
    }

    // --- push-after-phase tests ---

    #[test]
    fn test_push_after_phase_never_mode_is_noop() {
        let dir = tempdir().unwrap();
        setup_git_repo(dir.path());
        write_config(dir.path(), "manual", "never");

        let args = vec![
            "yolo".to_string(),
            "planning-git".to_string(),
            "push-after-phase".to_string(),
        ];
        let (output, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
        let j: Value = serde_json::from_str(&output).unwrap();
        assert_eq!(j["delta"]["pushed"], false);
    }

    #[test]
    fn test_push_after_phase_non_git_repo_returns_ok() {
        let dir = tempdir().unwrap();
        let args = vec![
            "yolo".to_string(),
            "planning-git".to_string(),
            "push-after-phase".to_string(),
        ];
        let (output, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
        let j: Value = serde_json::from_str(&output).unwrap();
        assert_eq!(j["ok"], true);
        assert_eq!(j["delta"]["pushed"], false);
    }

    // --- routing tests ---

    #[test]
    fn test_missing_subcommand_errors() {
        let dir = tempdir().unwrap();
        let args = vec![
            "yolo".to_string(),
            "planning-git".to_string(),
        ];
        let result = execute(&args, dir.path());
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Usage:"));
    }

    #[test]
    fn test_unknown_subcommand_errors() {
        let dir = tempdir().unwrap();
        let args = vec![
            "yolo".to_string(),
            "planning-git".to_string(),
            "foobar".to_string(),
        ];
        let result = execute(&args, dir.path());
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Unknown subcommand: foobar"));
    }
}
