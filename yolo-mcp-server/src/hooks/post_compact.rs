use serde_json::{json, Value};
use std::fs;
use std::path::Path;

use super::utils;

/// SessionStart(compact) handler: remind agent to re-read key files after compaction.
///
/// - Cleans up `.cost-ledger.json` and `.compaction-marker`
/// - Detects agent role from input context
/// - Maps role to suggested re-read files
/// - Attempts snapshot restore for task context
/// - Returns hookSpecificOutput with re-read guidance
/// - Always exit 0
pub fn handle_post_compact(input: &Value) -> (Value, i32) {
    let planning = Path::new(".yolo-planning");

    // Clean up stale files
    cleanup_stale_files(planning);

    // Detect role from input context
    let role = detect_role_from_input(input);
    let files = role_reread_files(&role);

    // Attempt snapshot restore
    let snapshot_context = restore_snapshot(planning, &role);

    // Task hint for teammates
    let task_hint = if role != "unknown" {
        " If you are a teammate, call TaskGet for your assigned task ID to restore your current objective."
    } else {
        ""
    };

    let additional = format!(
        "Context was compacted. Agent role: {}. Re-read these key files from disk: {}{}{}",
        role, files, snapshot_context, task_hint
    );

    let output = json!({
        "hookSpecificOutput": {
            "hookEventName": "SessionStart",
            "additionalContext": additional
        }
    });

    (output, 0)
}

/// Remove stale cost tracking and compaction marker files.
fn cleanup_stale_files(planning: &Path) {
    let _ = fs::remove_file(planning.join(".cost-ledger.json"));
    let _ = fs::remove_file(planning.join(".compaction-marker"));
}

/// Detect agent role by scanning the input JSON for known patterns.
fn detect_role_from_input(input: &Value) -> String {
    let input_str = input.to_string().to_lowercase();

    let patterns = [
        ("yolo-lead", "lead"),
        ("yolo-dev", "dev"),
        ("yolo-qa", "qa"),
        ("yolo-scout", "scout"),
        ("yolo-debugger", "debugger"),
        ("yolo-architect", "architect"),
        ("yolo-docs", "docs"),
    ];

    for (pattern, role) in &patterns {
        if input_str.contains(pattern) {
            return role.to_string();
        }
    }

    "unknown".to_string()
}

/// Map role to suggested re-read files after compaction.
fn role_reread_files(role: &str) -> &'static str {
    match role {
        "lead" => "STATE.md, ROADMAP.md, config.json, and current phase plans",
        "dev" => "your assigned plan file, SUMMARY.md template, and relevant source files",
        "qa" => "SUMMARY.md files under review, verification criteria, and gap reports",
        "scout" => "research notes, REQUIREMENTS.md, and any scout-specific findings",
        "debugger" => "reproduction steps, hypothesis log, and related source files",
        "architect" => {
            "REQUIREMENTS.md, ROADMAP.md, phase structure, and architecture decisions"
        }
        _ => "STATE.md, your assigned task context, and any in-progress files",
    }
}

/// Attempt to restore the most recent snapshot for the current phase/role.
/// Returns context string to append, or empty string.
fn restore_snapshot(planning: &Path, _role: &str) -> String {
    let exec_state_path = planning.join(".execution-state.json");
    if !exec_state_path.is_file() {
        return String::new();
    }

    let exec_content = match fs::read_to_string(&exec_state_path) {
        Ok(c) => c,
        Err(_) => return String::new(),
    };
    let exec_state: Value = match serde_json::from_str(&exec_content) {
        Ok(v) => v,
        Err(_) => return String::new(),
    };

    let phase = match exec_state.get("phase") {
        Some(Value::String(s)) => s.clone(),
        Some(Value::Number(n)) => n.to_string(),
        _ => return String::new(),
    };

    if phase.is_empty() {
        return String::new();
    }

    // Find the latest snapshot for this phase
    let snapshots_dir = planning.join("snapshots");
    if !snapshots_dir.is_dir() {
        return String::new();
    }

    let prefix = format!("snap-{}-", phase);
    let mut snap_files: Vec<_> = match fs::read_dir(&snapshots_dir) {
        Ok(rd) => rd
            .filter_map(|e| e.ok())
            .filter(|e| {
                e.file_name()
                    .to_str()
                    .map(|n| n.starts_with(&prefix) && n.ends_with(".json"))
                    .unwrap_or(false)
            })
            .map(|e| e.path())
            .collect(),
        Err(_) => return String::new(),
    };

    snap_files.sort();
    let snap_path = match snap_files.last() {
        Some(p) => p,
        None => return String::new(),
    };

    let snap_content = match fs::read_to_string(snap_path) {
        Ok(c) => c,
        Err(_) => return String::new(),
    };
    let snapshot: Value = match serde_json::from_str(&snap_content) {
        Ok(v) => v,
        Err(_) => return String::new(),
    };

    let snap_status = snapshot
        .pointer("/execution_state/status")
        .and_then(|v| v.as_str())
        .unwrap_or("unknown");

    let snap_plan = find_current_plan(&snapshot);

    // Build task context from event log
    let (in_progress_task, last_completed_task, next_task) =
        find_task_context(planning, &phase, &snap_plan, &snapshot);

    let mut ctx = format!(
        " Pre-compaction state: phase={}, plan={}, status={}.",
        phase, snap_plan, snap_status
    );

    if !in_progress_task.is_empty() {
        ctx.push_str(&format!(
            " In-progress task before compact: {}.",
            in_progress_task
        ));
    } else if !next_task.is_empty() {
        ctx.push_str(&format!(" Resume candidate: {}.", next_task));
    }

    if !last_completed_task.is_empty() {
        ctx.push_str(&format!(" Last completed task: {}.", last_completed_task));
    }

    // Log restore
    utils::log_hook_message(
        planning,
        &format!(
            "Snapshot restored: {} phase={}",
            snap_path.display(),
            phase
        ),
    );

    ctx
}

