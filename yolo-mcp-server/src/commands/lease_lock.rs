use super::domain_types::ResourceId;
use super::feature_flags::{self, FeatureFlag};
use super::log_event;
use chrono::Utc;
use serde_json::{json, Value};
use std::fs;
use std::path::{Path, PathBuf};

const DEFAULT_TTL_SECS: u64 = 300;

/// Read task_lease_ttl_secs from `.yolo-planning/config.json`, defaulting to 300.
fn read_task_lease_ttl(cwd: &Path) -> u64 {
    let config_path = cwd.join(".yolo-planning").join("config.json");
    if let Ok(content) = fs::read_to_string(&config_path)
        && let Ok(config) = serde_json::from_str::<Value>(&content)
        && let Some(ttl) = config.get("task_lease_ttl_secs").and_then(|v| v.as_u64()) {
            return ttl;
        }
    DEFAULT_TTL_SECS
}

/// Get the locks directory path.
fn locks_dir(cwd: &Path) -> PathBuf {
    cwd.join(".yolo-planning").join(".locks")
}

/// Sanitize a resource name into a safe filename.
fn lock_filename(resource: &str) -> String {
    resource.replace(['/', '\\'], "__").replace(' ', "_")
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

/// Check if a lease for the given resource exists and is expired.
/// Returns `true` if a lease file exists and has expired, `false` otherwise.
pub fn is_lease_expired(cwd: &Path, resource: &str) -> bool {
    let dir = locks_dir(cwd);
    let filename = lock_filename(resource);
    let lock_path = dir.join(format!("{}.lease", filename));

    if !lock_path.exists() {
        return false;
    }

    match read_lease(&lock_path) {
        Some(data) => is_expired(&data),
        None => false,
    }
}

/// Acquire a lease lock with TTL.
/// If `ttl_secs` equals `DEFAULT_TTL_SECS`, the config value from `task_lease_ttl_secs` is used.
pub fn acquire(resource: &ResourceId, owner: &str, ttl_secs: u64, cwd: &Path) -> Result<Value, Value> {
    let ttl_secs = if ttl_secs == DEFAULT_TTL_SECS {
        read_task_lease_ttl(cwd)
    } else {
        ttl_secs
    };
    let resource_str = resource.as_str();
    let dir = locks_dir(cwd);
    let _ = fs::create_dir_all(&dir);

    let filename = lock_filename(resource_str);
    let lock_path = dir.join(format!("{}.lease", filename));

    // Check existing lease
    if lock_path.exists()
        && let Some(existing) = read_lease(&lock_path) {
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
                    "resource": resource_str,
                    "held_by": existing_owner,
                    "requested_by": owner,
                    "hard_enforcement": hard,
                }));
            }
        }

    let ts = Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string();
    let lock_data = json!({
        "resource": resource_str,
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
        "resource": resource_str,
        "owner": owner,
        "acquired_at": ts,
        "ttl_secs": ttl_secs,
    }))
}

/// Renew an existing lease lock, resetting its TTL.
pub fn renew(resource: &ResourceId, owner: &str, ttl_secs: u64, cwd: &Path) -> Result<Value, Value> {
    let resource_str = resource.as_str();
    let dir = locks_dir(cwd);
    let filename = lock_filename(resource_str);
    let lock_path = dir.join(format!("{}.lease", filename));

    if !lock_path.exists() {
        return Err(json!({
            "action": "renew",
            "result": "not_held",
            "resource": resource_str,
        }));
    }

    if let Some(existing) = read_lease(&lock_path) {
        let existing_owner = existing.get("owner").and_then(|v| v.as_str()).unwrap_or("");
        if existing_owner != owner {
            return Err(json!({
                "action": "renew",
                "result": "not_owner",
                "resource": resource_str,
                "held_by": existing_owner,
                "requested_by": owner,
            }));
        }
    }

    let ts = Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string();
    let lock_data = json!({
        "resource": resource_str,
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
        "resource": resource_str,
        "owner": owner,
        "acquired_at": ts,
        "ttl_secs": ttl_secs,
    }))
}

