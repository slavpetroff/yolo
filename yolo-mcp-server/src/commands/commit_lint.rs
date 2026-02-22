use regex::Regex;
use serde_json::json;
use std::path::Path;
use std::process::Command;

/// Validates commit messages against the conventional commit format.
///
/// Usage: yolo commit-lint <commit_range>
///
/// Validates each commit subject matches: ^(feat|fix|test|refactor|perf|docs|style|chore)\([a-z0-9._-]+\): .+
///
/// Exit codes: 0=all valid, 1=violations found
pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    if args.len() < 3 {
        return Err("Usage: yolo commit-lint <commit_range>".to_string());
    }

    let commit_range = &args[2];

    // Run git log to get commit subjects
    let output = Command::new("git")
        .args([
            "log",
            "--pretty=format:%H %s",
            commit_range,
        ])
        .current_dir(cwd)
        .output()
        .map_err(|e| format!("Failed to run git log: {}", e))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("git log failed: {}", stderr));
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let lines: Vec<&str> = stdout.lines().filter(|l| !l.is_empty()).collect();

    let commit_re =
        Regex::new(r"^(feat|fix|test|refactor|perf|docs|style|chore)\([a-z0-9._-]+\): .+")
            .unwrap();

    let mut violations = Vec::new();
    let total = lines.len();
    let mut valid_count = 0u32;

    for line in &lines {
        // Format: <full_hash> <subject>
        let parts: Vec<&str> = line.splitn(2, ' ').collect();
        if parts.len() < 2 {
            continue;
        }
        let hash = parts[0];
        let subject = parts[1];
        let short_hash = if hash.len() >= 7 {
            &hash[..7]
        } else {
            hash
        };

        if commit_re.is_match(subject) {
            valid_count += 1;
        } else {
            violations.push(json!({
                "hash": short_hash,
                "subject": subject,
                "issue": "Does not match conventional commit format: {type}({scope}): {description}"
            }));
        }
    }

    let ok = violations.is_empty();
    let resp = json!({
        "ok": ok,
        "cmd": "commit-lint",
        "total": total,
        "valid": valid_count,
        "violations": violations,
    });

    Ok((resp.to_string(), if ok { 0 } else { 1 }))
}

/// Validate a single commit subject line against conventional commit format.
/// Used for unit testing without git.
fn validate_subject(subject: &str) -> bool {
    let commit_re =
        Regex::new(r"^(feat|fix|test|refactor|perf|docs|style|chore)\([a-z0-9._-]+\): .+")
            .unwrap();
    commit_re.is_match(subject)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_valid_commits_pass() {
        assert!(validate_subject("feat(04-01): create QA agent definition"));
        assert!(validate_subject("fix(router): handle edge case"));
        assert!(validate_subject("chore(yolo): bump version"));
        assert!(validate_subject("test(qa): add unit tests"));
        assert!(validate_subject("refactor(commands): simplify parsing"));
        assert!(validate_subject("perf(compile): reduce allocations"));
        assert!(validate_subject("docs(readme): update install steps"));
        assert!(validate_subject("style(fmt): run rustfmt"));
    }

    #[test]
    fn test_invalid_format_fails() {
        assert!(!validate_subject("Update readme"));
        assert!(!validate_subject("feat: missing scope"));
        assert!(!validate_subject("feat(CAPS): wrong case scope"));
        assert!(!validate_subject("unknown(scope): bad type"));
        assert!(!validate_subject("feat(scope):missing space"));
        assert!(!validate_subject(""));
    }
}
