use std::env;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};

use chrono::Utc;

/// Resolve the Claude config directory.
/// Uses `CLAUDE_CONFIG_DIR` env var if set, otherwise `$HOME/.claude`.
pub fn resolve_claude_dir() -> PathBuf {
    if let Ok(dir) = env::var("CLAUDE_CONFIG_DIR") {
        PathBuf::from(dir)
    } else if let Ok(home) = env::var("HOME") {
        PathBuf::from(home).join(".claude")
    } else {
        PathBuf::from(".claude")
    }
}

/// Resolve the latest versioned plugin cache directory for the YOLO plugin.
/// Looks in `<claude_dir>/plugins/cache/yolo-marketplace/yolo/*/scripts/`
/// and returns the highest version directory.
pub fn resolve_plugin_cache() -> Option<PathBuf> {
    let claude_dir = resolve_claude_dir();
    let cache_base = claude_dir
        .join("plugins")
        .join("cache")
        .join("yolo-marketplace")
        .join("yolo");

    if !cache_base.is_dir() {
        return None;
    }

    let mut versions: Vec<PathBuf> = fs::read_dir(&cache_base)
        .ok()?
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .filter(|p| p.is_dir())
        .collect();

    // Sort by directory name (version strings) — lexicographic works for semver with same-length segments
    versions.sort();
    versions.last().cloned()
}

/// Log a hook error to `.yolo-planning/.hook-errors.log`.
/// Trims to 50 entries (keeps last 30) to prevent unbounded growth.
pub fn log_hook_error(planning_dir: &Path, script_name: &str, exit_code: i32) {
    let log_path = planning_dir.join(".hook-errors.log");
    let ts = Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string();
    let entry = format!("[{}] {} exit={}\n", ts, script_name, exit_code);

    // Append entry
    if let Ok(mut f) = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&log_path)
    {
        let _ = f.write_all(entry.as_bytes());
    }

    // Trim if over 50 lines
    trim_log_file(&log_path, 50, 30);
}

/// Log a freeform message to the hook error log.
pub fn log_hook_message(planning_dir: &Path, message: &str) {
    let log_path = planning_dir.join(".hook-errors.log");
    let ts = Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string();
    let entry = format!("[{}] {}\n", ts, message);

    if let Ok(mut f) = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&log_path)
    {
        let _ = f.write_all(entry.as_bytes());
    }

    trim_log_file(&log_path, 50, 30);
}

/// Trim a log file: if it exceeds `max_lines`, keep only the last `keep_lines`.
fn trim_log_file(path: &Path, max_lines: usize, keep_lines: usize) {
    if let Ok(content) = fs::read_to_string(path) {
        let lines: Vec<&str> = content.lines().collect();
        if lines.len() > max_lines {
            let trimmed: Vec<&str> = lines[lines.len() - keep_lines..].to_vec();
            let mut output = trimmed.join("\n");
            output.push('\n');
            let _ = fs::write(path, output);
        }
    }
}

/// Walk up from `start` to find a directory containing `.yolo-planning/`.
/// Returns the `.yolo-planning` directory path if found.
pub fn get_planning_dir(start: &Path) -> Option<PathBuf> {
    let mut current = start.to_path_buf();
    loop {
        let candidate = current.join(".yolo-planning");
        if candidate.is_dir() {
            return Some(candidate);
        }
        if !current.pop() {
            return None;
        }
    }
}

