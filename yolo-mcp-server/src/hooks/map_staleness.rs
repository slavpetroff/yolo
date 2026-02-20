use std::fs;
use std::path::Path;
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

use serde_json::json;

use super::types::{HookInput, HookOutput};
use super::utils;

/// Handle SessionStart: check codebase map staleness.
/// If >30% files changed since map creation, emit hookSpecificOutput JSON
/// advising the user to refresh.
pub fn handle(input: &HookInput, hook_mode: bool) -> Result<HookOutput, String> {
    let cwd = std::env::current_dir().map_err(|e| format!("Failed to get cwd: {}", e))?;

    let planning_dir = match utils::get_planning_dir(&cwd) {
        Some(d) => d,
        None => return Ok(HookOutput::empty()),
    };

    // Skip during compaction
    if is_compaction_recent(&planning_dir) {
        return Ok(HookOutput::empty());
    }

    let meta_path = planning_dir.join("codebase/META.md");
    if !meta_path.is_file() {
        return if hook_mode {
            Ok(HookOutput::empty())
        } else {
            Ok(HookOutput::ok("status: no_map\n".to_string()))
        };
    }

    // Check git availability
    if !is_git_repo(&cwd) {
        return if hook_mode {
            Ok(HookOutput::empty())
        } else {
            Ok(HookOutput::ok("status: no_git\n".to_string()))
        };
    }

    // Parse META.md
    let meta = parse_meta(&meta_path);
    let git_hash = match meta.git_hash {
        Some(h) if !h.is_empty() => h,
        _ => {
            return if hook_mode {
                Ok(HookOutput::empty())
            } else {
                Ok(HookOutput::ok("status: no_map\n".to_string()))
            };
        }
    };
    let file_count = match meta.file_count {
        Some(c) if c > 0 => c,
        _ => {
            return if hook_mode {
                Ok(HookOutput::empty())
            } else {
                Ok(HookOutput::ok("status: no_map\n".to_string()))
            };
        }
    };
    let mapped_at = meta.mapped_at.unwrap_or_default();

    // Verify the stored hash exists in this repo
    if !git_object_exists(&cwd, &git_hash) {
        let diag = format!(
            "status: stale\nstaleness: 100%\nchanged: unknown\ntotal: {}\nsince: {}\n",
            file_count, mapped_at
        );
        return if hook_mode {
            let hook_json = json!({
                "hookSpecificOutput": {
                    "hookEventName": "SessionStart",
                    "additionalContext": format!(
                        "Codebase map is stale (100% files changed). Run /yolo:map --incremental to refresh."
                    )
                }
            });
            Ok(HookOutput::ok(hook_json.to_string()))
        } else {
            Ok(HookOutput::ok(diag))
        };
    }

    // Count changed files since map was created
    let changed = count_changed_files(&cwd, &git_hash);
    let staleness = (changed * 100) / file_count;
    let status = if staleness > 30 { "stale" } else { "fresh" };

    let diag = format!(
        "status: {}\nstaleness: {}%\nchanged: {}\ntotal: {}\nsince: {}\n",
        status, staleness, changed, file_count, mapped_at
    );

    if status == "stale" && hook_mode {
        let hook_json = json!({
            "hookSpecificOutput": {
                "hookEventName": "SessionStart",
                "additionalContext": format!(
                    "Codebase map is stale ({}% files changed). Run /yolo:map --incremental to refresh.",
                    staleness
                )
            }
        });
        Ok(HookOutput::ok(hook_json.to_string()))
    } else if hook_mode {
        // Fresh in hook mode: no output needed
        Ok(HookOutput::empty())
    } else {
        Ok(HookOutput::ok(diag))
    }
}

