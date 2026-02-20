use serde_json::{json, Value};
use std::fs;
use std::path::Path;

use super::utils;

/// TaskCompleted handler that detects newly-unblocked tasks.
///
/// When a task completes:
/// 1. Extracts the completed task_id from hook input
/// 2. Scans team task directories under `<claude_dir>/tasks/*/`
/// 3. Finds tasks with `blockedBy` containing the completed task_id
/// 4. Checks if ALL remaining blockers are also completed
/// 5. Outputs advisory "BLOCKER CLEARED" context for each unblocked task
///
/// Always returns exit 0 (advisory, never blocks).
pub fn blocker_notify(input: &Value) -> (Value, i32) {
    let task_id = extract_task_id(input);
    if task_id.is_empty() {
        return (Value::Null, 0);
    }

    let claude_dir = utils::resolve_claude_dir();
    let tasks_base = claude_dir.join("tasks");

    if !tasks_base.is_dir() {
        return (Value::Null, 0);
    }

    // Find first team task directory
    let team_tasks_dir = match find_team_tasks_dir(&tasks_base) {
        Some(d) => d,
        None => return (Value::Null, 0),
    };

    // Scan for unblocked tasks
    let unblocked = scan_for_unblocked(&team_tasks_dir, &task_id);

    if unblocked.is_empty() {
        return (Value::Null, 0);
    }

    let ctx = format!(
        "BLOCKER CLEARED: {}Send each unblocked agent a message to proceed.",
        unblocked.join("")
    );

    let output = json!({
        "hookSpecificOutput": {
            "hookEventName": "TaskCompleted",
            "additionalContext": ctx
        }
    });

    (output, 0)
}

/// Extract the completed task ID from hook input.
fn extract_task_id(input: &Value) -> String {
    // Try .task_id first, then .task.id
    if let Some(id) = input.get("task_id").and_then(|v| v.as_str()) {
        return id.to_string();
    }
    if let Some(id) = input
        .get("task")
        .and_then(|t| t.get("id"))
        .and_then(|v| v.as_str())
    {
        return id.to_string();
    }
    String::new()
}

/// Find the first team task directory under the tasks base.
fn find_team_tasks_dir(tasks_base: &Path) -> Option<std::path::PathBuf> {
    let entries = fs::read_dir(tasks_base).ok()?;
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            return Some(path);
        }
    }
    None
}

/// Scan task files in the team directory for tasks blocked by the completed task_id.
/// Returns a list of human-readable unblocked task descriptions.
fn scan_for_unblocked(team_dir: &Path, completed_id: &str) -> Vec<String> {
    let mut unblocked = Vec::new();

    let entries = match fs::read_dir(team_dir) {
        Ok(e) => e,
        Err(_) => return unblocked,
    };

    for entry in entries.flatten() {
        let path = entry.path();
        if path.extension().is_none_or(|ext| ext != "json") {
            continue;
        }

        let content = match fs::read_to_string(&path) {
            Ok(c) => c,
            Err(_) => continue,
        };

        let task: Value = match serde_json::from_str(&content) {
            Ok(v) => v,
            Err(_) => continue,
        };

        // Skip completed/deleted tasks
        let status = task
            .get("status")
            .and_then(|v| v.as_str())
            .unwrap_or("");
        if status == "completed" || status == "deleted" {
            continue;
        }

        // Check if this task is blocked by the completed task
        let blocked_by = match task.get("blockedBy").and_then(|v| v.as_array()) {
            Some(arr) => arr,
            None => continue,
        };

        let is_blocked = blocked_by
            .iter()
            .any(|v| v.as_str() == Some(completed_id));

        if !is_blocked {
            continue;
        }

        // Check if ALL other blockers are completed
        let all_clear = check_other_blockers_complete(team_dir, blocked_by, completed_id);

        if all_clear {
            let subject = task
                .get("subject")
                .and_then(|v| v.as_str())
                .unwrap_or("unknown");
            let owner = task
                .get("owner")
                .and_then(|v| v.as_str())
                .unwrap_or("unassigned");

            let file_id = path
                .file_stem()
                .and_then(|s| s.to_str())
                .unwrap_or("?");

            unblocked.push(format!(
                "Task #{} ({}) assigned to {} is now unblocked. ",
                file_id, subject, owner
            ));
        }
    }

    unblocked
}

