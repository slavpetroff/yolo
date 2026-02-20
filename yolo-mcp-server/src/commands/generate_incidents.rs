use serde_json::Value;
use std::fs;
use std::path::Path;

/// Read event-log.jsonl, filter blockers/rejections for a phase, build markdown report.
pub fn generate_incidents(phase: u64, cwd: &Path) -> Result<(String, i32), String> {
    let planning_dir = cwd.join(".yolo-planning");
    let events_file = planning_dir.join(".events/event-log.jsonl");

    if !events_file.exists() {
        return Ok(("".to_string(), 0));
    }

    // Find phase directory
    let phases_dir = planning_dir.join("phases");
    let padded = format!("{:02}", phase);

    let phase_dir = find_phase_dir(&phases_dir, &padded, phase);
    let phase_dir = match phase_dir {
        Some(d) => d,
        None => return Ok(("".to_string(), 0)),
    };

    // Read and parse event log
    let content = fs::read_to_string(&events_file)
        .map_err(|e| format!("Failed to read event log: {}", e))?;

    let mut blocked: Vec<Value> = Vec::new();
    let mut rejected: Vec<Value> = Vec::new();

    for line in content.lines() {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        if let Ok(entry) = serde_json::from_str::<Value>(line) {
            let event_phase = entry.get("phase").and_then(|v| v.as_u64()).unwrap_or(0);
            if event_phase != phase {
                continue;
            }
            match entry.get("event").and_then(|v| v.as_str()) {
                Some("task_blocked") => blocked.push(entry),
                Some("task_completion_rejected") => rejected.push(entry),
                _ => {}
            }
        }
    }

    let total = blocked.len() + rejected.len();
    if total == 0 {
        return Ok(("".to_string(), 0));
    }

    // Build markdown report
    let mut md = String::new();
    md.push_str(&format!("# Phase {} Incidents\n\n", phase));
    md.push_str(&format!(
        "Auto-generated from event log. Total: {} incidents.\n\n",
        total
    ));

    // Blockers section
    md.push_str(&format!("## Blockers ({})\n\n", blocked.len()));
    if blocked.is_empty() {
        md.push_str("No blockers recorded.\n");
    } else {
        md.push_str("| Time | Task | Reason | Next Action |\n");
        md.push_str("|------|------|--------|-------------|\n");
        for entry in &blocked {
            let ts = entry.get("ts").and_then(|v| v.as_str()).unwrap_or("");
            let data = entry.get("data");
            let task_id = data
                .and_then(|d| d.get("task_id"))
                .and_then(|v| v.as_str())
                .unwrap_or("unknown");
            let reason = data
                .and_then(|d| {
                    d.get("reason")
                        .or_else(|| d.get("evidence"))
                })
                .and_then(|v| v.as_str())
                .unwrap_or("unspecified");
            let next_action = data
                .and_then(|d| d.get("next_action"))
                .and_then(|v| v.as_str())
                .unwrap_or("none");
            md.push_str(&format!(
                "| {} | {} | {} | {} |\n",
                ts, task_id, reason, next_action
            ));
        }
    }

    // Rejections section
    md.push_str(&format!("\n## Rejections ({})\n\n", rejected.len()));
    if rejected.is_empty() {
        md.push_str("No rejections recorded.\n");
    } else {
        md.push_str("| Time | Task | Reason |\n");
        md.push_str("|------|------|--------|\n");
        for entry in &rejected {
            let ts = entry.get("ts").and_then(|v| v.as_str()).unwrap_or("");
            let data = entry.get("data");
            let task_id = data
                .and_then(|d| d.get("task_id"))
                .and_then(|v| v.as_str())
                .unwrap_or("unknown");
            let reason = data
                .and_then(|d| {
                    d.get("reason")
                        .or_else(|| d.get("evidence"))
                })
                .and_then(|v| v.as_str())
                .unwrap_or("unspecified");
            md.push_str(&format!("| {} | {} | {} |\n", ts, task_id, reason));
        }
    }

    // Write incidents file
    let incidents_file = phase_dir.join(format!("{}-INCIDENTS.md", padded));
    fs::write(&incidents_file, &md)
        .map_err(|e| format!("Failed to write incidents file: {}", e))?;

    Ok((incidents_file.to_string_lossy().to_string(), 0))
}

/// Find the phase directory matching the given phase number.
fn find_phase_dir(phases_dir: &Path, padded: &str, phase: u64) -> Option<std::path::PathBuf> {
    if !phases_dir.is_dir() {
        return None;
    }

    let entries = fs::read_dir(phases_dir).ok()?;
    for entry in entries.filter_map(|e| e.ok()) {
        if !entry.file_type().map(|ft| ft.is_dir()).unwrap_or(false) {
            continue;
        }
        let name = entry.file_name().to_string_lossy().to_string();
        if name.starts_with(&format!("{}-", padded)) || name.starts_with(&format!("{}-", phase)) {
            return Some(entry.path());
        }
    }
    None
}