/// Release a lease lock.
pub fn release(resource: &ResourceId, owner: &str, cwd: &Path) -> Result<Value, Value> {
    let resource_str = resource.as_str();
    let dir = locks_dir(cwd);
    let filename = lock_filename(resource_str);
    let lock_path = dir.join(format!("{}.lease", filename));

    if !lock_path.exists() {
        return Ok(json!({
            "action": "release",
            "result": "not_held",
            "resource": resource_str,
        }));
    }

    if let Some(existing) = read_lease(&lock_path) {
        let existing_owner = existing.get("owner").and_then(|v| v.as_str()).unwrap_or("");
        if existing_owner != owner {
            return Err(json!({
                "action": "release",
                "result": "not_owner",
                "resource": resource_str,
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
        "resource": resource_str,
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
            if let Some(name) = entry.file_name().to_str()
                && name.ends_with(".lease")
                && let Some(data) = read_lease(&entry.path())
                && is_expired(&data) {
                    let resource = data.get("resource").and_then(|v| v.as_str()).unwrap_or("unknown").to_string();
                    let _ = fs::remove_file(entry.path());
                    cleaned.push(resource);
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

/// Scan `.locks/` for expired leases, remove them, log `task_reassigned` events,
/// and return a JSON report with previous owner info.
pub fn reassign_expired_tasks(cwd: &Path) -> Value {
    let dir = locks_dir(cwd);
    let mut reassigned: Vec<Value> = Vec::new();

    if !dir.exists() {
        return json!({"action": "reassign", "reassigned": [], "count": 0});
    }

    if let Ok(entries) = fs::read_dir(&dir) {
        for entry in entries.flatten() {
            if let Some(name) = entry.file_name().to_str()
                && name.ends_with(".lease")
                && let Some(data) = read_lease(&entry.path())
                && is_expired(&data) {
                    let resource = data.get("resource").and_then(|v| v.as_str()).unwrap_or("unknown").to_string();
                    let prev_owner = data.get("owner").and_then(|v| v.as_str()).unwrap_or("unknown").to_string();
                    let acquired_at = data.get("owner").and_then(|v| v.as_str()).unwrap_or("").to_string();

                    let _ = fs::remove_file(entry.path());

                    // Log task_reassigned event if v3_event_log is enabled
                    let _ = log_event::log(
                        "task_reassigned",
                        "0",
                        None,
                        &[
                            ("resource".to_string(), resource.clone()),
                            ("previous_owner".to_string(), prev_owner.clone()),
                            ("reason".to_string(), "lease_expired".to_string()),
                        ],
                        cwd,
                    );

                    reassigned.push(json!({
                        "resource": resource,
                        "previous_owner": prev_owner,
                        "acquired_at": acquired_at,
                    }));
                }
        }
    }

    let count = reassigned.len();
    json!({
        "action": "reassign",
        "reassigned": reassigned,
        "count": count,
    })
}

/// CLI entry point: `yolo lease-lock <action> <resource> [--owner=<owner>] [--ttl=<seconds>]`
pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    if args.len() < 3 {
        return Err("Usage: yolo lease-lock <acquire|release|renew|cleanup|reassign> [resource] [--owner=<owner>] [--ttl=<seconds>]".to_string());
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
            let res = ResourceId::new(resource.ok_or("Missing resource argument")?);
            match acquire(&res, &owner, ttl_secs, cwd) {
                Ok(v) => Ok((v.to_string(), 0)),
                Err(v) => {
                    let code = if feature_flags::is_enabled(FeatureFlag::V2HardGates, cwd) { 2 } else { 1 };
                    Ok((v.to_string(), code))
                }
            }
        }
        "release" => {
            let res = ResourceId::new(resource.ok_or("Missing resource argument")?);
            match release(&res, &owner, cwd) {
                Ok(v) => Ok((v.to_string(), 0)),
                Err(v) => Ok((v.to_string(), 1)),
            }
        }
        "renew" => {
            let res = ResourceId::new(resource.ok_or("Missing resource argument")?);
            match renew(&res, &owner, ttl_secs, cwd) {
                Ok(v) => Ok((v.to_string(), 0)),
                Err(v) => Ok((v.to_string(), 1)),
            }
        }
        "cleanup" => {
            let mut result = cleanup_expired(cwd);
            // Also include reassignment info from expired leases
            let reassign_result = reassign_expired_tasks(cwd);
            if let Some(obj) = result.as_object_mut() {
                obj.insert("reassigned".to_string(), reassign_result["reassigned"].clone());
                obj.insert("reassigned_count".to_string(), reassign_result["count"].clone());
            }
            Ok((result.to_string(), 0))
        }
        "reassign" => {
            let result = reassign_expired_tasks(cwd);
            Ok((result.to_string(), 0))
        }
        _ => Err(format!("Unknown lease-lock action: {}. Use acquire, release, renew, cleanup, or reassign.", action)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn rid(s: &str) -> ResourceId {
        ResourceId::new(s)
    }

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
        let result = acquire(&rid("src/main.rs"), "dev-1", 300, dir.path()).unwrap();
        assert_eq!(result["result"], "acquired");
        assert_eq!(result["ttl_secs"], 300);

        let result = release(&rid("src/main.rs"), "dev-1", dir.path()).unwrap();
        assert_eq!(result["result"], "released");
    }

    #[test]
    fn test_acquire_conflict() {
        let dir = setup_test_env(true, false);
        acquire(&rid("src/main.rs"), "dev-1", 300, dir.path()).unwrap();
        let result = acquire(&rid("src/main.rs"), "dev-2", 300, dir.path());
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
        let result = acquire(&rid("src/main.rs"), "dev-2", 300, dir.path()).unwrap();
        assert_eq!(result["result"], "acquired");
        assert_eq!(result["owner"], "dev-2");
    }

    #[test]
    fn test_renew() {
        let dir = setup_test_env(true, false);
        acquire(&rid("src/main.rs"), "dev-1", 300, dir.path()).unwrap();
        let result = renew(&rid("src/main.rs"), "dev-1", 600, dir.path()).unwrap();
        assert_eq!(result["result"], "renewed");
        assert_eq!(result["ttl_secs"], 600);
    }

    #[test]
    fn test_renew_not_held() {
        let dir = setup_test_env(true, false);
        let result = renew(&rid("src/main.rs"), "dev-1", 300, dir.path());
        assert!(result.is_err());
        let err = result.unwrap_err();
        assert_eq!(err["result"], "not_held");
    }

    #[test]
    fn test_renew_wrong_owner() {
        let dir = setup_test_env(true, false);
        acquire(&rid("src/main.rs"), "dev-1", 300, dir.path()).unwrap();
        let result = renew(&rid("src/main.rs"), "dev-2", 300, dir.path());
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
        acquire(&rid("src/main.rs"), "dev-1", 300, dir.path()).unwrap();

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
        acquire(&rid("src/main.rs"), "dev-1", 300, dir.path()).unwrap();

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
        acquire(&rid("src/main.rs"), "dev-1", 300, dir.path()).unwrap();
        // Same owner re-acquires → should renew
        let result = acquire(&rid("src/main.rs"), "dev-1", 600, dir.path()).unwrap();
        assert_eq!(result["result"], "renewed");
        assert_eq!(result["ttl_secs"], 600);
    }

    #[test]
    fn test_release_not_held() {
        let dir = setup_test_env(true, false);
        let result = release(&rid("src/main.rs"), "dev-1", dir.path()).unwrap();
        assert_eq!(result["result"], "not_held");
    }

    #[test]
    fn test_missing_args() {
        let dir = setup_test_env(true, false);
        let args = vec!["yolo".into(), "lease-lock".into()];
        assert!(execute(&args, dir.path()).is_err());
    }

    #[test]
    fn test_read_task_lease_ttl_default() {
        let dir = setup_test_env(true, false);
        // Config has no task_lease_ttl_secs → default 300
        assert_eq!(read_task_lease_ttl(dir.path()), DEFAULT_TTL_SECS);
    }

    #[test]
    fn test_read_task_lease_ttl_custom() {
        let dir = TempDir::new().unwrap();
        let planning_dir = dir.path().join(".yolo-planning");
        fs::create_dir_all(&planning_dir).unwrap();
        let config = json!({"v3_lock_lite": true, "task_lease_ttl_secs": 120});
        fs::write(planning_dir.join("config.json"), config.to_string()).unwrap();
        assert_eq!(read_task_lease_ttl(dir.path()), 120);
    }

    #[test]
    fn test_acquire_uses_config_ttl() {
        let dir = TempDir::new().unwrap();
        let planning_dir = dir.path().join(".yolo-planning");
        fs::create_dir_all(&planning_dir).unwrap();
        let config = json!({"v3_lock_lite": true, "task_lease_ttl_secs": 180});
        fs::write(planning_dir.join("config.json"), config.to_string()).unwrap();

        // Pass DEFAULT_TTL_SECS (300) → acquire should use config value (180)
        let result = acquire(&rid("src/main.rs"), "dev-1", DEFAULT_TTL_SECS, dir.path()).unwrap();
        assert_eq!(result["result"], "acquired");
        assert_eq!(result["ttl_secs"], 180);
    }

    #[test]
    fn test_reassign_expired_tasks_removes_expired() {
        let dir = setup_test_env(true, false);
        let lock_dir = locks_dir(dir.path());
        fs::create_dir_all(&lock_dir).unwrap();

        // Create two expired leases
        let expired1 = json!({
            "resource": "task-a", "owner": "agent-1",
            "acquired_at": "2020-01-01T00:00:00Z", "ttl_secs": 1, "type": "lease",
        });
        let expired2 = json!({
            "resource": "task-b", "owner": "agent-2",
            "acquired_at": "2020-01-01T00:00:00Z", "ttl_secs": 1, "type": "lease",
        });
        fs::write(lock_dir.join("task-a.lease"), serde_json::to_string_pretty(&expired1).unwrap()).unwrap();
        fs::write(lock_dir.join("task-b.lease"), serde_json::to_string_pretty(&expired2).unwrap()).unwrap();

        // Create a fresh lease that should NOT be reassigned
        let ts = Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string();
        let fresh = json!({
            "resource": "task-c", "owner": "agent-3",
            "acquired_at": ts, "ttl_secs": 3600, "type": "lease",
        });
        fs::write(lock_dir.join("task-c.lease"), serde_json::to_string_pretty(&fresh).unwrap()).unwrap();

        let result = reassign_expired_tasks(dir.path());
        assert_eq!(result["action"], "reassign");
        assert_eq!(result["count"], 2);

        let reassigned = result["reassigned"].as_array().unwrap();
        assert_eq!(reassigned.len(), 2);

        // Verify previous owner info is included
        let owners: Vec<&str> = reassigned.iter().map(|r| r["previous_owner"].as_str().unwrap()).collect();
        assert!(owners.contains(&"agent-1"));
        assert!(owners.contains(&"agent-2"));

        // Expired leases removed, fresh stays
        assert!(!lock_dir.join("task-a.lease").exists());
        assert!(!lock_dir.join("task-b.lease").exists());
        assert!(lock_dir.join("task-c.lease").exists());
    }

    #[test]
    fn test_reassign_expired_tasks_empty() {
        let dir = setup_test_env(true, false);
        let result = reassign_expired_tasks(dir.path());
        assert_eq!(result["action"], "reassign");
        assert_eq!(result["count"], 0);
        assert!(result["reassigned"].as_array().unwrap().is_empty());
    }

    #[test]
    fn test_cli_reassign_action() {
        let dir = setup_test_env(true, false);
        let lock_dir = locks_dir(dir.path());
        fs::create_dir_all(&lock_dir).unwrap();

        let expired = json!({
            "resource": "stale-task", "owner": "crashed-agent",
            "acquired_at": "2020-01-01T00:00:00Z", "ttl_secs": 1, "type": "lease",
        });
        fs::write(lock_dir.join("stale-task.lease"), serde_json::to_string_pretty(&expired).unwrap()).unwrap();

        let args = vec!["yolo".into(), "lease-lock".into(), "reassign".into()];
        let (out, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);

        let parsed: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(parsed["action"], "reassign");
        assert_eq!(parsed["count"], 1);
        assert!(!lock_dir.join("stale-task.lease").exists());
    }

    #[test]
    fn test_cli_unknown_action() {
        let dir = setup_test_env(true, false);
        let args = vec!["yolo".into(), "lease-lock".into(), "invalid".into()];
        let result = execute(&args, dir.path());
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("reassign"));
    }

    // === Integration tests for Task 5 ===

    #[test]
    fn test_integration_acquire_expire_reassign() {
        // End-to-end: acquire lease, artificially expire it, reassign, verify
        let dir = setup_test_env(true, false);
        let lock_dir = locks_dir(dir.path());

        // Step 1: Acquire a lease
        let result = acquire(&rid("plan-1"), "agent-alpha", 300, dir.path()).unwrap();
        assert_eq!(result["result"], "acquired");
        assert!(lock_dir.join("plan-1.lease").exists());

        // Step 2: Artificially expire it by rewriting with old timestamp
        let expired = json!({
            "resource": "plan-1", "owner": "agent-alpha",
            "acquired_at": "2020-01-01T00:00:00Z", "ttl_secs": 1, "type": "lease",
        });
        fs::write(lock_dir.join("plan-1.lease"), serde_json::to_string_pretty(&expired).unwrap()).unwrap();

        // Step 3: Verify is_lease_expired detects it
        assert!(is_lease_expired(dir.path(), "plan-1"));

        // Step 4: Reassign expired tasks
        let reassign_result = reassign_expired_tasks(dir.path());
        assert_eq!(reassign_result["count"], 1);
        let reassigned = reassign_result["reassigned"].as_array().unwrap();
        assert_eq!(reassigned[0]["resource"], "plan-1");
        assert_eq!(reassigned[0]["previous_owner"], "agent-alpha");

        // Step 5: Lease file should be removed
        assert!(!lock_dir.join("plan-1.lease").exists());
    }

    #[test]
    fn test_integration_fresh_lease_not_reassigned() {
        let dir = setup_test_env(true, false);

        // Acquire a fresh lease
        let result = acquire(&rid("plan-2"), "agent-beta", 3600, dir.path()).unwrap();
        assert_eq!(result["result"], "acquired");

        // Fresh lease should NOT be expired
        assert!(!is_lease_expired(dir.path(), "plan-2"));

        // Reassign should NOT touch it
        let reassign_result = reassign_expired_tasks(dir.path());
        assert_eq!(reassign_result["count"], 0);

        // Lease file should still exist
        let lock_dir = locks_dir(dir.path());
        assert!(lock_dir.join("plan-2.lease").exists());
    }

    #[test]
    fn test_integration_reassign_with_event_logging() {
        // Test that reassignment logs events when v3_event_log is enabled
        let dir = TempDir::new().unwrap();
        let planning_dir = dir.path().join(".yolo-planning");
        fs::create_dir_all(&planning_dir).unwrap();
        let config = json!({"v3_lock_lite": true, "v3_event_log": true});
        fs::write(planning_dir.join("config.json"), config.to_string()).unwrap();

        // Create an expired lease
        let lock_dir = locks_dir(dir.path());
        fs::create_dir_all(&lock_dir).unwrap();
        let expired = json!({
            "resource": "task-logged", "owner": "crashed-agent",
            "acquired_at": "2020-01-01T00:00:00Z", "ttl_secs": 1, "type": "lease",
        });
        fs::write(lock_dir.join("task-logged.lease"), serde_json::to_string_pretty(&expired).unwrap()).unwrap();

        // Reassign
        let result = reassign_expired_tasks(dir.path());
        assert_eq!(result["count"], 1);

        // Verify event was logged
        let events_file = planning_dir.join(".events").join("event-log.jsonl");
        assert!(events_file.exists());
        let events_content = fs::read_to_string(&events_file).unwrap();
        assert!(events_content.contains("task_reassigned"));
        assert!(events_content.contains("crashed-agent"));
        assert!(events_content.contains("lease_expired"));
    }

    #[test]
    fn test_integration_reassign_report_has_previous_owner() {
        let dir = setup_test_env(true, false);
        let lock_dir = locks_dir(dir.path());
        fs::create_dir_all(&lock_dir).unwrap();

        // Create expired leases with different owners
        for (resource, owner) in [("res-a", "owner-1"), ("res-b", "owner-2"), ("res-c", "owner-3")] {
            let lease = json!({
                "resource": resource, "owner": owner,
                "acquired_at": "2020-01-01T00:00:00Z", "ttl_secs": 1, "type": "lease",
            });
            fs::write(
                lock_dir.join(format!("{}.lease", resource)),
                serde_json::to_string_pretty(&lease).unwrap(),
            ).unwrap();
        }

        let result = reassign_expired_tasks(dir.path());
        assert_eq!(result["count"], 3);

        let reassigned = result["reassigned"].as_array().unwrap();
        let owners: Vec<&str> = reassigned.iter()
            .map(|r| r["previous_owner"].as_str().unwrap())
            .collect();
        assert!(owners.contains(&"owner-1"));
        assert!(owners.contains(&"owner-2"));
        assert!(owners.contains(&"owner-3"));
    }
}
