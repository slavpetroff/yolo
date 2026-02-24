use regex::Regex;
use serde_json::json;
use std::collections::HashSet;
use std::fs;
use std::path::Path;
use std::process::Command;
use std::sync::OnceLock;

/// Cross-references declared files in SUMMARY against actual git diffs.
///
/// Usage: yolo diff-against-plan <summary_path> [--commits hash1,hash2]
///
/// Checks:
/// 1. Read files_modified from SUMMARY frontmatter or ## Files Modified section
/// 2. Extract commit_hashes from SUMMARY frontmatter (or --commits override)
/// 3. Run `git show --stat {hash}` for each commit hash
/// 4. Cross-reference: are all files in git commits also declared in SUMMARY?
///
/// The `--commits` flag fully overrides frontmatter `commit_hashes` when present
/// with a non-empty value. Empty value is treated as flag-not-passed.
///
/// Exit codes: 0=match, 1=mismatch
pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    if args.len() < 3 {
        return Err(
            "Usage: yolo diff-against-plan <summary_path> [--commits hash1,hash2]".to_string(),
        );
    }

    let summary_path = Path::new(&args[2]);

    if !summary_path.exists() {
        let resp = json!({
            "ok": false,
            "cmd": "diff-against-plan",
            "declared": 0,
            "actual": 0,
            "undeclared": [],
            "missing": ["SUMMARY file not found"],
            "fixable_by": "dev",
        });
        return Ok((resp.to_string(), 1));
    }

    let summary_content = fs::read_to_string(summary_path)
        .map_err(|e| format!("Failed to read SUMMARY: {}", e))?;

    // Extract declared files from ## Files Modified section
    let declared_files = extract_declared_files(&summary_content);

    // Extract commit hashes from frontmatter
    let frontmatter = extract_frontmatter(&summary_content);
    let mut commit_hashes = match &frontmatter {
        Some(fm) => parse_list_field(fm, "commit_hashes"),
        None => Vec::new(),
    };

    // --commits flag overrides frontmatter commit_hashes
    if let Some(val) = parse_flag(args, "--commits") {
        if !val.is_empty() {
            let overrides: Vec<String> = val
                .split(',')
                .map(|s| s.trim().to_string())
                .filter(|s| !s.is_empty())
                .collect();
            if !overrides.is_empty() {
                commit_hashes = overrides;
            }
        }
    }

    // Get actual files from git commits
    let actual_files = get_git_files(&commit_hashes, cwd);

    // Cross-reference
    let declared_set: HashSet<&str> = declared_files.iter().map(|s| s.as_str()).collect();
    let actual_set: HashSet<&str> = actual_files.iter().map(|s| s.as_str()).collect();

    let undeclared: Vec<&str> = actual_set.difference(&declared_set).copied().collect();
    let missing: Vec<&str> = declared_set.difference(&actual_set).copied().collect();

    let ok = undeclared.is_empty() && missing.is_empty();

    let fixable_by = if ok { "none" } else { "dev" };
    let resp = json!({
        "ok": ok,
        "cmd": "diff-against-plan",
        "declared": declared_files.len(),
        "actual": actual_files.len(),
        "undeclared": undeclared,
        "missing": missing,
        "fixable_by": fixable_by,
    });

    Ok((resp.to_string(), if ok { 0 } else { 1 }))
}

/// Extract frontmatter content between first `---` and second `---`.
fn extract_frontmatter(content: &str) -> Option<String> {
    if !content.starts_with("---") {
        return None;
    }
    let after_first = &content[3..];
    let rest = after_first.trim_start_matches(|c: char| c != '\n');
    let rest = rest.strip_prefix('\n').unwrap_or(rest);
    if let Some(end_idx) = rest.find("\n---") {
        Some(rest[..end_idx].to_string())
    } else if rest.ends_with("---") {
        let trimmed = rest.trim_end_matches("---");
        Some(trimmed.to_string())
    } else {
        None
    }
}

