use std::collections::BTreeSet;
use std::fs;
use std::path::Path;
use std::process::Command;

/// Maximum number of files returned from fallback strategies (tag-based, HEAD~5).
/// A massive diff is not useful context, so we cap fallback results.
const MAX_FALLBACK_FILES: usize = 50;

/// Output changed files (one per line) for delta context compilation.
/// Strategy 1 (git): diff --name-only HEAD + cached, deduplicate.
/// Fallback: last 5 commits or since last tag.
/// Strategy 2 (no git): extract from SUMMARY.md files.
pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    let phase_dir = if args.len() > 2 {
        cwd.join(&args[2])
    } else {
        cwd.to_path_buf()
    };

    // Strategy 1: git-based
    if is_git_repo(cwd) {
        if let Some(files) = git_strategy(cwd) {
            if !files.is_empty() {
                return Ok((files, 0));
            }
        }
    }

    // Strategy 2: SUMMARY.md extraction (no git)
    if phase_dir.is_dir() {
        let files = summary_strategy(&phase_dir);
        if !files.is_empty() {
            return Ok((files, 0));
        }
    }

    // No sources available
    Ok((String::new(), 0))
}

/// Git-based delta file detection.
fn git_strategy(cwd: &Path) -> Option<String> {
    let mut files = BTreeSet::new();

    // Changed files in working tree (unstaged)
    if let Some(changed) = git_diff_names(cwd, &["diff", "--name-only", "HEAD"]) {
        for f in changed {
            files.insert(f);
        }
    }

    // Staged files
    if let Some(staged) = git_diff_names(cwd, &["diff", "--name-only", "--cached"]) {
        for f in staged {
            files.insert(f);
        }
    }

    if !files.is_empty() {
        return Some(files.into_iter().collect::<Vec<_>>().join("\n"));
    }

    // No uncommitted changes -- try since last tag
    let last_tag = git_output(cwd, &["describe", "--tags", "--abbrev=0"]);
    if let Some(tag) = last_tag {
        let tag = tag.trim().to_string();
        if !tag.is_empty() {
            if let Some(tag_files) = git_diff_names(cwd, &["diff", "--name-only", &format!("{}..HEAD", tag)]) {
                if !tag_files.is_empty() {
                    // Skip tag-based fallback entirely if diff exceeds cap (not useful context)
                    if tag_files.len() <= MAX_FALLBACK_FILES {
                        let sorted: BTreeSet<String> = tag_files.into_iter().collect();
                        return Some(sorted.into_iter().collect::<Vec<_>>().join("\n"));
                    }
                }
            }
        }
    }

    // Fallback: last 5 commits
    if let Some(recent) = git_diff_names(cwd, &["diff", "--name-only", "HEAD~5..HEAD"]) {
        if !recent.is_empty() {
            let sorted: BTreeSet<String> = recent.into_iter().collect();
            let sorted_vec: Vec<String> = sorted.into_iter().collect();
            if sorted_vec.len() > MAX_FALLBACK_FILES {
                let total = sorted_vec.len();
                let mut truncated: Vec<String> = sorted_vec.into_iter().take(MAX_FALLBACK_FILES).collect();
                truncated.push(format!("... (truncated, showing first {} of {} files)", MAX_FALLBACK_FILES, total));
                return Some(truncated.join("\n"));
            }
            return Some(sorted_vec.join("\n"));
        }
    }

    None
}

/// Extract changed files from SUMMARY.md files in phase directory.
fn summary_strategy(phase_dir: &Path) -> String {
    let mut files = BTreeSet::new();

    if let Ok(entries) = fs::read_dir(phase_dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            let name = path.file_name().unwrap_or_default().to_string_lossy().to_string();
            if name.ends_with("-SUMMARY.md") {
                if let Ok(content) = fs::read_to_string(&path) {
                    let mut in_files_section = false;
                    for line in content.lines() {
                        if line.starts_with("## Files Modified") {
                            in_files_section = true;
                            continue;
                        }
                        if in_files_section && line.starts_with("## ") {
                            break;
                        }
                        if in_files_section && line.starts_with("- ") {
                            // Strip "- " prefix and any trailing parenthetical
                            let file = line.trim_start_matches("- ");
                            let file = if let Some(idx) = file.find(" (") {
                                &file[..idx]
                            } else {
                                file
                            };
                            let file = file.trim();
                            if !file.is_empty() {
                                files.insert(file.to_string());
                            }
                        }
                    }
                }
            }
        }
    }

    files.into_iter().collect::<Vec<_>>().join("\n")
}