/// Find the current plan from snapshot execution state.
fn find_current_plan(snapshot: &Value) -> String {
    // Try explicit current_plan first
    if let Some(plan) = snapshot
        .pointer("/execution_state/current_plan")
        .and_then(|v| v.as_str())
    {
        return plan.to_string();
    }

    // Fallback: find first running/pending plan
    if let Some(plans) = snapshot
        .pointer("/execution_state/plans")
        .and_then(|v| v.as_array())
    {
        for plan in plans {
            let status = plan.get("status").and_then(|v| v.as_str()).unwrap_or("");
            if status == "running" || status == "pending" {
                if let Some(id) = plan.get("id").and_then(|v| v.as_str()) {
                    return id.to_string();
                }
            }
        }
        // Fallback: first plan by id
        if let Some(first) = plans.first() {
            if let Some(id) = first.get("id").and_then(|v| v.as_str()) {
                return id.to_string();
            }
        }
    }

    "unknown".to_string()
}

/// Extract task resume context from event log.
/// Returns (in_progress_task, last_completed_task, next_task).
fn find_task_context(
    planning: &Path,
    phase: &str,
    plan_id: &str,
    snapshot: &Value,
) -> (String, String, String) {
    let event_log = planning.join(".events").join("event-log.jsonl");
    if !event_log.is_file() {
        return (String::new(), String::new(), String::new());
    }

    // Parse plan number from plan_id (e.g. "05-01" -> 1)
    let plan_num = plan_id_to_num(plan_id);
    if plan_num == 0 {
        return (String::new(), String::new(), String::new());
    }

    let content = match fs::read_to_string(&event_log) {
        Ok(c) => c,
        Err(_) => return (String::new(), String::new(), String::new()),
    };

    let phase_num: i64 = phase.parse().unwrap_or(0);
    let mut last_started: String = String::new();
    let mut last_completed: String = String::new();

    for line in content.lines() {
        let entry: Value = match serde_json::from_str(line) {
            Ok(v) => v,
            Err(_) => continue,
        };

        let event_phase = entry.get("phase").and_then(|v| v.as_i64()).unwrap_or(-1);
        let event_plan = entry.get("plan").and_then(|v| v.as_i64()).unwrap_or(-1);

        if event_phase != phase_num || event_plan != plan_num as i64 {
            continue;
        }

        let event_type = entry.get("event").and_then(|v| v.as_str()).unwrap_or("");
        let task_id = entry
            .pointer("/data/task_id")
            .and_then(|v| v.as_str())
            .unwrap_or("");

        if event_type == "task_started" && !task_id.is_empty() {
            last_started = task_id.to_string();
        }
        if event_type == "task_completed_confirmed" && !task_id.is_empty() {
            last_completed = task_id.to_string();
        }
    }

    // Determine in-progress task
    let explicit_task = snapshot
        .pointer("/execution_state/current_task_id")
        .and_then(|v| v.as_str())
        .unwrap_or("");

    let in_progress = if !explicit_task.is_empty() {
        explicit_task.to_string()
    } else if !last_started.is_empty() && last_started != last_completed {
        last_started
    } else {
        String::new()
    };

    let next = if !last_completed.is_empty() {
        next_task_from_completed(&last_completed)
    } else {
        String::new()
    };

    (in_progress, last_completed, next)
}

/// Convert plan id (e.g. "05-01") to numeric plan number (e.g. 1).
fn plan_id_to_num(plan_id: &str) -> u32 {
    let parts: Vec<&str> = plan_id.split('-').collect();
    if parts.len() >= 2 {
        parts[1].parse().unwrap_or(0)
    } else {
        plan_id.parse().unwrap_or(0)
    }
}

