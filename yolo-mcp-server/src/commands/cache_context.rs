use sha2::{Sha256, Digest};
use std::fs;
use std::path::Path;
use std::process::Command;

/// Compute a deterministic cache key from phase, role, config, and git state.
/// Check `.yolo-planning/.cache/context/{hash}.md` for cache hit.
/// Output: "hit {hash} {path}" or "miss {hash}". Exit 0 always.
pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    if args.len() < 4 {
        return Err("Usage: yolo cache-context <phase> <role> [config-path] [plan-path]".to_string());
    }

    let phase = &args[2];
    let role = &args[3];
    let config_path = if args.len() > 4 {
        cwd.join(&args[4])
    } else {
        cwd.join(".yolo-planning/config.json")
    };
    let plan_path = if args.len() > 5 {
        Some(cwd.join(&args[5]))
    } else {
        None
    };
    let cache_dir = cwd.join(".yolo-planning/.cache/context");

    let mut hash_input = format!("phase={}:role={}", phase, role);

    // Plan content SHA-256 (if plan exists)
    if let Some(ref pp) = plan_path
        && pp.is_file() {
            let plan_sum = sha256_file(pp).unwrap_or_else(|| "noplan".to_string());
            hash_input.push_str(&format!(":plan={}", plan_sum));
        }

    // Config V3 flags
    if config_path.is_file() {
        let flags = read_v3_flags(&config_path);
        hash_input.push_str(&format!(":flags={}", flags));
    }

    // Git diff changed files hash
    if is_git_repo(cwd) {
        let changed_sum = git_changed_files_hash(cwd);
        hash_input.push_str(&format!(":changed={}", changed_sum));
    }

    // Codebase mapping fingerprint for applicable roles
    let mapping_roles = ["debugger", "dev", "qa", "lead", "architect"];
    let codebase_dir = cwd.join(".yolo-planning/codebase");
    if mapping_roles.contains(&role.as_str()) && codebase_dir.is_dir() {
        let map_sum = codebase_fingerprint(&codebase_dir);
        hash_input.push_str(&format!(":codebase={}", map_sum));
    }

    // Rolling summary fingerprint
    if config_path.is_file()
        && rolling_summary_enabled(&config_path) {
            let rolling_path = cwd.join(".yolo-planning/ROLLING-CONTEXT.md");
            if rolling_path.is_file() {
                let rolling_sum = sha256_file(&rolling_path).unwrap_or_else(|| "norolling".to_string());
                hash_input.push_str(&format!(":rolling={}", rolling_sum));
            }
        }

    // Compute final hash, truncated to 16 chars
    let hash = sha256_str(&hash_input);
    if hash.is_empty() {
        return Ok(("miss nohash".to_string(), 0));
    }
    let hash = &hash[..16];

    let cached_file = cache_dir.join(format!("{}.md", hash));

    if cached_file.is_file() {
        Ok((format!("hit {} {}", hash, cached_file.display()), 0))
    } else {
        Ok((format!("miss {}", hash), 0))
    }
}

/// SHA-256 of file contents, full hex string.
fn sha256_file(path: &Path) -> Option<String> {
    let data = fs::read(path).ok()?;
    let mut hasher = Sha256::new();
    hasher.update(&data);
    Some(format!("{:x}", hasher.finalize()))
}

/// SHA-256 of a string, full hex string.
fn sha256_str(s: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(s.as_bytes());
    format!("{:x}", hasher.finalize())
}

/// Read V3 config flags as comma-separated string.
fn read_v3_flags(config_path: &Path) -> String {
    let content = match fs::read_to_string(config_path) {
        Ok(c) => c,
        Err(_) => return "false,false,false,false".to_string(),
    };
    let json: serde_json::Value = match serde_json::from_str(&content) {
        Ok(v) => v,
        Err(_) => return "false,false,false,false".to_string(),
    };

    let flags: Vec<String> = [
        "v3_delta_context",
        "v3_context_cache",
        "v3_plan_research_persist",
        "v3_metrics",
    ]
    .iter()
    .map(|key| {
        json.get(key)
            .and_then(|v| v.as_bool())
            .unwrap_or(false)
            .to_string()
    })
    .collect();

    flags.join(",")
}