/// Check if cwd is inside a git repo.
fn is_git_repo(cwd: &Path) -> bool {
    Command::new("git")
        .args(["rev-parse", "--is-inside-work-tree"])
        .current_dir(cwd)
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

/// Run a git command and return the list of filenames from its output.
fn git_diff_names(cwd: &Path, args: &[&str]) -> Option<Vec<String>> {
    let output = Command::new("git")
        .args(args)
        .current_dir(cwd)
        .output()
        .ok()?;

    if !output.status.success() {
        return None;
    }

    let text = String::from_utf8_lossy(&output.stdout);
    let files: Vec<String> = text
        .lines()
        .map(|l| l.trim().to_string())
        .filter(|l| !l.is_empty())
        .collect();

    Some(files)
}

/// Run a git command and return trimmed stdout.
fn git_output(cwd: &Path, args: &[&str]) -> Option<String> {
    let output = Command::new("git")
        .args(args)
        .current_dir(cwd)
        .output()
        .ok()?;

    if !output.status.success() {
        return None;
    }

    Some(String::from_utf8_lossy(&output.stdout).trim().to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn test_summary_strategy_no_files() {
        let dir = TempDir::new().unwrap();
        let result = summary_strategy(dir.path());
        assert!(result.is_empty());
    }

    #[test]
    fn test_summary_strategy_with_summaries() {
        let dir = TempDir::new().unwrap();
        let content = r#"## Summary
Some work done.

## Files Modified
- src/main.rs
- src/lib.rs (new)
- tests/test.rs (modified)

## Notes
Nothing else.
"#;
        fs::write(dir.path().join("01-SUMMARY.md"), content).unwrap();

        let result = summary_strategy(dir.path());
        let files: Vec<&str> = result.lines().collect();
        assert_eq!(files.len(), 3);
        assert!(files.contains(&"src/lib.rs"));
        assert!(files.contains(&"src/main.rs"));
        assert!(files.contains(&"tests/test.rs"));
    }

    #[test]
    fn test_summary_strategy_deduplicates() {
        let dir = TempDir::new().unwrap();
        let content1 = "## Files Modified\n- src/main.rs\n";
        let content2 = "## Files Modified\n- src/main.rs\n- src/lib.rs\n";
        fs::write(dir.path().join("01-SUMMARY.md"), content1).unwrap();
        fs::write(dir.path().join("02-SUMMARY.md"), content2).unwrap();

        let result = summary_strategy(dir.path());
        let files: Vec<&str> = result.lines().collect();
        assert_eq!(files.len(), 2); // Deduplicated
    }

    #[test]
    fn test_execute_empty_non_git() {
        let dir = TempDir::new().unwrap();
        let args: Vec<String> = vec!["yolo".into(), "delta-files".into()];
        let (output, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
        assert!(output.is_empty());
    }

    #[test]
    fn test_execute_with_phase_dir() {
        let dir = TempDir::new().unwrap();
        let phase = dir.path().join("phases/01");
        fs::create_dir_all(&phase).unwrap();
        fs::write(
            phase.join("01-SUMMARY.md"),
            "## Files Modified\n- src/app.rs\n",
        )
        .unwrap();

        let args: Vec<String> = vec![
            "yolo".into(),
            "delta-files".into(),
            phase.to_str().unwrap().into(),
        ];
        let (output, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
        assert_eq!(output.trim(), "src/app.rs");
    }

    #[test]
    fn test_git_strategy_in_real_repo() {
        // This test runs in the actual repo checkout
        let cwd = Path::new(env!("CARGO_MANIFEST_DIR")).parent().unwrap();
        if is_git_repo(cwd) {
            // Just verify it doesn't panic
            let _ = git_strategy(cwd);
        }
    }

    #[test]
    fn test_is_git_repo_non_repo() {
        let dir = TempDir::new().unwrap();
        assert!(!is_git_repo(dir.path()));
    }

    #[test]
    fn test_summary_strategy_stops_at_next_section() {
        let dir = TempDir::new().unwrap();
        let content = r#"## Files Modified
- src/a.rs

## Other Section
- not/a/file.rs
"#;
        fs::write(dir.path().join("01-SUMMARY.md"), content).unwrap();

        let result = summary_strategy(dir.path());
        let files: Vec<&str> = result.lines().collect();
        assert_eq!(files.len(), 1);
        assert_eq!(files[0], "src/a.rs");
    }
}