/// CLI entry point: `yolo incidents <phase>`
pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    if args.len() < 3 {
        return Err("Usage: yolo incidents <phase-number>".to_string());
    }

    let phase: u64 = args[2]
        .parse()
        .map_err(|_| format!("Invalid phase number: {}", args[2]))?;

    generate_incidents(phase, cwd)
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn setup_test_env(phase: u64) -> TempDir {
        let dir = TempDir::new().unwrap();
        let planning = dir.path().join(".yolo-planning");
        let padded = format!("{:02}", phase);
        fs::create_dir_all(planning.join(format!("phases/{}-test", padded))).unwrap();
        fs::create_dir_all(planning.join(".events")).unwrap();
        dir
    }

    fn write_events(dir: &Path, events: &[Value]) {
        let events_file = dir.join(".yolo-planning/.events/event-log.jsonl");
        let content: String = events
            .iter()
            .map(|e| serde_json::to_string(e).unwrap())
            .collect::<Vec<_>>()
            .join("\n");
        fs::write(&events_file, content).unwrap();
    }

    #[test]
    fn test_no_events_file() {
        let dir = TempDir::new().unwrap();
        let (output, code) = generate_incidents(1, dir.path()).unwrap();
        assert_eq!(code, 0);
        assert!(output.is_empty());
    }

    #[test]
    fn test_no_matching_phase_dir() {
        let dir = TempDir::new().unwrap();
        let planning = dir.path().join(".yolo-planning");
        fs::create_dir_all(planning.join(".events")).unwrap();
        fs::write(
            planning.join(".events/event-log.jsonl"),
            r#"{"event":"task_blocked","phase":99}"#,
        )
        .unwrap();

        let (output, code) = generate_incidents(99, dir.path()).unwrap();
        assert_eq!(code, 0);
        assert!(output.is_empty());
    }

    #[test]
    fn test_no_incidents() {
        let dir = setup_test_env(1);
        write_events(
            dir.path(),
            &[serde_json::json!({"event":"phase_start","phase":1})],
        );

        let (output, code) = generate_incidents(1, dir.path()).unwrap();
        assert_eq!(code, 0);
        assert!(output.is_empty());
    }

    #[test]
    fn test_blockers_only() {
        let dir = setup_test_env(2);
        write_events(
            dir.path(),
            &[serde_json::json!({
                "event": "task_blocked",
                "phase": 2,
                "ts": "2026-02-20T10:00:00Z",
                "data": {
                    "task_id": "task-1",
                    "reason": "dependency missing",
                    "next_action": "wait"
                }
            })],
        );

        let (output, code) = generate_incidents(2, dir.path()).unwrap();
        assert_eq!(code, 0);
        assert!(!output.is_empty());

        // Read generated file
        let content = fs::read_to_string(&output).unwrap();
        assert!(content.contains("# Phase 2 Incidents"));
        assert!(content.contains("Total: 1 incidents"));
        assert!(content.contains("dependency missing"));
        assert!(content.contains("## Blockers (1)"));
        assert!(content.contains("## Rejections (0)"));
    }

    #[test]
    fn test_rejections_only() {
        let dir = setup_test_env(3);
        write_events(
            dir.path(),
            &[serde_json::json!({
                "event": "task_completion_rejected",
                "phase": 3,
                "ts": "2026-02-20T11:00:00Z",
                "data": {
                    "task_id": "task-5",
                    "reason": "tests failing"
                }
            })],
        );

        let (output, code) = generate_incidents(3, dir.path()).unwrap();
        assert_eq!(code, 0);

        let content = fs::read_to_string(&output).unwrap();
        assert!(content.contains("## Rejections (1)"));
        assert!(content.contains("tests failing"));
    }

    #[test]
    fn test_mixed_incidents() {
        let dir = setup_test_env(1);
        write_events(
            dir.path(),
            &[
                serde_json::json!({
                    "event": "task_blocked",
                    "phase": 1,
                    "ts": "2026-02-20T10:00:00Z",
                    "data": {"task_id": "t1", "reason": "blocked"}
                }),
                serde_json::json!({
                    "event": "task_completion_rejected",
                    "phase": 1,
                    "ts": "2026-02-20T11:00:00Z",
                    "data": {"task_id": "t2", "reason": "rejected"}
                }),
                serde_json::json!({
                    "event": "phase_start",
                    "phase": 1,
                    "ts": "2026-02-20T09:00:00Z"
                }),
            ],
        );

        let (output, code) = generate_incidents(1, dir.path()).unwrap();
        assert_eq!(code, 0);

        let content = fs::read_to_string(&output).unwrap();
        assert!(content.contains("Total: 2 incidents"));
        assert!(content.contains("## Blockers (1)"));
        assert!(content.contains("## Rejections (1)"));
    }

    #[test]
    fn test_filters_by_phase() {
        let dir = setup_test_env(1);
        write_events(
            dir.path(),
            &[
                serde_json::json!({
                    "event": "task_blocked",
                    "phase": 1,
                    "ts": "2026-02-20T10:00:00Z",
                    "data": {"task_id": "t1", "reason": "phase 1 blocker"}
                }),
                serde_json::json!({
                    "event": "task_blocked",
                    "phase": 2,
                    "ts": "2026-02-20T10:00:00Z",
                    "data": {"task_id": "t2", "reason": "phase 2 blocker"}
                }),
            ],
        );

        let (output, code) = generate_incidents(1, dir.path()).unwrap();
        assert_eq!(code, 0);

        let content = fs::read_to_string(&output).unwrap();
        assert!(content.contains("phase 1 blocker"));
        assert!(!content.contains("phase 2 blocker"));
    }

    #[test]
    fn test_execute_cli_missing_args() {
        let dir = TempDir::new().unwrap();
        let args: Vec<String> = vec!["yolo".into(), "incidents".into()];
        assert!(execute(&args, dir.path()).is_err());
    }

    #[test]
    fn test_execute_cli_invalid_phase() {
        let dir = TempDir::new().unwrap();
        let args: Vec<String> = vec!["yolo".into(), "incidents".into(), "abc".into()];
        assert!(execute(&args, dir.path()).is_err());
    }
}