/// Check if all blockers (other than the just-completed one) are also completed.
fn check_other_blockers_complete(team_dir: &Path, blocked_by: &[Value], completed_id: &str) -> bool {
    for blocker_val in blocked_by {
        let blocker_id = match blocker_val.as_str() {
            Some(id) => id,
            None => continue,
        };

        if blocker_id == completed_id {
            continue;
        }

        let blocker_file = team_dir.join(format!("{}.json", blocker_id));
        if blocker_file.exists() {
            let content = match fs::read_to_string(&blocker_file) {
                Ok(c) => c,
                Err(_) => return false,
            };
            let blocker: Value = match serde_json::from_str(&content) {
                Ok(v) => v,
                Err(_) => return false,
            };
            let status = blocker
                .get("status")
                .and_then(|v| v.as_str())
                .unwrap_or("pending");
            if status != "completed" {
                return false;
            }
        }
    }
    true
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn test_extract_task_id_from_task_id() {
        let input = json!({"task_id": "42"});
        assert_eq!(extract_task_id(&input), "42");
    }

    #[test]
    fn test_extract_task_id_from_nested() {
        let input = json!({"task": {"id": "99"}});
        assert_eq!(extract_task_id(&input), "99");
    }

    #[test]
    fn test_extract_task_id_missing() {
        let input = json!({});
        assert_eq!(extract_task_id(&input), "");
    }

    #[test]
    fn test_blocker_notify_empty_task_id() {
        let input = json!({});
        let (output, code) = blocker_notify(&input);
        assert_eq!(code, 0);
        assert_eq!(output, Value::Null);
    }

    #[test]
    fn test_scan_for_unblocked_all_clear() {
        let dir = tempfile::tempdir().unwrap();

        // Task blocked by "42", which we're completing
        std::fs::write(
            dir.path().join("100.json"),
            r#"{"status":"pending","subject":"Do stuff","owner":"dev-01","blockedBy":["42"]}"#,
        )
        .unwrap();

        let result = scan_for_unblocked(dir.path(), "42");
        assert_eq!(result.len(), 1);
        assert!(result[0].contains("Task #100"));
        assert!(result[0].contains("Do stuff"));
        assert!(result[0].contains("dev-01"));
    }

    #[test]
    fn test_scan_for_unblocked_still_blocked() {
        let dir = tempfile::tempdir().unwrap();

        // Task blocked by "42" AND "43" — "43" is not completed
        std::fs::write(
            dir.path().join("100.json"),
            r#"{"status":"pending","subject":"Do stuff","owner":"dev-01","blockedBy":["42","43"]}"#,
        )
        .unwrap();

        // "43" is still pending
        std::fs::write(
            dir.path().join("43.json"),
            r#"{"status":"pending","subject":"Other","owner":"dev-02"}"#,
        )
        .unwrap();

        let result = scan_for_unblocked(dir.path(), "42");
        assert!(result.is_empty());
    }

    #[test]
    fn test_scan_for_unblocked_other_blocker_complete() {
        let dir = tempfile::tempdir().unwrap();

        // Task blocked by "42" AND "43" — "43" IS completed
        std::fs::write(
            dir.path().join("100.json"),
            r#"{"status":"pending","subject":"Do stuff","owner":"dev-01","blockedBy":["42","43"]}"#,
        )
        .unwrap();

        std::fs::write(
            dir.path().join("43.json"),
            r#"{"status":"completed","subject":"Other","owner":"dev-02"}"#,
        )
        .unwrap();

        let result = scan_for_unblocked(dir.path(), "42");
        assert_eq!(result.len(), 1);
        assert!(result[0].contains("Task #100"));
    }

    #[test]
    fn test_scan_for_unblocked_completed_task_skipped() {
        let dir = tempfile::tempdir().unwrap();

        // Already completed task that was blocked by "42"
        std::fs::write(
            dir.path().join("100.json"),
            r#"{"status":"completed","subject":"Done","owner":"dev-01","blockedBy":["42"]}"#,
        )
        .unwrap();

        let result = scan_for_unblocked(dir.path(), "42");
        assert!(result.is_empty());
    }

    #[test]
    fn test_scan_for_unblocked_not_blocked_by_id() {
        let dir = tempfile::tempdir().unwrap();

        // Task blocked by "99", not "42"
        std::fs::write(
            dir.path().join("100.json"),
            r#"{"status":"pending","subject":"Other","owner":"dev-01","blockedBy":["99"]}"#,
        )
        .unwrap();

        let result = scan_for_unblocked(dir.path(), "42");
        assert!(result.is_empty());
    }

    #[test]
    fn test_check_other_blockers_complete_empty() {
        let dir = tempfile::tempdir().unwrap();
        let blocked_by = vec![json!("42")];
        assert!(check_other_blockers_complete(dir.path(), &blocked_by, "42"));
    }

    #[test]
    fn test_check_other_blockers_complete_missing_file() {
        let dir = tempfile::tempdir().unwrap();
        // Blocker file doesn't exist — treat as non-blocking (fail-open)
        let blocked_by = vec![json!("42"), json!("99")];
        assert!(check_other_blockers_complete(dir.path(), &blocked_by, "42"));
    }

    #[test]
    fn test_blocker_notify_no_tasks_dir() {
        // With default CLAUDE_CONFIG_DIR, tasks dir likely doesn't exist in test
        let input = json!({"task_id": "42"});
        let (_, code) = blocker_notify(&input);
        assert_eq!(code, 0);
    }
}
