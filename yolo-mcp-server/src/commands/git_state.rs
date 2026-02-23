use std::path::Path;
use std::process::Command;
use serde_json::json;
use super::structured_response::Timer;

pub fn execute(_args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    let timer = Timer::start();

    if !is_git_repo(cwd) {
        let resp = json!({
            "ok": true,
            "cmd": "git-state",
            "is_git_repo": false,
            "branch": serde_json::Value::Null,
            "dirty": false,
            "dirty_files": 0,
            "staged_files": 0,
            "last_tag": serde_json::Value::Null,
            "commits_since_tag": 0,
            "head_sha": serde_json::Value::Null,
            "head_short": serde_json::Value::Null,
            "head_message": serde_json::Value::Null,
            "has_upstream": false,
            "ahead": 0,
            "behind": 0,
            "elapsed_ms": timer.elapsed_ms()
        });
        return Ok((resp.to_string(), 0));
    }

    let branch = git_cmd(cwd, &["rev-parse", "--abbrev-ref", "HEAD"]);
    let porcelain = git_cmd(cwd, &["status", "--porcelain"]);
    let dirty_files = porcelain.as_ref()
        .map(|s| s.lines().filter(|l| !l.is_empty()).count())
        .unwrap_or(0);
    let dirty = dirty_files > 0;

    let staged = git_cmd(cwd, &["diff", "--cached", "--name-only"]);
    let staged_files = staged.as_ref()
        .map(|s| s.lines().filter(|l| !l.is_empty()).count())
        .unwrap_or(0);

    let last_tag = git_cmd(cwd, &["describe", "--tags", "--abbrev=0"]);
    let commits_since_tag = if let Some(ref tag) = last_tag {
        let range = format!("{}..HEAD", tag);
        git_cmd(cwd, &["rev-list", &range, "--count"])
            .and_then(|s| s.parse::<u64>().ok())
            .unwrap_or(0)
    } else {
        0
    };

    let head_sha = git_cmd(cwd, &["rev-parse", "HEAD"]);
    let head_short = git_cmd(cwd, &["rev-parse", "--short", "HEAD"]);
    let head_message = git_cmd(cwd, &["log", "-1", "--format=%s"]);

    let has_upstream = git_cmd(cwd, &["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"]).is_some();
    let (ahead, behind) = if has_upstream {
        parse_ahead_behind(cwd)
    } else {
        (0, 0)
    };

    let resp = json!({
        "ok": true,
        "cmd": "git-state",
        "is_git_repo": true,
        "branch": branch,
        "dirty": dirty,
        "dirty_files": dirty_files,
        "staged_files": staged_files,
        "last_tag": last_tag,
        "commits_since_tag": commits_since_tag,
        "head_sha": head_sha,
        "head_short": head_short,
        "head_message": head_message,
        "has_upstream": has_upstream,
        "ahead": ahead,
        "behind": behind,
        "elapsed_ms": timer.elapsed_ms()
    });

    Ok((resp.to_string(), 0))
}

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

fn git_cmd(cwd: &Path, args: &[&str]) -> Option<String> {
    Command::new("git")
        .args(args)
        .current_dir(cwd)
        .stderr(std::process::Stdio::null())
        .output()
        .ok()
        .filter(|o| o.status.success())
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
}

fn parse_ahead_behind(cwd: &Path) -> (u64, u64) {
    git_cmd(cwd, &["rev-list", "--left-right", "--count", "HEAD...@{u}"])
        .and_then(|s| {
            let parts: Vec<&str> = s.split('\t').collect();
            if parts.len() == 2 {
                let ahead = parts[0].trim().parse::<u64>().unwrap_or(0);
                let behind = parts[1].trim().parse::<u64>().unwrap_or(0);
                Some((ahead, behind))
            } else {
                None
            }
        })
        .unwrap_or((0, 0))
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;
    use std::fs;

    fn setup_git_repo(dir: &Path) {
        Command::new("git").args(["init"]).current_dir(dir).output().unwrap();
        Command::new("git").args(["config", "user.email", "test@test.com"]).current_dir(dir).output().unwrap();
        Command::new("git").args(["config", "user.name", "Test"]).current_dir(dir).output().unwrap();
        fs::write(dir.join("README.md"), "init").unwrap();
        Command::new("git").args(["add", "."]).current_dir(dir).output().unwrap();
        Command::new("git").args(["commit", "-m", "initial commit"]).current_dir(dir).output().unwrap();
    }

    #[test]
    fn test_non_git_dir() {
        let dir = tempdir().unwrap();
        let (output, code) = execute(&vec!["yolo".into(), "git-state".into()], dir.path()).unwrap();
        assert_eq!(code, 0);
        let j: serde_json::Value = serde_json::from_str(&output).unwrap();
        assert_eq!(j["ok"], true);
        assert_eq!(j["is_git_repo"], false);
        assert_eq!(j["branch"], serde_json::Value::Null);
    }

    #[test]
    fn test_clean_git_repo() {
        let dir = tempdir().unwrap();
        setup_git_repo(dir.path());
        let (output, code) = execute(&vec!["yolo".into(), "git-state".into()], dir.path()).unwrap();
        assert_eq!(code, 0);
        let j: serde_json::Value = serde_json::from_str(&output).unwrap();
        assert_eq!(j["ok"], true);
        assert_eq!(j["is_git_repo"], true);
        assert_eq!(j["dirty"], false);
        assert_eq!(j["dirty_files"], 0);
        assert!(j["head_sha"].is_string());
        assert!(j["head_short"].is_string());
        assert_eq!(j["head_message"], "initial commit");
    }

    #[test]
    fn test_dirty_git_repo() {
        let dir = tempdir().unwrap();
        setup_git_repo(dir.path());
        fs::write(dir.path().join("new-file.txt"), "uncommitted").unwrap();
        let (output, _) = execute(&vec!["yolo".into(), "git-state".into()], dir.path()).unwrap();
        let j: serde_json::Value = serde_json::from_str(&output).unwrap();
        assert_eq!(j["dirty"], true);
        assert!(j["dirty_files"].as_u64().unwrap() > 0);
    }

    #[test]
    fn test_git_repo_with_tag() {
        let dir = tempdir().unwrap();
        setup_git_repo(dir.path());
        Command::new("git").args(["tag", "v1.0.0"]).current_dir(dir.path()).output().unwrap();
        fs::write(dir.path().join("a.txt"), "a").unwrap();
        Command::new("git").args(["add", "."]).current_dir(dir.path()).output().unwrap();
        Command::new("git").args(["commit", "-m", "second"]).current_dir(dir.path()).output().unwrap();
        fs::write(dir.path().join("b.txt"), "b").unwrap();
        Command::new("git").args(["add", "."]).current_dir(dir.path()).output().unwrap();
        Command::new("git").args(["commit", "-m", "third"]).current_dir(dir.path()).output().unwrap();

        let (output, _) = execute(&vec!["yolo".into(), "git-state".into()], dir.path()).unwrap();
        let j: serde_json::Value = serde_json::from_str(&output).unwrap();
        assert_eq!(j["last_tag"], "v1.0.0");
        assert_eq!(j["commits_since_tag"], 2);
    }

    #[test]
    fn test_git_repo_no_tag() {
        let dir = tempdir().unwrap();
        setup_git_repo(dir.path());
        let (output, _) = execute(&vec!["yolo".into(), "git-state".into()], dir.path()).unwrap();
        let j: serde_json::Value = serde_json::from_str(&output).unwrap();
        assert_eq!(j["last_tag"], serde_json::Value::Null);
        assert_eq!(j["commits_since_tag"], 0);
    }
}
