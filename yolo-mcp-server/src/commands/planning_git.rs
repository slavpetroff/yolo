use std::fs;
use std::path::Path;
use std::process::Command;
use serde_json::Value;

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

fn handle_sync_ignore(args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    let default_config = ".yolo-planning/config.json".to_string();
    let config_file = args.get(3).unwrap_or(&default_config);
    let config_path = cwd.join(config_file);

    if !is_git_repo(cwd) {
        return Ok(("".to_string(), 0));
    }

    let (tracking, _) = read_config(&config_path);
    sync_root_ignore(cwd, &tracking);

    if tracking == "commit" {
        ensure_transient_ignore(cwd);
    }

    Ok(("".to_string(), 0))
}

pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    let subcommand = args.get(2).map(|s| s.as_str()).unwrap_or("");

    match subcommand {
        "sync-ignore" => handle_sync_ignore(args, cwd),
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
        let (_, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);

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
        let (_, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);

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
        let (_, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);

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
        assert_eq!(output, "");
    }

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