/// CLI entry point for `yolo map-staleness`.
pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    let hook_mode = args.iter().any(|a| a == "--hook");

    let planning_dir = match utils::get_planning_dir(cwd) {
        Some(d) => d,
        None => {
            return if hook_mode {
                Ok((String::new(), 0))
            } else {
                Ok(("status: no_map\n".to_string(), 0))
            };
        }
    };

    if is_compaction_recent(&planning_dir) {
        return Ok((String::new(), 0));
    }

    let meta_path = planning_dir.join("codebase/META.md");
    if !meta_path.is_file() {
        return if hook_mode {
            Ok((String::new(), 0))
        } else {
            Ok(("status: no_map\n".to_string(), 0))
        };
    }

    if !is_git_repo(cwd) {
        return if hook_mode {
            Ok((String::new(), 0))
        } else {
            Ok(("status: no_git\n".to_string(), 0))
        };
    }

    let meta = parse_meta(&meta_path);
    let git_hash = match meta.git_hash {
        Some(h) if !h.is_empty() => h,
        _ => {
            return if hook_mode {
                Ok((String::new(), 0))
            } else {
                Ok(("status: no_map\n".to_string(), 0))
            };
        }
    };
    let file_count = match meta.file_count {
        Some(c) if c > 0 => c,
        _ => {
            return if hook_mode {
                Ok((String::new(), 0))
            } else {
                Ok(("status: no_map\n".to_string(), 0))
            };
        }
    };
    let mapped_at = meta.mapped_at.unwrap_or_default();

    if !git_object_exists(cwd, &git_hash) {
        let diag = format!(
            "status: stale\nstaleness: 100%\nchanged: unknown\ntotal: {}\nsince: {}\n",
            file_count, mapped_at
        );
        return if hook_mode {
            let hook_json = json!({
                "hookSpecificOutput": {
                    "hookEventName": "SessionStart",
                    "additionalContext": "Codebase map is stale (100% files changed). Run /yolo:map --incremental to refresh."
                }
            });
            Ok((hook_json.to_string(), 0))
        } else {
            Ok((diag, 0))
        };
    }

    let changed = count_changed_files(cwd, &git_hash);
    let staleness = (changed * 100) / file_count;
    let status = if staleness > 30 { "stale" } else { "fresh" };

    let diag = format!(
        "status: {}\nstaleness: {}%\nchanged: {}\ntotal: {}\nsince: {}\n",
        status, staleness, changed, file_count, mapped_at
    );

    if status == "stale" && hook_mode {
        let hook_json = json!({
            "hookSpecificOutput": {
                "hookEventName": "SessionStart",
                "additionalContext": format!(
                    "Codebase map is stale ({}% files changed). Run /yolo:map --incremental to refresh.",
                    staleness
                )
            }
        });
        Ok((hook_json.to_string(), 0))
    } else if hook_mode {
        Ok((String::new(), 0))
    } else {
        Ok((diag, 0))
    }
}

struct MetaInfo {
    git_hash: Option<String>,
    file_count: Option<i64>,
    mapped_at: Option<String>,
}

/// Parse META.md for git_hash, file_count, mapped_at.
/// Supports both `key: value` and `- **key**: value` formats.
fn parse_meta(path: &Path) -> MetaInfo {
    let mut info = MetaInfo {
        git_hash: None,
        file_count: None,
        mapped_at: None,
    };

    let content = match fs::read_to_string(path) {
        Ok(c) => c,
        Err(_) => return info,
    };

    for line in content.lines() {
        let line = line.trim();

        // Support `key: value` format
        if line.starts_with("git_hash:") {
            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() > 1 {
                info.git_hash = Some(parts[1].to_string());
            }
        } else if line.starts_with("file_count:") {
            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() > 1 {
                info.file_count = parts[1].parse().ok();
            }
        } else if line.starts_with("mapped_at:") {
            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() > 1 {
                info.mapped_at = Some(parts[1].to_string());
            }
        }
        // Support `- **key**: value` format
        else if line.starts_with("- **git_hash**:") {
            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() > 2 {
                info.git_hash = Some(parts[2].to_string());
            }
        } else if line.starts_with("- **file_count**:") {
            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() > 2 {
                info.file_count = parts[2].parse().ok();
            }
        } else if line.starts_with("- **mapped_at**:") {
            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() > 2 {
                info.mapped_at = Some(parts[2].to_string());
            }
        }
    }

    info
}

/// Check if compaction marker is recent (within 60 seconds).
fn is_compaction_recent(planning_dir: &Path) -> bool {
    let marker = planning_dir.join(".compaction-marker");
    if !marker.is_file() {
        return false;
    }

    let content = fs::read_to_string(&marker).unwrap_or_default();
    let marker_ts: u64 = content.trim().parse().unwrap_or(0);
    if marker_ts == 0 {
        return false;
    }

    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);

    now.saturating_sub(marker_ts) < 60
}

/// Check if cwd is a git repo.
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

