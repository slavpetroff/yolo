use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;

const YOLO_MARKER: &str = "YOLO pre-push hook";

const HOOK_CONTENT: &str = r#"#!/usr/bin/env bash
set -euo pipefail
# YOLO pre-push hook — delegates to the latest cached plugin script.
# Installed by YOLO install-hooks.sh. Remove with: rm .git/hooks/pre-push
SCRIPT=$(ls -1 "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/yolo-marketplace/yolo/*/scripts/pre-push-hook.sh 2>/dev/null | sort -V | tail -1)
if [ -n "$SCRIPT" ] && [ -f "$SCRIPT" ]; then
  exec bash "$SCRIPT" "$@"
fi
# Plugin not cached — skip silently
exit 0"#;

/// Install YOLO-managed git hooks. Idempotent.
/// Returns a description of the action taken, or Ok("") for no-op.
pub fn install_hooks() -> Result<String, String> {
    let git_root = find_git_root()?;
    let hooks_dir = git_root.join(".git/hooks");
    fs::create_dir_all(&hooks_dir)
        .map_err(|e| format!("Failed to create hooks dir: {e}"))?;

    let hook_path = hooks_dir.join("pre-push");
    install_pre_push_hook(&hook_path)
}

fn find_git_root() -> Result<PathBuf, String> {
    let output = Command::new("git")
        .args(["rev-parse", "--show-toplevel"])
        .output()
        .map_err(|e| format!("Failed to run git: {e}"))?;

    if !output.status.success() {
        return Err("Not inside a git repository".to_string());
    }

    let root = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if root.is_empty() {
        return Err("git rev-parse returned empty".to_string());
    }
    Ok(PathBuf::from(root))
}

fn install_pre_push_hook(hook_path: &Path) -> Result<String, String> {
    if hook_path.exists() {
        // Check if it's a symlink (old-style YOLO hook)
        if hook_path.is_symlink() {
            let target = fs::read_link(hook_path)
                .map_err(|e| format!("Failed to read symlink: {e}"))?;
            let target_str = target.to_string_lossy();
            if target_str.contains("pre-push-hook.sh") {
                // Old symlink-style — upgrade to standalone script
                write_hook(hook_path)?;
                return Ok("Upgraded pre-push hook to standalone script".to_string());
            }
            return Ok("pre-push hook exists but is not managed by YOLO -- skipping".to_string());
        }

        // Check if this is our managed hook
        if let Ok(content) = fs::read_to_string(hook_path) {
            if content.contains(YOLO_MARKER) {
                return Ok("pre-push hook already installed".to_string());
            }
        }
        return Ok("pre-push hook exists but is not managed by YOLO -- skipping".to_string());
    }

    // No existing hook — install fresh
    write_hook(hook_path)?;
    Ok("Installed pre-push hook".to_string())
}

fn write_hook(hook_path: &Path) -> Result<(), String> {
    // Remove first in case it's a symlink (fs::write follows symlinks)
    let _ = fs::remove_file(hook_path);
    fs::write(hook_path, HOOK_CONTENT)
        .map_err(|e| format!("Failed to write hook: {e}"))?;
    let mut perms = fs::metadata(hook_path)
        .map_err(|e| format!("Failed to read hook metadata: {e}"))?
        .permissions();
    perms.set_mode(0o755);
    fs::set_permissions(hook_path, perms)
        .map_err(|e| format!("Failed to chmod hook: {e}"))?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    fn setup_hook_dir() -> (tempfile::TempDir, PathBuf) {
        let dir = tempdir().unwrap();
        let hooks_dir = dir.path().join(".git/hooks");
        fs::create_dir_all(&hooks_dir).unwrap();
        (dir, hooks_dir)
    }

    #[test]
    fn test_fresh_install() {
        let (_dir, hooks_dir) = setup_hook_dir();
        let hook = hooks_dir.join("pre-push");

        let result = install_pre_push_hook(&hook).unwrap();
        assert_eq!(result, "Installed pre-push hook");
        assert!(hook.exists());

        let content = fs::read_to_string(&hook).unwrap();
        assert!(content.contains(YOLO_MARKER));

        let mode = fs::metadata(&hook).unwrap().permissions().mode();
        assert_eq!(mode & 0o755, 0o755);
    }

    #[test]
    fn test_already_installed_is_noop() {
        let (_dir, hooks_dir) = setup_hook_dir();
        let hook = hooks_dir.join("pre-push");

        // First install
        install_pre_push_hook(&hook).unwrap();

        // Second install — noop
        let result = install_pre_push_hook(&hook).unwrap();
        assert_eq!(result, "pre-push hook already installed");
    }

    #[test]
    fn test_non_yolo_hook_skipped() {
        let (_dir, hooks_dir) = setup_hook_dir();
        let hook = hooks_dir.join("pre-push");
        fs::write(&hook, "#!/bin/bash\necho custom hook").unwrap();

        let result = install_pre_push_hook(&hook).unwrap();
        assert_eq!(
            result,
            "pre-push hook exists but is not managed by YOLO -- skipping"
        );

        // Verify original content preserved
        let content = fs::read_to_string(&hook).unwrap();
        assert!(content.contains("custom hook"));
    }

    #[test]
    fn test_symlink_yolo_hook_upgraded() {
        let (_dir, hooks_dir) = setup_hook_dir();
        let hook = hooks_dir.join("pre-push");
        let target = hooks_dir.join("pre-push-hook.sh");
        fs::write(&target, "#!/bin/bash\nold hook").unwrap();
        std::os::unix::fs::symlink(&target, &hook).unwrap();

        let result = install_pre_push_hook(&hook).unwrap();
        assert_eq!(result, "Upgraded pre-push hook to standalone script");

        // Should now be a regular file, not symlink
        assert!(!hook.is_symlink());
        let content = fs::read_to_string(&hook).unwrap();
        assert!(content.contains(YOLO_MARKER));
    }

    #[test]
    fn test_symlink_non_yolo_skipped() {
        let (_dir, hooks_dir) = setup_hook_dir();
        let hook = hooks_dir.join("pre-push");
        let target = hooks_dir.join("other-hook.sh");
        fs::write(&target, "#!/bin/bash\nother").unwrap();
        std::os::unix::fs::symlink(&target, &hook).unwrap();

        let result = install_pre_push_hook(&hook).unwrap();
        assert_eq!(
            result,
            "pre-push hook exists but is not managed by YOLO -- skipping"
        );
    }
}