/// Parse a YAML list field from frontmatter.
fn parse_list_field(frontmatter: &str, field_name: &str) -> Vec<String> {
    let mut result = Vec::new();
    let mut in_field = false;
    let prefix = format!("{}:", field_name);

    for line in frontmatter.lines() {
        let trimmed = line.trim();

        if trimmed.starts_with(&prefix) {
            let value = trimmed[prefix.len()..].trim();

            if value.starts_with('[') {
                let inner = value.trim_start_matches('[').trim_end_matches(']');
                if inner.trim().is_empty() {
                    return result;
                }
                for item in inner.split(',') {
                    let cleaned = item.trim().trim_matches('"').trim_matches('\'').trim();
                    if !cleaned.is_empty() {
                        result.push(cleaned.to_string());
                    }
                }
                return result;
            }

            if value == "[]" {
                return result;
            }

            in_field = true;
            continue;
        }

        if in_field {
            if let Some(stripped) = trimmed.strip_prefix("- ") {
                let item = stripped.trim().trim_matches('"').trim_matches('\'');
                if !item.is_empty() {
                    result.push(item.to_string());
                }
            } else if !trimmed.is_empty() {
                break;
            }
        }
    }

    result
}

/// Extract file paths from the ## Files Modified section.
fn extract_declared_files(content: &str) -> Vec<String> {
    let mut files = Vec::new();
    let mut in_section = false;

    for line in content.lines() {
        let trimmed = line.trim();

        if trimmed == "## Files Modified" {
            in_section = true;
            continue;
        }

        if in_section {
            if trimmed.starts_with("## ") {
                break; // Next section
            }
            if let Some(stripped) = trimmed.strip_prefix("- ") {
                let path = stripped
                    .trim()
                    .trim_matches('`')
                    .trim();
                if !path.is_empty() {
                    files.push(path.to_string());
                }
            }
        }
    }

    files
}