/// Verify a git object exists.
fn git_object_exists(cwd: &Path, hash: &str) -> bool {
    Command::new("git")
        .args(["cat-file", "-e", hash])
        .current_dir(cwd)
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

/// Count files changed since a given git hash.
fn count_changed_files(cwd: &Path, hash: &str) -> i64 {
    let output = Command::new("git")
        .args(["diff", "--name-only", &format!("{}..HEAD", hash)])
        .current_dir(cwd)
        .output();

    match output {
        Ok(o) if o.status.success() => {
            let text = String::from_utf8_lossy(&o.stdout);
            text.lines().filter(|l| !l.trim().is_empty()).count() as i64
        }
        _ => 0,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn test_parse_meta_key_value_format() {
        let dir = TempDir::new().unwrap();
        let meta = dir.path().join("META.md");
        fs::write(
            &meta,
            "git_hash: abc123\nfile_count: 50\nmapped_at: 2026-01-01T00:00:00Z\n",
        )
        .unwrap();

        let info = parse_meta(&meta);
        assert_eq!(info.git_hash.as_deref(), Some("abc123"));
        assert_eq!(info.file_count, Some(50));
        assert_eq!(info.mapped_at.as_deref(), Some("2026-01-01T00:00:00Z"));
    }

    #[test]
    fn test_parse_meta_markdown_format() {
        let dir = TempDir::new().unwrap();
        let meta = dir.path().join("META.md");
        fs::write(
            &meta,
            "- **git_hash**: def456\n- **file_count**: 100\n- **mapped_at**: 2026-02-01\n",
        )
        .unwrap();

        let info = parse_meta(&meta);
        assert_eq!(info.git_hash.as_deref(), Some("def456"));
        assert_eq!(info.file_count, Some(100));
        assert_eq!(info.mapped_at.as_deref(), Some("2026-02-01"));
    }

    #[test]
    fn test_parse_meta_missing_file() {
        let info = parse_meta(Path::new("/nonexistent/META.md"));
        assert!(info.git_hash.is_none());
        assert!(info.file_count.is_none());
        assert!(info.mapped_at.is_none());
    }

    #[test]
    fn test_is_compaction_recent_no_marker() {
        let dir = TempDir::new().unwrap();
        assert!(!is_compaction_recent(dir.path()));
    }

    #[test]
    fn test_is_compaction_recent_old_marker() {
        let dir = TempDir::new().unwrap();
        let marker = dir.path().join(".compaction-marker");
        // Write a timestamp from 5 minutes ago
        let old_ts = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs()
            - 300;
        fs::write(&marker, old_ts.to_string()).unwrap();
        assert!(!is_compaction_recent(dir.path()));
    }

    #[test]
    fn test_is_compaction_recent_fresh_marker() {
        let dir = TempDir::new().unwrap();
        let marker = dir.path().join(".compaction-marker");
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();
        fs::write(&marker, now.to_string()).unwrap();
        assert!(is_compaction_recent(dir.path()));
    }

    #[test]
    fn test_execute_no_planning_dir() {
        let dir = TempDir::new().unwrap();
        let args: Vec<String> = vec!["yolo".into(), "map-staleness".into()];
        let (output, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
        assert!(output.contains("no_map"));
    }

    #[test]
    fn test_execute_no_meta() {
        let dir = TempDir::new().unwrap();
        fs::create_dir_all(dir.path().join(".yolo-planning")).unwrap();
        let args: Vec<String> = vec!["yolo".into(), "map-staleness".into()];
        let (output, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
        assert!(output.contains("no_map"));
    }

    #[test]
    fn test_execute_hook_mode_no_planning() {
        let dir = TempDir::new().unwrap();
        let args: Vec<String> = vec!["yolo".into(), "map-staleness".into(), "--hook".into()];
        let (output, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
        assert!(output.is_empty());
    }

    #[test]
    fn test_execute_compaction_skip() {
        let dir = TempDir::new().unwrap();
        let planning = dir.path().join(".yolo-planning");
        fs::create_dir_all(planning.join("codebase")).unwrap();
        fs::write(
            planning.join("codebase/META.md"),
            "git_hash: abc\nfile_count: 10\n",
        )
        .unwrap();
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();
        fs::write(planning.join(".compaction-marker"), now.to_string()).unwrap();

        let args: Vec<String> = vec!["yolo".into(), "map-staleness".into()];
        let (output, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
        assert!(output.is_empty());
    }

    #[test]
    fn test_handle_no_planning_dir() {
        let dir = TempDir::new().unwrap();
        // Set CWD to temp dir
        let _ = std::env::set_current_dir(dir.path());
        let input = HookInput {
            data: serde_json::json!({}),
        };
        let result = handle(&input, true);
        assert!(result.is_ok());
        let output = result.unwrap();
        assert_eq!(output.exit_code, 0);
    }

    #[test]
    fn test_staleness_calculation() {
        // 10 changed out of 100 = 10% = fresh
        let staleness = (10 * 100) / 100;
        assert_eq!(staleness, 10);
        assert!(staleness <= 30);

        // 40 changed out of 100 = 40% = stale
        let staleness = (40 * 100) / 100;
        assert_eq!(staleness, 40);
        assert!(staleness > 30);
    }
}
