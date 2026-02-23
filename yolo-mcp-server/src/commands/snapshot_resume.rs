use chrono::Utc;
use serde_json::{json, Value};
use std::fs;
use std::path::Path;
use std::process::Command;

/// CLI entry: `yolo snapshot-resume <save|restore> <phase> [args...]`
pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    if args.len() < 2 {
        return Err("Usage: yolo snapshot-resume <save|restore> <phase> [args...]".to_string());
    }

    let action = &args[0];
    let phase = &args[1];

    let planning_dir = cwd.join(".yolo-planning");
    let config_path = planning_dir.join("config.json");
    let snapshots_dir = planning_dir.join(".snapshots");

    // Check feature flag v3_snapshot_resume
    if config_path.exists() {
        if let Ok(content) = fs::read_to_string(&config_path) {
            if let Ok(config) = serde_json::from_str::<Value>(&content) {
                let enabled = config
                    .get("v3_snapshot_resume")
                    .and_then(|v| v.as_bool())
                    .unwrap_or(false);
                if !enabled {
                    return Ok(("".to_string(), 0));
                }
            }
        }
    }

    match action.as_str() {
        "save" => {
            let state_path_str = args.get(2).map(|s| s.as_str()).unwrap_or(".yolo-planning/.execution-state.json");
            let state_path = cwd.join(state_path_str);
            if fs::create_dir_all(&snapshots_dir).is_err() {
                return Ok(("".to_string(), 0));
            }
            if !state_path.exists() {
                return Ok(("".to_string(), 0));
            }
            save_snapshot(cwd, phase, &state_path, &snapshots_dir, args)
        }
        "restore" => {
            if !snapshots_dir.is_dir() {
                return Ok(("".to_string(), 0));
            }
            let preferred_role = args.get(2).map(|s| s.as_str()).unwrap_or("");
            restore_snapshot(phase, preferred_role, &snapshots_dir)
        }
        _ => {
            eprintln!("Unknown action: {}. Valid: save, restore", action);
            Ok(("".to_string(), 0))
        }
    }
}

fn save_snapshot(
    cwd: &Path,
    phase: &str,
    state_path: &Path,
    snapshots_dir: &Path,
    args: &[String],
) -> Result<(String, i32), String> {
    let ts = Utc::now().format("%Y%m%dT%H%M%S").to_string();
    let snapshot_file = snapshots_dir.join(format!("{}-{}.json", phase, ts));

    // Agent role
    let agent_role = if let Some(role) = args.get(3) {
        role.clone()
    } else {
        let active_agent = cwd.join(".yolo-planning/.active-agent");
        fs::read_to_string(active_agent)
            .unwrap_or_else(|_| "unknown".to_string())
            .trim()
            .to_string()
    };

    let trigger = args.get(4).map(|s| s.as_str()).unwrap_or("unknown");

    // Read execution state
    let exec_state: Value = fs::read_to_string(state_path)
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or(json!({}));

    // Git log (direct git call, not bash)
    let recent_commits = get_recent_commits(cwd);

    let snapshot = json!({
        "snapshot_ts": ts,
        "phase": phase,
        "execution_state": exec_state,
        "recent_commits": recent_commits,
        "agent_role": agent_role,
        "compaction_trigger": trigger
    });

    if fs::write(&snapshot_file, serde_json::to_string_pretty(&snapshot).unwrap_or_default()).is_err() {
        return Ok(("".to_string(), 0));
    }

    // Prune: keep max 10 snapshots per phase
    prune_snapshots(phase, snapshots_dir, 10);

    let rel = snapshot_file.to_string_lossy().to_string();
    Ok((rel, 0))
}

fn restore_snapshot(
    phase: &str,
    preferred_role: &str,
    snapshots_dir: &Path,
) -> Result<(String, i32), String> {
    let prefix = format!("{}-", phase);
    let suffix = ".json";

    // Collect matching snapshots sorted by name descending (newest first since timestamp-based)
    let mut candidates: Vec<String> = Vec::new();
    if let Ok(entries) = fs::read_dir(snapshots_dir) {
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().to_string();
            if name.starts_with(&prefix) && name.ends_with(suffix) {
                candidates.push(name);
            }
        }
    }
    candidates.sort_by(|a, b| b.cmp(a)); // reverse sort = newest first

    if candidates.is_empty() {
        return Ok(("".to_string(), 0));
    }

    // Try preferred role first
    if !preferred_role.is_empty() && preferred_role != "unknown" {
        for name in &candidates {
            let path = snapshots_dir.join(name);
            if let Ok(content) = fs::read_to_string(&path) {
                if let Ok(snap) = serde_json::from_str::<Value>(&content) {
                    let role = snap
                        .get("agent_role")
                        .and_then(|v| v.as_str())
                        .unwrap_or("");
                    if role == preferred_role {
                        return Ok((path.to_string_lossy().to_string(), 0));
                    }
                }
            }
        }
    }

    // Fall back to latest
    let latest = snapshots_dir.join(&candidates[0]);
    if latest.exists() {
        Ok((latest.to_string_lossy().to_string(), 0))
    } else {
        Ok(("".to_string(), 0))
    }
}