/// Normalize an agent role name by stripping common prefixes and mapping to canonical names.
/// Examples:
///   "yolo-lead" -> "lead"
///   "@yolo:dev" -> "dev"
///   "yolo:architect" -> "architect"
///   "team-dev-1" -> "dev"
///   "yolo-qa" -> "qa"
///   "debugger" -> "debugger"
pub fn normalize_agent_role(name: &str) -> String {
    let mut s = name.to_string();

    // Strip leading @
    if s.starts_with('@') {
        s = s[1..].to_string();
    }

    // Strip "yolo-" or "yolo:" prefix
    if s.starts_with("yolo-") || s.starts_with("yolo:") {
        s = s[5..].to_string();
    }

    // Strip "team-" prefix
    if s.starts_with("team-") {
        s = s[5..].to_string();
    }

    // Strip trailing numeric suffix (e.g., "dev-1" -> "dev", "dev-02" -> "dev")
    if let Some(idx) = s.rfind('-') {
        let suffix = &s[idx + 1..];
        if !suffix.is_empty() && suffix.chars().all(|c| c.is_ascii_digit()) {
            s = s[..idx].to_string();
        }
    }

    // Map known aliases
    match s.as_str() {
        "leader" => "lead".to_string(),
        "arch" => "architect".to_string(),
        "debug" => "debugger".to_string(),
        other => other.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn test_resolve_claude_dir_with_env() {
        unsafe { env::set_var("CLAUDE_CONFIG_DIR", "/tmp/test-claude-dir") };
        let dir = resolve_claude_dir();
        assert_eq!(dir, PathBuf::from("/tmp/test-claude-dir"));
        unsafe { env::remove_var("CLAUDE_CONFIG_DIR") };
    }

    #[test]
    fn test_resolve_claude_dir_default() {
        unsafe { env::remove_var("CLAUDE_CONFIG_DIR") };
        let dir = resolve_claude_dir();
        let home = env::var("HOME").unwrap_or_default();
        assert_eq!(dir, PathBuf::from(home).join(".claude"));
    }

    #[test]
    fn test_normalize_agent_role_yolo_prefix() {
        assert_eq!(normalize_agent_role("yolo-lead"), "lead");
        assert_eq!(normalize_agent_role("yolo-dev"), "dev");
        assert_eq!(normalize_agent_role("yolo:architect"), "architect");
        assert_eq!(normalize_agent_role("yolo-qa"), "qa");
    }

    #[test]
    fn test_normalize_agent_role_at_prefix() {
        assert_eq!(normalize_agent_role("@yolo:dev"), "dev");
        assert_eq!(normalize_agent_role("@yolo-lead"), "lead");
    }

    #[test]
    fn test_normalize_agent_role_team_prefix() {
        assert_eq!(normalize_agent_role("team-dev-1"), "dev");
        assert_eq!(normalize_agent_role("team-lead"), "lead");
    }

    #[test]
    fn test_normalize_agent_role_numeric_suffix() {
        assert_eq!(normalize_agent_role("dev-1"), "dev");
        assert_eq!(normalize_agent_role("dev-02"), "dev");
        assert_eq!(normalize_agent_role("yolo-dev-3"), "dev");
    }

    #[test]
    fn test_normalize_agent_role_aliases() {
        assert_eq!(normalize_agent_role("leader"), "lead");
        assert_eq!(normalize_agent_role("arch"), "architect");
        assert_eq!(normalize_agent_role("debug"), "debugger");
        assert_eq!(normalize_agent_role("sec"), "sec");
    }

    #[test]
    fn test_normalize_agent_role_passthrough() {
        assert_eq!(normalize_agent_role("debugger"), "debugger");
        assert_eq!(normalize_agent_role("scout"), "scout");
        assert_eq!(normalize_agent_role("docs"), "docs");
    }

    #[test]
    fn test_get_planning_dir_found() {
        let dir = TempDir::new().unwrap();
        let planning = dir.path().join(".yolo-planning");
        fs::create_dir_all(&planning).unwrap();

        let result = get_planning_dir(dir.path());
        assert_eq!(result, Some(planning));
    }

    #[test]
    fn test_get_planning_dir_from_subdir() {
        let dir = TempDir::new().unwrap();
        let planning = dir.path().join(".yolo-planning");
        fs::create_dir_all(&planning).unwrap();
        let sub = dir.path().join("src").join("deep");
        fs::create_dir_all(&sub).unwrap();

        let result = get_planning_dir(&sub);
        assert_eq!(result, Some(planning));
    }

    #[test]
    fn test_get_planning_dir_not_found() {
        let dir = TempDir::new().unwrap();
        // No .yolo-planning created
        let result = get_planning_dir(dir.path());
        assert!(result.is_none());
    }

    #[test]
    fn test_log_hook_error_creates_file() {
        let dir = TempDir::new().unwrap();
        log_hook_error(dir.path(), "test-hook.sh", 1);

        let log_path = dir.path().join(".hook-errors.log");
        assert!(log_path.exists());

        let content = fs::read_to_string(&log_path).unwrap();
        assert!(content.contains("test-hook.sh exit=1"));
    }

    #[test]
    fn test_log_hook_error_trims_under_50() {
        let dir = TempDir::new().unwrap();

        // Write 55 entries — trim fires when crossing 50, keeping 30.
        // Subsequent appends bring it to 34.
        for i in 0..55 {
            log_hook_error(dir.path(), &format!("hook-{}.sh", i), 1);
        }

        let log_path = dir.path().join(".hook-errors.log");
        let content = fs::read_to_string(&log_path).unwrap();
        let lines: Vec<&str> = content.lines().collect();
        // After trim at 51 (keeps 30), then 4 more appends = 34
        assert!(lines.len() <= 50, "Log should never exceed 50 lines, got {}", lines.len());
        // Should contain the latest entries
        assert!(content.contains("hook-54.sh"));
        // Should NOT contain the earliest entries
        assert!(!content.contains("hook-0.sh"));
    }

    #[test]
    fn test_log_hook_message() {
        let dir = TempDir::new().unwrap();
        log_hook_message(dir.path(), "SIGHUP received, cleaning up");

        let log_path = dir.path().join(".hook-errors.log");
        let content = fs::read_to_string(&log_path).unwrap();
        assert!(content.contains("SIGHUP received, cleaning up"));
    }

    #[test]
    fn test_resolve_plugin_cache_missing_dir() {
        unsafe { env::set_var("CLAUDE_CONFIG_DIR", "/tmp/nonexistent-claude-test-dir"); }
        let result = resolve_plugin_cache();
        assert!(result.is_none());
        unsafe { env::remove_var("CLAUDE_CONFIG_DIR"); }
    }
}
