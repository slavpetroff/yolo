use std::path::Path;
use std::process::Command;

/// Execute the pre-push hook: enforce version file consistency before git push.
/// Returns (output, exit_code).
pub fn execute(_args: &[String], _cwd: &Path) -> Result<(String, i32), String> {
    // Find repo root
    let root = match get_repo_root() {
        Some(r) => r,
        None => {
            return Ok((
                "WARNING: pre-push hook could not determine repo root -- skipping version check"
                    .to_string(),
                0,
            ));
        }
    };

    // Guard: skip if Cargo.toml doesn't exist (not a YOLO repo)
    if !root.join("Cargo.toml").exists() {
        return Ok(("".to_string(), 0));
    }

    // Call bump_version::execute with --verify
    let verify_args = vec![
        "yolo".to_string(),
        "bump-version".to_string(),
        "--verify".to_string(),
    ];
    let root_path = std::path::Path::new(&root);

    match super::bump_version::execute(&verify_args, root_path) {
        Ok((output, code)) => {
            if code != 0 {
                let mut msg = String::new();
                msg.push_str("\nERROR: Push blocked -- version files are out of sync.\n\n");
                // Extract MISMATCH lines
                for line in output.lines() {
                    if line.contains("MISMATCH") || line.contains("mismatch") {
                        msg.push_str(line);
                        msg.push('\n');
                    }
                }
                msg.push_str("\n  Run: yolo bump-version --verify\n");
                msg.push_str("  to see details, then manually sync the 4 version files.\n");
                Ok((msg, 1))
            } else {
                Ok(("".to_string(), 0))
            }
        }
        Err(e) => {
            // Non-fatal: log warning but don't block push
            Ok((format!("WARNING: version check failed: {e}"), 0))
        }
    }
}

fn get_repo_root() -> Option<std::path::PathBuf> {
    let output = Command::new("git")
        .args(["rev-parse", "--show-toplevel"])
        .output()
        .ok()?;

    if !output.status.success() {
        return None;
    }

    let root = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if root.is_empty() {
        None
    } else {
        Some(std::path::PathBuf::from(root))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_get_repo_root() {
        // Running inside a git repo, should find root
        let root = get_repo_root();
        assert!(root.is_some());
        assert!(root.unwrap().join(".git").exists());
    }

    #[test]
    fn test_execute_in_repo() {
        // Execute in the actual repo — should either pass or detect mismatch
        let args = vec!["yolo".to_string(), "pre-push".to_string()];
        let cwd = std::env::current_dir().unwrap();
        let result = execute(&args, &cwd);
        assert!(result.is_ok());
        // Exit code should be 0 or 1 (sync or mismatch)
        let (_, code) = result.unwrap();
        assert!(code == 0 || code == 1);
    }
}