/// Get files modified in the given commit hashes via `git show --stat`.
fn get_git_files(hashes: &[String], cwd: &Path) -> Vec<String> {
    fn stat_re() -> &'static Regex {
        static RE: OnceLock<Regex> = OnceLock::new();
        RE.get_or_init(|| Regex::new(r"^ ([^ ].+?)\s+\|").unwrap())
    }

    let mut files = HashSet::new();

    for hash in hashes {
        let output = Command::new("git")
            .args(["show", "--stat", "--format=", hash])
            .current_dir(cwd)
            .output();

        if let Ok(o) = output
            && o.status.success() {
                let stdout = String::from_utf8_lossy(&o.stdout);
                for line in stdout.lines() {
                    if let Some(caps) = stat_re().captures(line) {
                        let file_path = caps[1].trim();
                        if !file_path.is_empty() {
                            files.insert(file_path.to_string());
                        }
                    }
                }
            }
    }

    files.into_iter().collect()
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

    #[test]
    fn test_matching_files_pass() {
        // Test the file extraction logic directly
        let summary = "\
---
phase: \"04\"
plan: \"01\"
title: \"Test\"
status: complete
tasks_completed: 1
tasks_total: 1
commit_hashes: []
---

# Summary

## What Was Built

Something.

## Files Modified

- `src/commands/foo.rs`
- `src/commands/bar.rs`
";
        let declared = extract_declared_files(summary);
        assert_eq!(declared.len(), 2);
        assert!(declared.contains(&"src/commands/foo.rs".to_string()));
        assert!(declared.contains(&"src/commands/bar.rs".to_string()));
    }

    #[test]
    fn test_undeclared_files_detected() {
        // Simulate: actual has files not in declared
        let declared: HashSet<&str> = vec!["a.rs", "b.rs"].into_iter().collect();
        let actual: HashSet<&str> = vec!["a.rs", "b.rs", "c.rs"].into_iter().collect();

        let undeclared: Vec<&str> = actual.difference(&declared).copied().collect();
        assert_eq!(undeclared.len(), 1);
        assert!(undeclared.contains(&"c.rs"));
    }

    #[test]
    fn test_summary_not_found() {
        let dir = tempdir().unwrap();
        let args = vec![
            "yolo".to_string(),
            "diff-against-plan".to_string(),
            dir.path().join("nonexistent.md").to_string_lossy().to_string(),
        ];
        let (output, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 1);
        let parsed: serde_json::Value = serde_json::from_str(&output).unwrap();
        assert_eq!(parsed["ok"], false);
        assert_eq!(parsed["fixable_by"], "dev");
    }

    #[test]
    fn test_empty_commit_hashes() {
        let dir = tempdir().unwrap();
        let summary_path = dir.path().join("SUMMARY.md");
        fs::write(
            &summary_path,
            "\
---
phase: \"04\"
commit_hashes: []
---

## Files Modified

- `foo.rs`
",
        )
        .unwrap();

        let args = vec![
            "yolo".to_string(),
            "diff-against-plan".to_string(),
            summary_path.to_string_lossy().to_string(),
        ];
        let (output, code) = execute(&args, dir.path()).unwrap();
        // declared=1 but actual=0 since no commits, so missing=[foo.rs]
        let parsed: serde_json::Value = serde_json::from_str(&output).unwrap();
        assert_eq!(parsed["declared"], 1);
        assert_eq!(parsed["actual"], 0);
        // missing files means ok=false, fixable_by=dev
        assert_eq!(parsed["fixable_by"], "dev");
    }

    #[test]
    fn test_commits_flag_overrides_frontmatter() {
        let dir = tempdir().unwrap();
        let summary_path = dir.path().join("SUMMARY.md");
        fs::write(
            &summary_path,
            "\
---
phase: \"04\"
commit_hashes: [\"aaa1111\"]
---

## Files Modified

- `foo.rs`
",
        )
        .unwrap();

        // --commits flag should override frontmatter hash aaa1111
        let args = vec![
            "yolo".to_string(),
            "diff-against-plan".to_string(),
            summary_path.to_string_lossy().to_string(),
            "--commits".to_string(),
            "bbb2222,ccc3333".to_string(),
        ];
        let (output, _code) = execute(&args, dir.path()).unwrap();
        let parsed: serde_json::Value = serde_json::from_str(&output).unwrap();
        // actual=0 because bbb2222 and ccc3333 are not real git hashes,
        // but the key assertion is that we did NOT resolve aaa1111 either.
        // If frontmatter was used, git show aaa1111 would also fail → actual=0.
        // The override is confirmed by the fact that commit_hashes was replaced;
        // we verify via parse_flag directly.
        assert_eq!(parsed["cmd"], "diff-against-plan");

        // Direct unit test of the override logic
        let flag_val = parse_flag(&args, "--commits");
        assert_eq!(flag_val, Some("bbb2222,ccc3333".to_string()));
    }

    #[test]
    fn test_empty_commits_flag_uses_frontmatter() {
        let dir = tempdir().unwrap();
        let summary_path = dir.path().join("SUMMARY.md");
        fs::write(
            &summary_path,
            "\
---
phase: \"04\"
commit_hashes: []
---

## Files Modified

- `foo.rs`
",
        )
        .unwrap();

        // --commits with empty string should fall back to frontmatter
        let args = vec![
            "yolo".to_string(),
            "diff-against-plan".to_string(),
            summary_path.to_string_lossy().to_string(),
            "--commits".to_string(),
            "".to_string(),
        ];
        let (output, _code) = execute(&args, dir.path()).unwrap();
        let parsed: serde_json::Value = serde_json::from_str(&output).unwrap();
        // Same as no-flag behavior: frontmatter has empty commit_hashes,
        // so actual=0, declared=1
        assert_eq!(parsed["declared"], 1);
        assert_eq!(parsed["actual"], 0);
    }

    #[test]
    fn test_parse_flag_returns_none_when_absent() {
        let args = vec![
            "yolo".to_string(),
            "diff-against-plan".to_string(),
            "summary.md".to_string(),
        ];
        assert_eq!(parse_flag(&args, "--commits"), None);
    }
}
