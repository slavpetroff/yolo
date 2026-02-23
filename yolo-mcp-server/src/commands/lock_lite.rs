use super::feature_flags::{self, FeatureFlag};
use chrono::Utc;
use serde_json::{json, Value};
use std::fs;
use std::path::{Path, PathBuf};

/// Get the locks directory path.
fn locks_dir(cwd: &Path) -> PathBuf {
    cwd.join(".yolo-planning").join(".locks")
}

/// Sanitize a resource name into a safe filename.
fn lock_filename(resource: &str) -> String {
    resource.replace(['/', '\\'], "__").replace(' ', "_")
}

/// Acquire a lock on a resource. Creates a lock file with metadata.
/// Returns Ok with lock info on success, Err if lock already held by another owner.
pub fn acquire(resource: &str, owner: &str, cwd: &Path) -> Result<Value, Value> {
    let dir = locks_dir(cwd);
    let _ = fs::create_dir_all(&dir);

    let filename = lock_filename(resource);
    let lock_path = dir.join(format!("{}.lock", filename));

    // Check if lock already exists
    if lock_path.exists()
        && let Ok(content) = fs::read_to_string(&lock_path)
        && let Ok(existing) = serde_json::from_str::<Value>(&content) {
            let existing_owner = existing.get("owner").and_then(|v| v.as_str()).unwrap_or("");
            if existing_owner == owner {
                // Same owner, re-entrant acquire
                return Ok(json!({
                    "action": "acquire",
                    "result": "already_held",
                    "resource": resource,
                    "owner": owner,
                }));
            }
            return Err(json!({
                "action": "acquire",
                "result": "conflict",
                "resource": resource,
                "held_by": existing_owner,
                "requested_by": owner,
            }));
        }

    let ts = Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string();
    let lock_data = json!({
        "resource": resource,
        "owner": owner,
        "acquired_at": ts,
    });

    fs::write(&lock_path, serde_json::to_string_pretty(&lock_data).unwrap())
        .map_err(|e| json!({"action": "acquire", "result": "error", "error": e.to_string()}))?;

    Ok(json!({
        "action": "acquire",
        "result": "acquired",
        "resource": resource,
        "owner": owner,
        "acquired_at": ts,
    }))
}

/// Release a lock on a resource. Removes the lock file.
pub fn release(resource: &str, owner: &str, cwd: &Path) -> Result<Value, Value> {
    let dir = locks_dir(cwd);
    let filename = lock_filename(resource);
    let lock_path = dir.join(format!("{}.lock", filename));

    if !lock_path.exists() {
        return Ok(json!({
            "action": "release",
            "result": "not_held",
            "resource": resource,
        }));
    }

    // Verify ownership before release
    if let Ok(content) = fs::read_to_string(&lock_path)
        && let Ok(existing) = serde_json::from_str::<Value>(&content) {
            let existing_owner = existing.get("owner").and_then(|v| v.as_str()).unwrap_or("");
            if existing_owner != owner {
                return Err(json!({
                    "action": "release",
                    "result": "not_owner",
                    "resource": resource,
                    "held_by": existing_owner,
                    "requested_by": owner,
                }));
            }
        }

    fs::remove_file(&lock_path)
        .map_err(|e| json!({"action": "release", "result": "error", "error": e.to_string()}))?;

    Ok(json!({
        "action": "release",
        "result": "released",
        "resource": resource,
        "owner": owner,
    }))
}

/// Check for lock conflicts on a set of resources.
/// Returns a list of resources that are currently locked by others.
pub fn check(resources: &[&str], owner: &str, cwd: &Path) -> Value {
    let dir = locks_dir(cwd);
    let mut conflicts = Vec::new();
    let mut available = Vec::new();

    for &resource in resources {
        let filename = lock_filename(resource);
        let lock_path = dir.join(format!("{}.lock", filename));

        if lock_path.exists()
            && let Ok(content) = fs::read_to_string(&lock_path)
            && let Ok(existing) = serde_json::from_str::<Value>(&content) {
                let existing_owner = existing.get("owner").and_then(|v| v.as_str()).unwrap_or("");
                if existing_owner != owner {
                    conflicts.push(json!({
                        "resource": resource,
                        "held_by": existing_owner,
                    }));
                    continue;
                }
            }
        available.push(resource);
    }

    json!({
        "action": "check",
        "conflicts": conflicts,
        "available": available,
        "has_conflicts": !conflicts.is_empty(),
    })
}

