use std::fs;
use std::path::{Path, PathBuf};

use chrono::Utc;
use serde_json::{json, Value};

use super::types::{HookInput, HookOutput};
use super::utils;

const HEALTH_DIR_NAME: &str = ".agent-health";

/// Handle agent health "start" subcommand (called from SubagentStart).
pub fn cmd_start(input: &HookInput, planning_dir: &Path) -> Result<HookOutput, String> {
    let pid = extract_pid(&input.data);
    let role = extract_and_normalize_role(&input.data);

    if role.is_empty() || pid == 0 {
        return Ok(HookOutput::empty());
    }

    let health_dir = planning_dir.join(HEALTH_DIR_NAME);
    let _ = fs::create_dir_all(&health_dir);

    let now = Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string();

    let health = json!({
        "pid": pid,
        "role": role,
        "started_at": now,
        "last_event_at": now,
        "last_event": "start",
        "idle_count": 0
    });

    let health_file = health_dir.join(format!("{}.json", role));
    fs::write(&health_file, serde_json::to_string_pretty(&health).unwrap())
        .map_err(|e| format!("Failed to write health file: {}", e))?;

    Ok(HookOutput::empty())
}

/// Handle agent health "idle" subcommand (called from TeammateIdle).
pub fn cmd_idle(input: &HookInput, planning_dir: &Path) -> Result<HookOutput, String> {
    let role = extract_and_normalize_role(&input.data);
    if role.is_empty() {
        return Ok(HookOutput::empty());
    }

    let health_dir = planning_dir.join(HEALTH_DIR_NAME);
    let health_file = health_dir.join(format!("{}.json", role));

    if !health_file.exists() {
        return Ok(HookOutput::empty());
    }

    let content = fs::read_to_string(&health_file).unwrap_or_default();
    let health: Value = serde_json::from_str(&content).unwrap_or(json!({}));

    let pid = health
        .get("pid")
        .and_then(|v| v.as_u64())
        .unwrap_or(0) as i32;

    // Check PID liveness
    if pid > 0 && !is_alive(pid) {
        let advisory = orphan_recovery(&role, pid as u32, planning_dir);
        let _ = fs::remove_file(&health_file);
        return Ok(HookOutput::ok(advisory));
    }

    // Increment idle count
    let idle_count = health
        .get("idle_count")
        .and_then(|v| v.as_u64())
        .unwrap_or(0)
        + 1;

    let now = Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string();

    let mut updated = health.clone();
    updated["last_event_at"] = json!(now);
    updated["last_event"] = json!("idle");
    updated["idle_count"] = json!(idle_count);

    let _ = fs::write(
        &health_file,
        serde_json::to_string_pretty(&updated).unwrap(),
    );

    // Check for stuck agent
    let mut advisory = String::new();
    if idle_count >= 3 {
        advisory = format!(
            "AGENT HEALTH: Agent {} appears stuck (idle_count={})",
            role, idle_count
        );
    }

    if advisory.is_empty() {
        Ok(HookOutput::empty())
    } else {
        Ok(HookOutput::ok(advisory))
    }
}

/// Handle agent health "stop" subcommand (called from SubagentStop).
pub fn cmd_stop(input: &HookInput, planning_dir: &Path) -> Result<HookOutput, String> {
    let role = extract_and_normalize_role(&input.data);
    if role.is_empty() {
        return Ok(HookOutput::empty());
    }

    let health_dir = planning_dir.join(HEALTH_DIR_NAME);
    let health_file = health_dir.join(format!("{}.json", role));
    let mut advisory = String::new();

    if health_file.exists() {
        let content = fs::read_to_string(&health_file).unwrap_or_default();
        let health: Value = serde_json::from_str(&content).unwrap_or(json!({}));

        let pid = health
            .get("pid")
            .and_then(|v| v.as_u64())
            .unwrap_or(0) as i32;

        if pid > 0 && !is_alive(pid) {
            advisory = orphan_recovery(&role, pid as u32, planning_dir);
        }

        let _ = fs::remove_file(&health_file);
    }

    if advisory.is_empty() {
        Ok(HookOutput::empty())
    } else {
        Ok(HookOutput::ok(advisory))
    }
}