/// Check if rolling summary is enabled in config.
fn rolling_summary_enabled(config_path: &Path) -> bool {
    let content = fs::read_to_string(config_path).unwrap_or_default();
    let json: serde_json::Value = serde_json::from_str(&content).unwrap_or_default();
    json.get("v3_rolling_summary")
        .and_then(|v| v.as_bool())
        .unwrap_or(false)
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

/// SHA-256 of sorted `git diff --name-only HEAD` output.
fn git_changed_files_hash(cwd: &Path) -> String {
    let output = Command::new("git")
        .args(["diff", "--name-only", "HEAD"])
        .current_dir(cwd)
        .output();

    match output {
        Ok(o) if o.status.success() => {
            let text = String::from_utf8_lossy(&o.stdout);
            let mut files: Vec<&str> = text.lines().filter(|l| !l.is_empty()).collect();
            files.sort();
            sha256_str(&files.join("\n"))
        }
        _ => "nogit".to_string(),
    }
}

/// Fingerprint of codebase mapping directory (file sizes + names).
fn codebase_fingerprint(codebase_dir: &Path) -> String {
    let mut entries: Vec<String> = Vec::new();
    if let Ok(rd) = fs::read_dir(codebase_dir) {
        for entry in rd.flatten() {
            let path = entry.path();
            if path.extension().is_some_and(|e| e == "md")
                && let Ok(meta) = fs::metadata(&path) {
                    entries.push(format!(
                        "{}:{}",
                        path.file_name().unwrap_or_default().to_string_lossy(),
                        meta.len()
                    ));
                }
        }
    }
    entries.sort();
    if entries.is_empty() {
        "nomap".to_string()
    } else {
        sha256_str(&entries.join("\n"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn test_sha256_str_deterministic() {
        let a = sha256_str("hello world");
        let b = sha256_str("hello world");
        assert_eq!(a, b);
        assert_eq!(a.len(), 64); // Full SHA-256 hex
    }

    #[test]
    fn test_sha256_str_different_inputs() {
        let a = sha256_str("input_a");
        let b = sha256_str("input_b");
        assert_ne!(a, b);
    }

    #[test]
    fn test_sha256_file() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("test.txt");
        fs::write(&path, "test content").unwrap();

        let hash = sha256_file(&path);
        assert!(hash.is_some());
        assert_eq!(hash.as_ref().unwrap().len(), 64);

        // Same content produces same hash
        let hash2 = sha256_file(&path);
        assert_eq!(hash, hash2);
    }

    #[test]
    fn test_sha256_file_missing() {
        let result = sha256_file(Path::new("/nonexistent/file.txt"));
        assert!(result.is_none());
    }

    #[test]
    fn test_read_v3_flags_defaults() {
        let dir = TempDir::new().unwrap();
        let config = dir.path().join("config.json");
        fs::write(&config, "{}").unwrap();

        let flags = read_v3_flags(&config);
        assert_eq!(flags, "false,false,false,false");
    }

    #[test]
    fn test_read_v3_flags_some_enabled() {
        let dir = TempDir::new().unwrap();
        let config = dir.path().join("config.json");
        fs::write(
            &config,
            r#"{"v3_delta_context": true, "v3_metrics": true}"#,
        )
        .unwrap();

        let flags = read_v3_flags(&config);
        assert_eq!(flags, "true,false,false,true");
    }

    #[test]
    fn test_read_v3_flags_missing_file() {
        let flags = read_v3_flags(Path::new("/nonexistent/config.json"));
        assert_eq!(flags, "false,false,false,false");
    }

    #[test]
    fn test_rolling_summary_enabled() {
        let dir = TempDir::new().unwrap();
        let config = dir.path().join("config.json");

        fs::write(&config, r#"{"v3_rolling_summary": true}"#).unwrap();
        assert!(rolling_summary_enabled(&config));

        fs::write(&config, r#"{"v3_rolling_summary": false}"#).unwrap();
        assert!(!rolling_summary_enabled(&config));

        fs::write(&config, "{}").unwrap();
        assert!(!rolling_summary_enabled(&config));
    }

    #[test]
    fn test_codebase_fingerprint_empty_dir() {
        let dir = TempDir::new().unwrap();
        let fp = codebase_fingerprint(dir.path());
        assert_eq!(fp, "nomap");
    }

    #[test]
    fn test_codebase_fingerprint_with_files() {
        let dir = TempDir::new().unwrap();
        fs::write(dir.path().join("INDEX.md"), "# Index").unwrap();
        fs::write(dir.path().join("PATTERNS.md"), "# Patterns").unwrap();

        let fp = codebase_fingerprint(dir.path());
        assert_ne!(fp, "nomap");
        assert_eq!(fp.len(), 64);

        // Deterministic
        let fp2 = codebase_fingerprint(dir.path());
        assert_eq!(fp, fp2);
    }

    #[test]
    fn test_execute_cache_miss() {
        let dir = TempDir::new().unwrap();
        let planning = dir.path().join(".yolo-planning");
        fs::create_dir_all(planning.join(".cache/context")).unwrap();

        let args: Vec<String> = vec![
            "yolo".into(),
            "cache-context".into(),
            "1".into(),
            "dev".into(),
        ];
        let (output, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
        assert!(output.starts_with("miss "));
        // Hash should be 16 chars
        let hash = output.strip_prefix("miss ").unwrap();
        assert_eq!(hash.len(), 16);
    }

    #[test]
    fn test_execute_cache_hit() {
        let dir = TempDir::new().unwrap();
        let cache_dir = dir.path().join(".yolo-planning/.cache/context");
        fs::create_dir_all(&cache_dir).unwrap();

        // First call to get the hash
        let args: Vec<String> = vec![
            "yolo".into(),
            "cache-context".into(),
            "1".into(),
            "dev".into(),
        ];
        let (output, _) = execute(&args, dir.path()).unwrap();
        let hash = output.strip_prefix("miss ").unwrap().to_string();

        // Create the cache file
        fs::write(cache_dir.join(format!("{}.md", hash)), "cached content").unwrap();

        // Second call should be a hit
        let (output2, code2) = execute(&args, dir.path()).unwrap();
        assert_eq!(code2, 0);
        assert!(output2.starts_with("hit "));
        assert!(output2.contains(&hash));
    }

    #[test]
    fn test_execute_missing_args() {
        let dir = TempDir::new().unwrap();
        let args: Vec<String> = vec!["yolo".into(), "cache-context".into()];
        let result = execute(&args, dir.path());
        assert!(result.is_err());
    }

    #[test]
    fn test_cache_key_determinism() {
        let dir = TempDir::new().unwrap();
        fs::create_dir_all(dir.path().join(".yolo-planning/.cache/context")).unwrap();

        let args: Vec<String> = vec![
            "yolo".into(),
            "cache-context".into(),
            "2".into(),
            "lead".into(),
        ];
        let (out1, _) = execute(&args, dir.path()).unwrap();
        let (out2, _) = execute(&args, dir.path()).unwrap();
        assert_eq!(out1, out2);
    }

    #[test]
    fn test_cache_key_varies_by_phase() {
        let dir = TempDir::new().unwrap();
        fs::create_dir_all(dir.path().join(".yolo-planning/.cache/context")).unwrap();

        let args1: Vec<String> = vec![
            "yolo".into(),
            "cache-context".into(),
            "1".into(),
            "dev".into(),
        ];
        let args2: Vec<String> = vec![
            "yolo".into(),
            "cache-context".into(),
            "2".into(),
            "dev".into(),
        ];
        let (out1, _) = execute(&args1, dir.path()).unwrap();
        let (out2, _) = execute(&args2, dir.path()).unwrap();
        assert_ne!(out1, out2);
    }

    #[test]
    fn test_cache_key_varies_by_role() {
        let dir = TempDir::new().unwrap();
        fs::create_dir_all(dir.path().join(".yolo-planning/.cache/context")).unwrap();

        let args1: Vec<String> = vec![
            "yolo".into(),
            "cache-context".into(),
            "1".into(),
            "dev".into(),
        ];
        let args2: Vec<String> = vec![
            "yolo".into(),
            "cache-context".into(),
            "1".into(),
            "lead".into(),
        ];
        let (out1, _) = execute(&args1, dir.path()).unwrap();
        let (out2, _) = execute(&args2, dir.path()).unwrap();
        assert_ne!(out1, out2);
    }
}