/// CLI entry point: `yolo lock <action> <resource> [--owner=<owner>]`
pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    if args.len() < 4 {
        return Err("Usage: yolo lock <acquire|release|check> <resource> [--owner=<owner>]".to_string());
    }

    if !feature_flags::is_enabled(FeatureFlag::V3LockLite, cwd) {
        return Ok((json!({"result": "skip", "reason": "v3_lock_lite=false"}).to_string(), 0));
    }

    let action = &args[2];
    let resource = &args[3];

    // Parse owner from flags or default
    let mut owner = "unknown".to_string();
    for arg in args.iter().skip(4) {
        if arg.starts_with("--owner=") {
            owner = arg.replace("--owner=", "");
        }
    }

    match action.as_str() {
        "acquire" => {
            match acquire(resource, &owner, cwd) {
                Ok(v) => Ok((v.to_string(), 0)),
                Err(v) => Ok((v.to_string(), 2)),
            }
        }
        "release" => {
            match release(resource, &owner, cwd) {
                Ok(v) => Ok((v.to_string(), 0)),
                Err(v) => Ok((v.to_string(), 1)),
            }
        }
        "check" => {
            // For check, collect all resources from remaining non-flag args
            let resources: Vec<&str> = args.iter().skip(3)
                .filter(|a| !a.starts_with("--"))
                .map(|s| s.as_str())
                .collect();
            let result = check(&resources, &owner, cwd);
            let code = if result.get("has_conflicts").and_then(|v| v.as_bool()).unwrap_or(false) { 2 } else { 0 };
            Ok((result.to_string(), code))
        }
        _ => Err(format!("Unknown lock action: {}. Use acquire, release, or check.", action)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn setup_test_env(enabled: bool) -> TempDir {
        let dir = TempDir::new().unwrap();
        let planning_dir = dir.path().join(".yolo-planning");
        fs::create_dir_all(&planning_dir).unwrap();
        let config = json!({"v3_lock_lite": enabled});
        fs::write(planning_dir.join("config.json"), config.to_string()).unwrap();
        dir
    }

    #[test]
    fn test_skip_when_disabled() {
        let dir = setup_test_env(false);
        let args = vec!["yolo".into(), "lock".into(), "acquire".into(), "res".into()];
        let (out, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
        assert!(out.contains("v3_lock_lite=false"));
    }

    #[test]
    fn test_acquire_and_release() {
        let dir = setup_test_env(true);
        let result = acquire("src/main.rs", "dev-1", dir.path()).unwrap();
        assert_eq!(result["result"], "acquired");

        let result = release("src/main.rs", "dev-1", dir.path()).unwrap();
        assert_eq!(result["result"], "released");
    }

    #[test]
    fn test_acquire_conflict() {
        let dir = setup_test_env(true);
        acquire("src/main.rs", "dev-1", dir.path()).unwrap();
        let result = acquire("src/main.rs", "dev-2", dir.path());
        assert!(result.is_err());
        let err = result.unwrap_err();
        assert_eq!(err["result"], "conflict");
        assert_eq!(err["held_by"], "dev-1");
    }

    #[test]
    fn test_acquire_reentrant() {
        let dir = setup_test_env(true);
        acquire("src/main.rs", "dev-1", dir.path()).unwrap();
        let result = acquire("src/main.rs", "dev-1", dir.path()).unwrap();
        assert_eq!(result["result"], "already_held");
    }

    #[test]
    fn test_release_not_held() {
        let dir = setup_test_env(true);
        let result = release("src/main.rs", "dev-1", dir.path()).unwrap();
        assert_eq!(result["result"], "not_held");
    }

    #[test]
    fn test_release_wrong_owner() {
        let dir = setup_test_env(true);
        acquire("src/main.rs", "dev-1", dir.path()).unwrap();
        let result = release("src/main.rs", "dev-2", dir.path());
        assert!(result.is_err());
        let err = result.unwrap_err();
        assert_eq!(err["result"], "not_owner");
    }

    #[test]
    fn test_check_no_conflicts() {
        let dir = setup_test_env(true);
        let result = check(&["src/a.rs", "src/b.rs"], "dev-1", dir.path());
        assert_eq!(result["has_conflicts"], false);
        assert_eq!(result["available"].as_array().unwrap().len(), 2);
    }

    #[test]
    fn test_check_with_conflicts() {
        let dir = setup_test_env(true);
        acquire("src/a.rs", "dev-1", dir.path()).unwrap();
        let result = check(&["src/a.rs", "src/b.rs"], "dev-2", dir.path());
        assert_eq!(result["has_conflicts"], true);
        assert_eq!(result["conflicts"].as_array().unwrap().len(), 1);
        assert_eq!(result["available"].as_array().unwrap().len(), 1);
    }

    #[test]
    fn test_check_own_lock_not_conflict() {
        let dir = setup_test_env(true);
        acquire("src/a.rs", "dev-1", dir.path()).unwrap();
        let result = check(&["src/a.rs"], "dev-1", dir.path());
        assert_eq!(result["has_conflicts"], false);
    }

    #[test]
    fn test_lock_filename_sanitization() {
        assert_eq!(lock_filename("src/main.rs"), "src__main.rs");
        assert_eq!(lock_filename("src\\main.rs"), "src__main.rs");
        assert_eq!(lock_filename("my file.txt"), "my_file.txt");
    }

    #[test]
    fn test_missing_args() {
        let dir = setup_test_env(true);
        let args = vec!["yolo".into(), "lock".into()];
        assert!(execute(&args, dir.path()).is_err());
    }

    #[test]
    fn test_cli_acquire_release() {
        let dir = setup_test_env(true);
        let args = vec![
            "yolo".into(), "lock".into(), "acquire".into(),
            "myfile".into(), "--owner=agent-1".into(),
        ];
        let (out, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
        assert!(out.contains("acquired"));

        let args = vec![
            "yolo".into(), "lock".into(), "release".into(),
            "myfile".into(), "--owner=agent-1".into(),
        ];
        let (out, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
        assert!(out.contains("released"));
    }

    #[test]
    fn test_cli_acquire_conflict_exit_code() {
        let dir = setup_test_env(true);
        // First acquire succeeds
        let args1 = vec![
            "yolo".into(), "lock".into(), "acquire".into(),
            "res".into(), "--owner=dev-1".into(),
        ];
        let (_, code1) = execute(&args1, dir.path()).unwrap();
        assert_eq!(code1, 0);
        // Conflict returns exit code 2
        let args2 = vec![
            "yolo".into(), "lock".into(), "acquire".into(),
            "res".into(), "--owner=dev-2".into(),
        ];
        let (out, code2) = execute(&args2, dir.path()).unwrap();
        assert_eq!(code2, 2);
        assert!(out.contains("conflict"));
    }

    #[test]
    fn test_cli_check_conflict_exit_code() {
        let dir = setup_test_env(true);
        acquire("src/a.rs", "dev-1", dir.path()).unwrap();
        let args = vec![
            "yolo".into(), "lock".into(), "check".into(),
            "src/a.rs".into(), "--owner=dev-2".into(),
        ];
        let (_, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 2);
    }

    #[test]
    fn test_cli_release_wrong_owner_exit_code() {
        let dir = setup_test_env(true);
        acquire("res".into(), "dev-1", dir.path()).unwrap();
        let args = vec![
            "yolo".into(), "lock".into(), "release".into(),
            "res".into(), "--owner=dev-2".into(),
        ];
        let (_, code) = execute(&args, dir.path()).unwrap();
        // Wrong-owner release stays at exit code 1 (different error class)
        assert_eq!(code, 1);
    }
}
