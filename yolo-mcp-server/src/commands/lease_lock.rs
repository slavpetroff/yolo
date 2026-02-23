use super::feature_flags::{self, FeatureFlag};
use chrono::Utc;
use serde_json::{json, Value};
use std::fs;
use std::path::{Path, PathBuf};

const DEFAULT_TTL_SECS: u64 = 300;

/// Get the locks directory path.
fn locks_dir(cwd: &Path) -> PathBuf {
    cwd.join(".yolo-planning").join(".locks")
}

/// Sanitize a resource name into a safe filename.
fn lock_filename(resource: &str) -> String {
    resource.replace('/', "__").replace('\\', "__").replace(' ', "_")
}

/// Read a lease lock file and parse its JSON content.
fn read_lease(lock_path: &Path) -> Option<Value> {
    fs::read_to_string(lock_path).ok().and_then(|c| serde_json::from_str(&c).ok())
}

/// Check if a lease has expired based on its TTL.
fn is_expired(lock_data: &Value) -> bool {
    let acquired_at = lock_data.get("acquired_at").and_then(|v| v.as_str()).unwrap_or("");
    let ttl_secs = lock_data.get("ttl_secs").and_then(|v| v.as_u64()).unwrap_or(DEFAULT_TTL_SECS);

    if acquired_at.is_empty() {
        return true;
    }

    if let Ok(acquired) = chrono::DateTime::parse_from_rfc3339(acquired_at) {
        let now = Utc::now();
        let elapsed = (now - acquired.with_timezone(&Utc)).num_seconds();
        return elapsed as u64 > ttl_secs;
    }

    // Also try the simpler format
    if let Ok(acquired) = chrono::NaiveDateTime::parse_from_str(acquired_at, "%Y-%m-%dT%H:%M:%SZ") {
        let now = Utc::now().naive_utc();
        let elapsed = (now - acquired).num_seconds();
        return elapsed as u64 > ttl_secs;
    }

    true // Can't parse timestamp, treat as expired
}

/// Acquire a lease lock with TTL.
pub fn acquire(resource: &str, owner: &str, ttl_secs: u64, cwd: &Path) -> Result<Value, Value> {
    let dir = locks_dir(cwd);
    let _ = fs::create_dir_all(&dir);

    let filename = lock_filename(resource);
    let lock_path = dir.join(format!("{}.lease", filename));

    // Check existing lease
    if lock_path.exists() {
        if let Some(existing) = read_lease(&lock_path) {
            let existing_owner = existing.get("owner").and_then(|v| v.as_str()).unwrap_or("");

            if is_expired(&existing) {
                // Expired lease, take it over
                let _ = fs::remove_file(&lock_path);
            } else if existing_owner == owner {
                // Re-entrant acquire, renew
                return renew(resource, owner, ttl_secs, cwd);
            } else {
                let hard = feature_flags::is_enabled(FeatureFlag::V2HardGates, cwd);
                return Err(json!({
                    "action": "acquire",
                    "result": "conflict",
                    "resource": resource,
                    "held_by": existing_owner,
                    "requested_by": owner,
                    "hard_enforcement": hard,
                }));
            }
        }
    }

    let ts = Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string();
    let lock_data = json!({
        "resource": resource,
        "owner": owner,
        "acquired_at": ts,
        "ttl_secs": ttl_secs,
        "type": "lease",
    });

    fs::write(&lock_path, serde_json::to_string_pretty(&lock_data).unwrap())
        .map_err(|e| json!({"action": "acquire", "result": "error", "error": e.to_string()}))?;

    Ok(json!({
        "action": "acquire",
        "result": "acquired",
        "resource": resource,
        "owner": owner,
        "acquired_at": ts,
        "ttl_secs": ttl_secs,
    }))
}