/// Handle agent health "cleanup" subcommand.
pub fn cmd_cleanup(planning_dir: &Path) -> Result<HookOutput, String> {
    let health_dir = planning_dir.join(HEALTH_DIR_NAME);
    if health_dir.exists() {
        let _ = fs::remove_dir_all(&health_dir);
    }
    Ok(HookOutput::empty())
}

/// Orphan recovery: find tasks owned by the dead agent and clear ownership.
fn orphan_recovery(role: &str, pid: u32, planning_dir: &Path) -> String {
    let tasks_dir = resolve_tasks_dir();
    let mut advisory = String::new();

    if let Some(tasks_dir) = tasks_dir {
        if tasks_dir.is_dir() {
            // Scan all team directories
            if let Ok(entries) = fs::read_dir(&tasks_dir) {
                for entry in entries.flatten() {
                    if !entry.path().is_dir() {
                        continue;
                    }
                    recover_tasks_in_dir(&entry.path(), role, pid, &mut advisory);
                }
            }
        }
    }

    if advisory.is_empty() {
        format!(
            "AGENT HEALTH: Orphan recovery -- agent {} PID {} is dead (no orphaned tasks found)",
            role, pid
        )
    } else {
        advisory
    }
}

fn recover_tasks_in_dir(team_dir: &Path, role: &str, pid: u32, advisory: &mut String) {
    let entries = match fs::read_dir(team_dir) {
        Ok(e) => e,
        Err(_) => return,
    };

    for entry in entries.flatten() {
        let path = entry.path();
        if !path.extension().is_some_and(|e| e == "json") {
            continue;
        }

        let content = match fs::read_to_string(&path) {
            Ok(c) => c,
            Err(_) => continue,
        };

        let mut task: Value = match serde_json::from_str(&content) {
            Ok(v) => v,
            Err(_) => continue,
        };

        let task_owner = task
            .get("owner")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();
        let task_status = task
            .get("status")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();
        let task_id = task
            .get("id")
            .and_then(|v| v.as_str())
            .unwrap_or("unknown")
            .to_string();

        if task_owner == role && task_status == "in_progress" {
            task["owner"] = json!("");
            if let Ok(updated) = serde_json::to_string_pretty(&task) {
                let _ = fs::write(&path, updated);
            }
            *advisory = format!(
                "AGENT HEALTH: Orphan recovery -- cleared ownership of task {} (owner {} PID {} is dead)",
                task_id, role, pid
            );
        }
    }
}

fn resolve_tasks_dir() -> Option<PathBuf> {
    let claude_dir = utils::resolve_claude_dir();
    let tasks_dir = claude_dir.join("tasks");
    if tasks_dir.is_dir() {
        Some(tasks_dir)
    } else {
        None
    }
}

fn extract_pid(data: &Value) -> u32 {
    data.get("pid")
        .and_then(|v| {
            v.as_u64()
                .map(|n| n as u32)
                .or_else(|| v.as_str().and_then(|s| s.parse().ok()))
        })
        .unwrap_or(0)
}

fn extract_and_normalize_role(data: &Value) -> String {
    let raw = data
        .get("agent_type")
        .or_else(|| data.get("agent_name"))
        .or_else(|| data.get("name"))
        .and_then(|v| v.as_str())
        .unwrap_or("");

    if raw.is_empty() {
        return String::new();
    }

    utils::normalize_agent_role(raw)
}