/// Build next task id from last completed (e.g. "1-1-T3" -> "1-1-T4").
fn next_task_from_completed(task_id: &str) -> String {
    if let Some(t_pos) = task_id.rfind('T') {
        let prefix = &task_id[..t_pos + 1];
        let num_str = &task_id[t_pos + 1..];
        if let Ok(num) = num_str.parse::<u32>() {
            return format!("{}{}", prefix, num + 1);
        }
    }
    String::new()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_detect_role_lead() {
        let input = json!({"context": "yolo-lead session"});
        assert_eq!(detect_role_from_input(&input), "lead");
    }

    #[test]
    fn test_detect_role_dev() {
        let input = json!({"agent": "yolo-dev-1"});
        assert_eq!(detect_role_from_input(&input), "dev");
    }

    #[test]
    fn test_detect_role_unknown() {
        let input = json!({"context": "some random input"});
        assert_eq!(detect_role_from_input(&input), "unknown");
    }

    #[test]
    fn test_role_reread_files_lead() {
        let files = role_reread_files("lead");
        assert!(files.contains("STATE.md"));
        assert!(files.contains("ROADMAP.md"));
    }

    #[test]
    fn test_role_reread_files_dev() {
        let files = role_reread_files("dev");
        assert!(files.contains("plan file"));
        assert!(files.contains("source files"));
    }

    #[test]
    fn test_role_reread_files_default() {
        let files = role_reread_files("unknown");
        assert!(files.contains("STATE.md"));
    }

    #[test]
    fn test_plan_id_to_num() {
        assert_eq!(plan_id_to_num("05-01"), 1);
        assert_eq!(plan_id_to_num("01-03"), 3);
        assert_eq!(plan_id_to_num("3"), 3);
        assert_eq!(plan_id_to_num("bad"), 0);
    }

    #[test]
    fn test_next_task_from_completed() {
        assert_eq!(next_task_from_completed("1-1-T3"), "1-1-T4");
        assert_eq!(next_task_from_completed("2-5-T10"), "2-5-T11");
        assert_eq!(next_task_from_completed("no-match"), "");
    }

    #[test]
    fn test_handle_post_compact_dev() {
        let input = json!({"context": "yolo-dev-1 working on task"});
        let (output, code) = handle_post_compact(&input);
        assert_eq!(code, 0);

        let ctx = output["hookSpecificOutput"]["additionalContext"]
            .as_str()
            .unwrap();
        assert!(ctx.contains("Context was compacted"));
        assert!(ctx.contains("dev"));
        assert!(ctx.contains("plan file"));
    }

    #[test]
    fn test_handle_post_compact_unknown_role() {
        let input = json!({"data": "nothing relevant"});
        let (output, code) = handle_post_compact(&input);
        assert_eq!(code, 0);

        let ctx = output["hookSpecificOutput"]["additionalContext"]
            .as_str()
            .unwrap();
        assert!(ctx.contains("unknown"));
        assert!(ctx.contains("STATE.md"));
    }

    #[test]
    fn test_handle_post_compact_output_structure() {
        let input = json!({});
        let (output, code) = handle_post_compact(&input);
        assert_eq!(code, 0);
        assert!(output.get("hookSpecificOutput").is_some());
        assert_eq!(
            output["hookSpecificOutput"]["hookEventName"],
            "SessionStart"
        );
    }

    #[test]
    fn test_cleanup_stale_files() {
        let dir = tempfile::tempdir().unwrap();
        let planning = dir.path();

        // Create files to clean up
        fs::write(planning.join(".cost-ledger.json"), "{}").unwrap();
        fs::write(planning.join(".compaction-marker"), "123").unwrap();

        cleanup_stale_files(planning);

        assert!(!planning.join(".cost-ledger.json").exists());
        assert!(!planning.join(".compaction-marker").exists());
    }

    #[test]
    fn test_find_current_plan_explicit() {
        let snapshot = json!({
            "execution_state": {
                "current_plan": "02-03"
            }
        });
        assert_eq!(find_current_plan(&snapshot), "02-03");
    }

    #[test]
    fn test_find_current_plan_from_plans_array() {
        let snapshot = json!({
            "execution_state": {
                "plans": [
                    {"id": "02-01", "status": "completed"},
                    {"id": "02-02", "status": "running"},
                    {"id": "02-03", "status": "pending"}
                ]
            }
        });
        assert_eq!(find_current_plan(&snapshot), "02-02");
    }

    #[test]
    fn test_find_current_plan_fallback_first() {
        let snapshot = json!({
            "execution_state": {
                "plans": [
                    {"id": "02-01", "status": "completed"}
                ]
            }
        });
        assert_eq!(find_current_plan(&snapshot), "02-01");
    }

    #[test]
    fn test_find_current_plan_unknown() {
        let snapshot = json!({"execution_state": {}});
        assert_eq!(find_current_plan(&snapshot), "unknown");
    }
}