/// Renew an existing lease lock, resetting its TTL.
pub fn renew(resource: &str, owner: &str, ttl_secs: u64, cwd: &Path) -> Result<Value, Value> {
    let dir = locks_dir(cwd);
    let filename = lock_filename(resource);
    let lock_path = dir.join(format!("{}.lease", filename));

    if !lock_path.exists() {
        return Err(json!({
            "action": "renew",
            "result": "not_held",
            "resource": resource,
        }));
    }

    if let Some(existing) = read_lease(&lock_path) {
        let existing_owner = existing.get("owner").and_then(|v| v.as_str()).unwrap_or("");
        if existing_owner != owner {
            return Err(json!({
                "action": "renew",
                "result": "not_owner",
                "resource": resource,
                "held_by": existing_owner,
                "requested_by": owner,
            }));
        }
    }

    let ts = Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string();
    let lock_data = json!({
        "resource": resource,
        "owner": owner,
        "acquired_at": ts,
        "ttl_secs": ttl_secs,
        "type": "lease",
    });

    fs::write(&lock_path, serde_json::to_string_pretty(&lock_data).unwrap())
        .map_err(|e| json!({"action": "renew", "result": "error", "error": e.to_string()}))?;

    Ok(json!({
        "action": "renew",
        "result": "renewed",
        "resource": resource,
        "owner": owner,
        "acquired_at": ts,
        "ttl_secs": ttl_secs,
    }))
}

