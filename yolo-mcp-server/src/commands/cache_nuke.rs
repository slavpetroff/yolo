use crate::hooks::utils;
use serde_json::json;
use std::fs;
use std::path::Path;

/// Wipe YOLO caches to prevent stale contamination.
/// --keep-latest: keep latest cached plugin version, remove rest.
/// Output: JSON summary of what was wiped.
pub fn execute(args: &[String], _cwd: &Path) -> Result<(String, i32), String> {
    let keep_latest = args.iter().any(|a| a == "--keep-latest");

    let claude_dir = utils::resolve_claude_dir();
    let plugin_cache_dir = claude_dir
        .join("plugins")
        .join("cache")
        .join("yolo-marketplace")
        .join("yolo");

    let uid = get_uid();

    nuke_caches(&plugin_cache_dir, keep_latest, uid)
}

/// Core cache nuking logic, testable without env var side effects.
fn nuke_caches(
    plugin_cache_dir: &Path,
    keep_latest: bool,
    uid: u32,
) -> Result<(String, i32), String> {
    let mut wiped_plugin_cache = false;
    let mut wiped_temp_caches = false;
    let mut versions_removed: usize = 0;

    // --- 1. Plugin cache ---
    if plugin_cache_dir.is_dir() {
        let mut version_dirs: Vec<std::path::PathBuf> = Vec::new();
        if let Ok(entries) = fs::read_dir(plugin_cache_dir) {
            for entry in entries.flatten() {
                let path = entry.path();
                if path.is_dir() {
                    version_dirs.push(path);
                }
            }
        }
        version_dirs.sort();

        if keep_latest {
            if version_dirs.len() > 1 {
                let to_remove = &version_dirs[..version_dirs.len() - 1];
                versions_removed = to_remove.len();
                for dir in to_remove {
                    let _ = fs::remove_dir_all(dir);
                }
                wiped_plugin_cache = true;
            }
        } else {
            versions_removed = version_dirs.len();
            let _ = fs::remove_dir_all(plugin_cache_dir);
            wiped_plugin_cache = true;
        }
    }

    // --- 2. Temp caches (statusline + update check) ---
    let temp_patterns = collect_temp_files(uid);
    if !temp_patterns.is_empty() {
        for f in &temp_patterns {
            let _ = fs::remove_file(f);
        }
        wiped_temp_caches = true;
    }

    let summary = json!({
        "wiped": {
            "plugin_cache": wiped_plugin_cache,
            "temp_caches": wiped_temp_caches,
            "versions_removed": versions_removed,
        }
    });

    Ok((summary.to_string(), 0))
}

/// Get the current user's UID.
fn get_uid() -> u32 {
    #[cfg(unix)]
    {
        unsafe { libc::getuid() }
    }
    #[cfg(not(unix))]
    {
        0
    }
}

/// Collect temp files matching yolo patterns for this user.
fn collect_temp_files(uid: u32) -> Vec<std::path::PathBuf> {
    let uid_str = uid.to_string();
    let tmp_dir = Path::new("/tmp");
    let mut matched = Vec::new();

    if let Ok(entries) = fs::read_dir(tmp_dir) {
        for entry in entries.flatten() {
            let name = entry.file_name();
            let name_str = name.to_string_lossy();
            if name_str.starts_with("yolo-") && name_str.contains(&uid_str) {
                matched.push(entry.path());
            }
        }
    }

    matched
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn test_nuke_no_cache_dirs() {
        let dir = TempDir::new().unwrap();
        let cache = dir.path().join("plugins/cache/yolo-marketplace/yolo");
        // Don't create the dir -- it shouldn't exist

        let (output, code) = nuke_caches(&cache, false, 99999).unwrap();
        assert_eq!(code, 0);
        let json: serde_json::Value = serde_json::from_str(&output).unwrap();
        assert_eq!(json["wiped"]["plugin_cache"], false);
        assert_eq!(json["wiped"]["versions_removed"], 0);
    }

    #[test]
    fn test_nuke_wipe_all_versions() {
        let dir = TempDir::new().unwrap();
        let cache = dir.path().join("plugins/cache/yolo-marketplace/yolo");
        fs::create_dir_all(cache.join("1.0.0")).unwrap();
        fs::create_dir_all(cache.join("1.1.0")).unwrap();
        fs::create_dir_all(cache.join("2.0.0")).unwrap();

        let (output, code) = nuke_caches(&cache, false, 99999).unwrap();
        assert_eq!(code, 0);
        let json: serde_json::Value = serde_json::from_str(&output).unwrap();
        assert_eq!(json["wiped"]["plugin_cache"], true);
        assert_eq!(json["wiped"]["versions_removed"], 3);
        assert!(!cache.exists());
    }

    #[test]
    fn test_nuke_keep_latest() {
        let dir = TempDir::new().unwrap();
        let cache = dir.path().join("plugins/cache/yolo-marketplace/yolo");
        fs::create_dir_all(cache.join("1.0.0")).unwrap();
        fs::create_dir_all(cache.join("1.1.0")).unwrap();
        fs::create_dir_all(cache.join("2.0.0")).unwrap();

        let (output, code) = nuke_caches(&cache, true, 99999).unwrap();
        assert_eq!(code, 0);
        let json: serde_json::Value = serde_json::from_str(&output).unwrap();
        assert_eq!(json["wiped"]["plugin_cache"], true);
        assert_eq!(json["wiped"]["versions_removed"], 2);
        // Latest version should remain
        assert!(cache.join("2.0.0").exists());
        assert!(!cache.join("1.0.0").exists());
        assert!(!cache.join("1.1.0").exists());
    }

    #[test]
    fn test_nuke_keep_latest_single_version() {
        let dir = TempDir::new().unwrap();
        let cache = dir.path().join("plugins/cache/yolo-marketplace/yolo");
        fs::create_dir_all(cache.join("1.0.0")).unwrap();

        let (output, code) = nuke_caches(&cache, true, 99999).unwrap();
        assert_eq!(code, 0);
        let json: serde_json::Value = serde_json::from_str(&output).unwrap();
        assert_eq!(json["wiped"]["plugin_cache"], false);
        assert_eq!(json["wiped"]["versions_removed"], 0);
        assert!(cache.join("1.0.0").exists());
    }

    #[test]
    fn test_get_uid() {
        let uid = get_uid();
        assert!(uid < 100_000);
    }

    #[test]
    fn test_collect_temp_files_no_matches() {
        let files = collect_temp_files(99999);
        let _ = files; // Just verify it doesn't panic
    }

    #[test]
    fn test_json_output_shape() {
        let dir = TempDir::new().unwrap();
        let cache = dir.path().join("nonexistent");

        let (output, _) = nuke_caches(&cache, false, 99999).unwrap();
        let json: serde_json::Value = serde_json::from_str(&output).unwrap();
        assert!(json.get("wiped").is_some());
        assert!(json["wiped"].get("plugin_cache").is_some());
        assert!(json["wiped"].get("temp_caches").is_some());
        assert!(json["wiped"].get("versions_removed").is_some());
    }
}