fn is_alive(pid: i32) -> bool {
    unsafe { libc::kill(pid, 0) == 0 }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn make_input(json: &str) -> HookInput {
        HookInput {
            data: serde_json::from_str(json).unwrap(),
        }
    }

    #[test]
    fn test_cmd_start_creates_health_file() {
        let dir = TempDir::new().unwrap();
        let planning = dir.path().join(".yolo-planning");
        fs::create_dir_all(&planning).unwrap();

        let input = make_input(r#"{"agent_type":"yolo-dev","pid":12345}"#);
        let result = cmd_start(&input, &planning);
        assert!(result.is_ok());

        let health_file = planning.join(".agent-health/dev.json");
        assert!(health_file.exists());

        let content: Value =
            serde_json::from_str(&fs::read_to_string(&health_file).unwrap()).unwrap();
        assert_eq!(content["pid"], 12345);
        assert_eq!(content["role"], "dev");
        assert_eq!(content["last_event"], "start");
        assert_eq!(content["idle_count"], 0);
    }

    #[test]
    fn test_cmd_start_empty_input() {
        let dir = TempDir::new().unwrap();
        let planning = dir.path().join(".yolo-planning");

        let input = make_input(r#"{}"#);
        let result = cmd_start(&input, &planning);
        assert!(result.is_ok());
        assert_eq!(result.unwrap().exit_code, 0);
    }

    #[test]
    fn test_cmd_idle_increments_count() {
        let dir = TempDir::new().unwrap();
        let planning = dir.path().join(".yolo-planning");
        let health_dir = planning.join(".agent-health");
        fs::create_dir_all(&health_dir).unwrap();

        // Use our own PID so it's alive
        let my_pid = std::process::id();
        let health = json!({
            "pid": my_pid,
            "role": "dev",
            "started_at": "2026-01-01T00:00:00Z",
            "last_event_at": "2026-01-01T00:00:00Z",
            "last_event": "start",
            "idle_count": 0
        });
        fs::write(
            health_dir.join("dev.json"),
            serde_json::to_string_pretty(&health).unwrap(),
        )
        .unwrap();

        let input = make_input(r#"{"agent_type":"yolo-dev"}"#);
        let result = cmd_idle(&input, &planning);
        assert!(result.is_ok());

        let updated: Value = serde_json::from_str(
            &fs::read_to_string(health_dir.join("dev.json")).unwrap(),
        )
        .unwrap();
        assert_eq!(updated["idle_count"], 1);
        assert_eq!(updated["last_event"], "idle");
    }

    #[test]
    fn test_cmd_idle_stuck_warning() {
        let dir = TempDir::new().unwrap();
        let planning = dir.path().join(".yolo-planning");
        let health_dir = planning.join(".agent-health");
        fs::create_dir_all(&health_dir).unwrap();

        let my_pid = std::process::id();
        let health = json!({
            "pid": my_pid,
            "role": "lead",
            "started_at": "2026-01-01T00:00:00Z",
            "last_event_at": "2026-01-01T00:00:00Z",
            "last_event": "idle",
            "idle_count": 2
        });
        fs::write(
            health_dir.join("lead.json"),
            serde_json::to_string_pretty(&health).unwrap(),
        )
        .unwrap();

        let input = make_input(r#"{"agent_type":"yolo-lead"}"#);
        let result = cmd_idle(&input, &planning).unwrap();
        assert!(result.stdout.contains("appears stuck"));
        assert!(result.stdout.contains("idle_count=3"));
    }

    #[test]
    fn test_cmd_idle_dead_pid_triggers_recovery() {
        let dir = TempDir::new().unwrap();
        let planning = dir.path().join(".yolo-planning");
        let health_dir = planning.join(".agent-health");
        fs::create_dir_all(&health_dir).unwrap();

        let health = json!({
            "pid": 999999,
            "role": "dev",
            "started_at": "2026-01-01T00:00:00Z",
            "last_event_at": "2026-01-01T00:00:00Z",
            "last_event": "start",
            "idle_count": 0
        });
        fs::write(
            health_dir.join("dev.json"),
            serde_json::to_string_pretty(&health).unwrap(),
        )
        .unwrap();

        let input = make_input(r#"{"agent_type":"yolo-dev"}"#);
        let result = cmd_idle(&input, &planning).unwrap();
        assert!(result.stdout.contains("Orphan recovery"));

        // Health file should be removed
        assert!(!health_dir.join("dev.json").exists());
    }

    #[test]
    fn test_cmd_idle_no_health_file() {
        let dir = TempDir::new().unwrap();
        let planning = dir.path().join(".yolo-planning");
        fs::create_dir_all(&planning).unwrap();

        let input = make_input(r#"{"agent_type":"yolo-dev"}"#);
        let result = cmd_idle(&input, &planning);
        assert!(result.is_ok());
        assert_eq!(result.unwrap().exit_code, 0);
    }

    #[test]
    fn test_cmd_stop_removes_health_file() {
        let dir = TempDir::new().unwrap();
        let planning = dir.path().join(".yolo-planning");
        let health_dir = planning.join(".agent-health");
        fs::create_dir_all(&health_dir).unwrap();

        let my_pid = std::process::id();
        let health = json!({
            "pid": my_pid,
            "role": "dev",
            "started_at": "2026-01-01T00:00:00Z",
            "last_event_at": "2026-01-01T00:00:00Z",
            "last_event": "start",
            "idle_count": 0
        });
        fs::write(
            health_dir.join("dev.json"),
            serde_json::to_string_pretty(&health).unwrap(),
        )
        .unwrap();

        let input = make_input(r#"{"agent_type":"yolo-dev"}"#);
        let result = cmd_stop(&input, &planning);
        assert!(result.is_ok());

        assert!(!health_dir.join("dev.json").exists());
    }

    #[test]
    fn test_cmd_stop_dead_pid_recovery() {
        let dir = TempDir::new().unwrap();
        let planning = dir.path().join(".yolo-planning");
        let health_dir = planning.join(".agent-health");
        fs::create_dir_all(&health_dir).unwrap();

        let health = json!({
            "pid": 999999,
            "role": "qa",
            "started_at": "2026-01-01T00:00:00Z",
            "last_event_at": "2026-01-01T00:00:00Z",
            "last_event": "start",
            "idle_count": 0
        });
        fs::write(
            health_dir.join("qa.json"),
            serde_json::to_string_pretty(&health).unwrap(),
        )
        .unwrap();

        let input = make_input(r#"{"agent_type":"yolo-qa"}"#);
        let result = cmd_stop(&input, &planning).unwrap();
        assert!(result.stdout.contains("Orphan recovery"));
        assert!(!health_dir.join("qa.json").exists());
    }

    #[test]
    fn test_cmd_cleanup() {
        let dir = TempDir::new().unwrap();
        let planning = dir.path().join(".yolo-planning");
        let health_dir = planning.join(".agent-health");
        fs::create_dir_all(&health_dir).unwrap();
        fs::write(health_dir.join("dev.json"), "{}").unwrap();

        let result = cmd_cleanup(&planning);
        assert!(result.is_ok());
        assert!(!health_dir.exists());
    }

    #[test]
    fn test_cmd_cleanup_no_dir() {
        let dir = TempDir::new().unwrap();
        let planning = dir.path().join(".yolo-planning");

        let result = cmd_cleanup(&planning);
        assert!(result.is_ok());
    }

    #[test]
    fn test_orphan_recovery_with_mock_tasks() {
        let dir = TempDir::new().unwrap();
        let planning = dir.path().join(".yolo-planning");
        fs::create_dir_all(&planning).unwrap();

        // Create mock tasks directory
        let tasks_dir = dir.path().join("mock-tasks");
        let team_dir = tasks_dir.join("team-1");
        fs::create_dir_all(&team_dir).unwrap();

        let task = json!({
            "id": "task-42",
            "owner": "dev",
            "status": "in_progress"
        });
        fs::write(
            team_dir.join("task-42.json"),
            serde_json::to_string_pretty(&task).unwrap(),
        )
        .unwrap();

        // Directly call recover helper
        let mut advisory = String::new();
        recover_tasks_in_dir(&team_dir, "dev", 999999, &mut advisory);

        assert!(advisory.contains("cleared ownership"));
        assert!(advisory.contains("task-42"));

        // Verify owner was cleared
        let updated: Value = serde_json::from_str(
            &fs::read_to_string(team_dir.join("task-42.json")).unwrap(),
        )
        .unwrap();
        assert_eq!(updated["owner"], "");
    }

    #[test]
    fn test_extract_and_normalize_role() {
        let data: Value = serde_json::from_str(r#"{"agent_type":"yolo-dev"}"#).unwrap();
        assert_eq!(extract_and_normalize_role(&data), "dev");

        let data: Value = serde_json::from_str(r#"{"agent_name":"@yolo:lead-1"}"#).unwrap();
        assert_eq!(extract_and_normalize_role(&data), "lead");

        let data: Value = serde_json::from_str(r#"{}"#).unwrap();
        assert_eq!(extract_and_normalize_role(&data), "");
    }
}