/// Release a lease lock.
pub fn release(resource: &str, owner: &str, cwd: &Path) -> Result<Value, Value> {
    let dir = locks_dir(cwd);
    let filename = lock_filename(resource);
    let lock_path = dir.join(format!("{}.lease", filename));

    if !lock_path.exists() {
        return Ok(json!({
            "action": "release",
            "result": "not_held",
            "resource": resource,
        }));
    }

    if let Some(existing) = read_lease(&lock_path) {
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

/// Clean up all expired lease locks. Returns the count of cleaned leases.
pub fn cleanup_expired(cwd: &Path) -> Value {
    let dir = locks_dir(cwd);
    let mut cleaned = Vec::new();

    if !dir.exists() {
        return json!({"action": "cleanup", "cleaned": 0, "resources": []});
    }

    if let Ok(entries) = fs::read_dir(&dir) {
        for entry in entries.flatten() {
            if let Some(name) = entry.file_name().to_str() {
                if name.ends_with(".lease") {
                    if let Some(data) = read_lease(&entry.path()) {
                        if is_expired(&data) {
                            let resource = data.get("resource").and_then(|v| v.as_str()).unwrap_or("unknown").to_string();
                            let _ = fs::remove_file(entry.path());
                            cleaned.push(resource);
                        }
                    }
                }
            }
        }
    }

    let count = cleaned.len();
    json!({
        "action": "cleanup",
        "cleaned": count,
        "resources": cleaned,
    })
}

/// CLI entry point: `yolo lease-lock <action> <resource> [--owner=<owner>] [--ttl=<seconds>]`
pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    if args.len() < 3 {
        return Err("Usage: yolo lease-lock <acquire|release|renew|cleanup> [resource] [--owner=<owner>] [--ttl=<seconds>]".to_string());
    }

    if !feature_flags::is_enabled(FeatureFlag::V3LockLite, cwd) {
        return Ok((json!({"result": "skip", "reason": "v3_lock_lite=false"}).to_string(), 0));
    }

    let action = &args[2];

    // Parse flags
    let mut owner = "unknown".to_string();
    let mut ttl_secs = DEFAULT_TTL_SECS;
    let mut resource: Option<String> = None;

    for arg in args.iter().skip(3) {
        if arg.starts_with("--owner=") {
            owner = arg.replace("--owner=", "");
        } else if arg.starts_with("--ttl=") {
            ttl_secs = arg.replace("--ttl=", "").parse().unwrap_or(DEFAULT_TTL_SECS);
        } else if resource.is_none() {
            resource = Some(arg.clone());
        }
    }

    match action.as_str() {
        "acquire" => {
            let res = resource.ok_or("Missing resource argument")?;
            match acquire(&res, &owner, ttl_secs, cwd) {
                Ok(v) => Ok((v.to_string(), 0)),
                Err(v) => {
                    let code = if feature_flags::is_enabled(FeatureFlag::V2HardGates, cwd) { 2 } else { 1 };
                    Ok((v.to_string(), code))
                }
            }
        }
        "release" => {
            let res = resource.ok_or("Missing resource argument")?;
            match release(&res, &owner, cwd) {
                Ok(v) => Ok((v.to_string(), 0)),
                Err(v) => Ok((v.to_string(), 1)),
            }
        }
        "renew" => {
            let res = resource.ok_or("Missing resource argument")?;
            match renew(&res, &owner, ttl_secs, cwd) {
                Ok(v) => Ok((v.to_string(), 0)),
                Err(v) => Ok((v.to_string(), 1)),
            }
        }
        "cleanup" => {
            let result = cleanup_expired(cwd);
            Ok((result.to_string(), 0))
        }
        _ => Err(format!("Unknown lease-lock action: {}. Use acquire, release, renew, or cleanup.", action)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn setup_test_env(lock_enabled: bool, hard_gates: bool) -> TempDir {
        let dir = TempDir::new().unwrap();
        let planning_dir = dir.path().join(".yolo-planning");
        fs::create_dir_all(&planning_dir).unwrap();
        let config = json!({"v3_lock_lite": lock_enabled, "v2_hard_gates": hard_gates});
        fs::write(planning_dir.join("config.json"), config.to_string()).unwrap();
        dir
    }

    #[test]
    fn test_skip_when_disabled() {
        let dir = setup_test_env(false, false);
        let args = vec!["yolo".into(), "lease-lock".into(), "acquire".into(), "res".into()];
        let (out, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
        assert!(out.contains("v3_lock_lite=false"));
    }

    #[test]
    fn test_acquire_and_release() {
        let dir = setup_test_env(true, false);
        let result = acquire("src/main.rs", "dev-1", 300, dir.path()).unwrap();
        assert_eq!(result["result"], "acquired");
        assert_eq!(result["ttl_secs"], 300);

        let result = release("src/main.rs", "dev-1", dir.path()).unwrap();
        assert_eq!(result["result"], "released");
    }

    #[test]
    fn test_acquire_conflict() {
        let dir = setup_test_env(true, false);
        acquire("src/main.rs", "dev-1", 300, dir.path()).unwrap();
        let result = acquire("src/main.rs", "dev-2", 300, dir.path());
        assert!(result.is_err());
        let err = result.unwrap_err();
        assert_eq!(err["result"], "conflict");
    }

    #[test]
    fn test_acquire_expired_takeover() {
        let dir = setup_test_env(true, false);
        // Create an already-expired lease
        let lock_dir = locks_dir(dir.path());
        fs::create_dir_all(&lock_dir).unwrap();
        let lock_data = json!({
            "resource": "src/main.rs",
            "owner": "dev-1",
            "acquired_at": "2020-01-01T00:00:00Z",
            "ttl_secs": 1,
            "type": "lease",
        });
        fs::write(lock_dir.join("src__main.rs.lease"), serde_json::to_string_pretty(&lock_data).unwrap()).unwrap();

        // Should succeed because old lease is expired
        let result = acquire("src/main.rs", "dev-2", 300, dir.path()).unwrap();
        assert_eq!(result["result"], "acquired");
        assert_eq!(result["owner"], "dev-2");
    }

    #[test]
    fn test_renew() {
        let dir = setup_test_env(true, false);
        acquire("src/main.rs", "dev-1", 300, dir.path()).unwrap();
        let result = renew("src/main.rs", "dev-1", 600, dir.path()).unwrap();
        assert_eq!(result["result"], "renewed");
        assert_eq!(result["ttl_secs"], 600);
    }

    #[test]
    fn test_renew_not_held() {
        let dir = setup_test_env(true, false);
        let result = renew("src/main.rs", "dev-1", 300, dir.path());
        assert!(result.is_err());
        let err = result.unwrap_err();
        assert_eq!(err["result"], "not_held");
    }

    #[test]
    fn test_renew_wrong_owner() {
        let dir = setup_test_env(true, false);
        acquire("src/main.rs", "dev-1", 300, dir.path()).unwrap();
        let result = renew("src/main.rs", "dev-2", 300, dir.path());
        assert!(result.is_err());
        let err = result.unwrap_err();
        assert_eq!(err["result"], "not_owner");
    }

    #[test]
    fn test_cleanup_expired() {
        let dir = setup_test_env(true, false);
        let lock_dir = locks_dir(dir.path());
        fs::create_dir_all(&lock_dir).unwrap();

        // Create expired lease
        let expired = json!({
            "resource": "old.rs",
            "owner": "dev-1",
            "acquired_at": "2020-01-01T00:00:00Z",
            "ttl_secs": 1,
            "type": "lease",
        });
        fs::write(lock_dir.join("old.rs.lease"), serde_json::to_string_pretty(&expired).unwrap()).unwrap();

        // Create fresh lease
        let ts = Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string();
        let fresh = json!({
            "resource": "new.rs",
            "owner": "dev-2",
            "acquired_at": ts,
            "ttl_secs": 3600,
            "type": "lease",
        });
        fs::write(lock_dir.join("new.rs.lease"), serde_json::to_string_pretty(&fresh).unwrap()).unwrap();

        let result = cleanup_expired(dir.path());
        assert_eq!(result["cleaned"], 1);
        assert!(result["resources"].as_array().unwrap().iter().any(|v| v == "old.rs"));

        // Fresh lease should still exist
        assert!(lock_dir.join("new.rs.lease").exists());
        assert!(!lock_dir.join("old.rs.lease").exists());
    }

    #[test]
    fn test_hard_gates_enforcement() {
        let dir = setup_test_env(true, true);
        acquire("src/main.rs", "dev-1", 300, dir.path()).unwrap();

        // With hard gates enabled, conflict should return exit code 2
        let args = vec![
            "yolo".into(), "lease-lock".into(), "acquire".into(),
            "src/main.rs".into(), "--owner=dev-2".into(),
        ];
        let (out, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 2);
        assert!(out.contains("conflict"));
    }

    #[test]
    fn test_soft_gates_enforcement() {
        let dir = setup_test_env(true, false);
        acquire("src/main.rs", "dev-1", 300, dir.path()).unwrap();

        // Without hard gates, conflict returns exit code 1
        let args = vec![
            "yolo".into(), "lease-lock".into(), "acquire".into(),
            "src/main.rs".into(), "--owner=dev-2".into(),
        ];
        let (out, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 1);
        assert!(out.contains("conflict"));
    }

    #[test]
    fn test_cli_ttl_flag() {
        let dir = setup_test_env(true, false);
        let args = vec![
            "yolo".into(), "lease-lock".into(), "acquire".into(),
            "myfile".into(), "--owner=agent-1".into(), "--ttl=60".into(),
        ];
        let (out, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
        let parsed: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(parsed["ttl_secs"], 60);
    }

    #[test]
    fn test_reentrant_acquire_renews() {
        let dir = setup_test_env(true, false);
        acquire("src/main.rs", "dev-1", 300, dir.path()).unwrap();
        // Same owner re-acquires → should renew
        let result = acquire("src/main.rs", "dev-1", 600, dir.path()).unwrap();
        assert_eq!(result["result"], "renewed");
        assert_eq!(result["ttl_secs"], 600);
    }

    #[test]
    fn test_release_not_held() {
        let dir = setup_test_env(true, false);
        let result = release("src/main.rs", "dev-1", dir.path()).unwrap();
        assert_eq!(result["result"], "not_held");
    }

    #[test]
    fn test_missing_args() {
        let dir = setup_test_env(true, false);
        let args = vec!["yolo".into(), "lease-lock".into()];
        assert!(execute(&args, dir.path()).is_err());
    }
}