fn get_recent_commits(cwd: &Path) -> Value {
    let output = Command::new("git")
        .args(["log", "--oneline", "-5"])
        .current_dir(cwd)
        .output();

    match output {
        Ok(o) if o.status.success() => {
            let text = String::from_utf8_lossy(&o.stdout);
            let lines: Vec<Value> = text
                .lines()
                .filter(|l| !l.is_empty())
                .map(|l| Value::String(l.to_string()))
                .collect();
            Value::Array(lines)
        }
        _ => json!([]),
    }
}

fn prune_snapshots(phase: &str, snapshots_dir: &Path, max: usize) {
    let prefix = format!("{}-", phase);
    let suffix = ".json";

    let mut matching: Vec<String> = Vec::new();
    if let Ok(entries) = fs::read_dir(snapshots_dir) {
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().to_string();
            if name.starts_with(&prefix) && name.ends_with(suffix) {
                matching.push(name);
            }
        }
    }

    if matching.len() <= max {
        return;
    }

    // Sort ascending (oldest first by timestamp in name)
    matching.sort();
    let prune_count = matching.len() - max;
    for name in matching.iter().take(prune_count) {
        let _ = fs::remove_file(snapshots_dir.join(name));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn setup_test_env() -> TempDir {
        let dir = TempDir::new().unwrap();
        let planning = dir.path().join(".yolo-planning");
        fs::create_dir_all(&planning).unwrap();

        // Enable feature flag
        fs::write(
            planning.join("config.json"),
            r#"{"v3_snapshot_resume": true}"#,
        )
        .unwrap();

        // Create execution state
        fs::write(
            planning.join(".execution-state.json"),
            r#"{"phase": 1, "status": "running"}"#,
        )
        .unwrap();

        // Init git repo for git log
        let _ = Command::new("git")
            .args(["init"])
            .current_dir(dir.path())
            .output();
        let _ = Command::new("git")
            .args(["commit", "--allow-empty", "-m", "test: init"])
            .current_dir(dir.path())
            .output();

        dir
    }

    #[test]
    fn test_save_creates_snapshot() {
        let dir = setup_test_env();
        let args = vec!["save".into(), "1".into()];
        let (out, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
        assert!(out.contains("1-"), "Output should contain snapshot path: {}", out);

        let snapshots = dir.path().join(".yolo-planning/.snapshots");
        assert!(snapshots.is_dir());
        let entries: Vec<_> = fs::read_dir(&snapshots).unwrap().flatten().collect();
        assert_eq!(entries.len(), 1);
    }

    #[test]
    fn test_save_prunes_old_snapshots() {
        let dir = setup_test_env();
        let snapshots = dir.path().join(".yolo-planning/.snapshots");
        fs::create_dir_all(&snapshots).unwrap();

        // Create 12 old snapshots
        for i in 0..12 {
            let name = format!("1-20260101T{:06}.json", i);
            fs::write(snapshots.join(&name), "{}").unwrap();
        }

        let args = vec!["save".into(), "1".into()];
        let (_, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);

        // Should have max 10 after pruning (12 old + 1 new = 13, prune to 10)
        let count = fs::read_dir(&snapshots).unwrap().flatten().count();
        assert!(count <= 10, "Expected <=10 snapshots, got {}", count);
    }

    #[test]
    fn test_restore_finds_latest() {
        let dir = setup_test_env();
        let snapshots = dir.path().join(".yolo-planning/.snapshots");
        fs::create_dir_all(&snapshots).unwrap();

        // Create snapshots
        fs::write(
            snapshots.join("2-20260101T000001.json"),
            r#"{"agent_role": "dev"}"#,
        )
        .unwrap();
        fs::write(
            snapshots.join("2-20260101T000002.json"),
            r#"{"agent_role": "lead"}"#,
        )
        .unwrap();

        let args = vec!["restore".into(), "2".into()];
        let (out, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
        assert!(out.contains("000002"), "Should find latest snapshot: {}", out);
    }

    #[test]
    fn test_restore_prefers_role() {
        let dir = setup_test_env();
        let snapshots = dir.path().join(".yolo-planning/.snapshots");
        fs::create_dir_all(&snapshots).unwrap();

        fs::write(
            snapshots.join("3-20260101T000001.json"),
            r#"{"agent_role": "dev"}"#,
        )
        .unwrap();
        fs::write(
            snapshots.join("3-20260101T000002.json"),
            r#"{"agent_role": "lead"}"#,
        )
        .unwrap();

        let args = vec!["restore".into(), "3".into(), "dev".into()];
        let (out, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
        assert!(out.contains("000001"), "Should prefer dev role snapshot: {}", out);
    }

    #[test]
    fn test_snapshot_save_restore_with_default_config() {
        // Integration test: save a snapshot and restore it using default config (flags enabled)
        let dir = TempDir::new().unwrap();
        let planning = dir.path().join(".yolo-planning");
        fs::create_dir_all(&planning).unwrap();

        // Use config matching new defaults (all recovery flags enabled)
        let config = serde_json::json!({
            "v3_snapshot_resume": true,
            "v3_event_recovery": true,
            "v3_lease_locks": true
        });
        fs::write(planning.join("config.json"), config.to_string()).unwrap();

        // Create execution state
        let exec_state = serde_json::json!({
            "phase": 11,
            "status": "running",
            "wave": 2,
            "plans_complete": 4,
            "plans_total": 5
        });
        fs::write(
            planning.join(".execution-state.json"),
            serde_json::to_string_pretty(&exec_state).unwrap(),
        ).unwrap();

        // Init git repo for git log
        let _ = Command::new("git").args(["init"]).current_dir(dir.path()).output();
        let _ = Command::new("git").args(["commit", "--allow-empty", "-m", "feat: wave 1 done"]).current_dir(dir.path()).output();

        // Save snapshot with explicit agent role
        let save_args: Vec<String> = vec![
            "save".into(), "11".into(),
            ".yolo-planning/.execution-state.json".into(),
            "dev".into(),
            "compaction".into(),
        ];
        let (save_out, save_code) = execute(&save_args, dir.path()).unwrap();
        assert_eq!(save_code, 0);
        assert!(!save_out.is_empty(), "Save should return snapshot path");

        // Verify snapshot file content
        let snapshots_dir = planning.join(".snapshots");
        let entries: Vec<_> = fs::read_dir(&snapshots_dir).unwrap().flatten().collect();
        assert_eq!(entries.len(), 1);

        let snap_content = fs::read_to_string(entries[0].path()).unwrap();
        let snap: Value = serde_json::from_str(&snap_content).unwrap();

        // Verify snapshot contains execution state
        assert_eq!(snap["execution_state"]["phase"], 11);
        assert_eq!(snap["execution_state"]["status"], "running");
        assert_eq!(snap["execution_state"]["wave"], 2);

        // Verify agent role
        assert_eq!(snap["agent_role"], "dev");

        // Verify compaction trigger
        assert_eq!(snap["compaction_trigger"], "compaction");

        // Verify recent commits (git log)
        assert!(snap["recent_commits"].is_array());

        // Restore snapshot - should find our saved one
        let restore_args: Vec<String> = vec!["restore".into(), "11".into(), "dev".into()];
        let (restore_out, restore_code) = execute(&restore_args, dir.path()).unwrap();
        assert_eq!(restore_code, 0);
        assert!(!restore_out.is_empty(), "Restore should return snapshot path");

        // Restored path should point to a valid file
        let restored_path = std::path::Path::new(restore_out.trim());
        assert!(restored_path.exists(), "Restored snapshot path should exist: {}", restore_out);
    }

    #[test]
    fn test_disabled_feature_flag() {
        let dir = TempDir::new().unwrap();
        let planning = dir.path().join(".yolo-planning");
        fs::create_dir_all(&planning).unwrap();
        fs::write(
            planning.join("config.json"),
            r#"{"v3_snapshot_resume": false}"#,
        )
        .unwrap();

        let args = vec!["save".into(), "1".into()];
        let (out, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
        assert!(out.is_empty());
    }

    #[test]
    fn test_missing_state_file() {
        let dir = setup_test_env();
        // Remove the execution state
        let _ = fs::remove_file(dir.path().join(".yolo-planning/.execution-state.json"));

        let args = vec!["save".into(), "1".into()];
        let (out, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
        assert!(out.is_empty());
    }

    #[test]
    fn test_restore_empty_dir() {
        let dir = setup_test_env();
        let snapshots = dir.path().join(".yolo-planning/.snapshots");
        fs::create_dir_all(&snapshots).unwrap();

        let args = vec!["restore".into(), "1".into()];
        let (out, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
        assert!(out.is_empty());
    }
}
