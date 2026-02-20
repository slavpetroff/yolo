use serde_json::{json, Value};
use std::fs;
use std::path::Path;

/// CLI entry: `yolo recover-state <phase> [phases-dir]`
/// Rebuild .execution-state.json from event log + SUMMARY.md files.
/// Fail-open: returns empty JSON object on errors.
pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    if args.len() < 1 {
        return Ok(("{}".to_string(), 0));
    }

    let phase_str = &args[0];
    let phase: i64 = phase_str.parse().unwrap_or(0);

    let planning_dir = cwd.join(".yolo-planning");
    let config_path = planning_dir.join("config.json");

    // Check v3_event_recovery feature flag
    if config_path.exists() {
        if let Ok(content) = fs::read_to_string(&config_path) {
            if let Ok(config) = serde_json::from_str::<Value>(&content) {
                let enabled = config
                    .get("v3_event_recovery")
                    .and_then(|v| v.as_bool())
                    .unwrap_or(false);
                if !enabled {
                    return Ok(("{}".to_string(), 0));
                }
            }
        }
    }

    let phases_dir = if args.len() > 1 {
        cwd.join(&args[1])
    } else {
        planning_dir.join("phases")
    };

    let events_file = planning_dir.join(".events").join("event-log.jsonl");

    // Find phase directory matching NN-slug pattern
    let phase_prefix = format!("{:02}-", phase);
    let phase_dir = find_phase_dir(&phases_dir, &phase_prefix);

    let phase_dir = match phase_dir {
        Some(d) => d,
        None => return Ok(("{}".to_string(), 0)),
    };

    let phase_slug = phase_dir
        .file_name()
        .unwrap_or_default()
        .to_string_lossy()
        .trim_start_matches(&phase_prefix)
        .to_string();

    // Collect plans from *-PLAN.md files
    let plans = collect_plans(&phase_dir, phase, &events_file);

    // Determine overall status
    let total = plans.len();
    let complete = plans.iter().filter(|p| p.status == "complete").count();
    let failed = plans.iter().filter(|p| p.status == "failed").count();

    let status = if complete == total && total > 0 {
        "complete"
    } else if failed > 0 {
        "failed"
    } else if complete > 0 {
        "running"
    } else {
        "pending"
    };

    // Determine wave info
    let max_wave = plans.iter().map(|p| p.wave).max().unwrap_or(1);
    let current_wave = plans
        .iter()
        .filter(|p| p.status == "pending" || p.status == "running")
        .map(|p| p.wave)
        .min()
        .unwrap_or(1);

    // Build plans JSON array
    let plans_json: Vec<Value> = plans
        .iter()
        .map(|p| {
            json!({
                "id": p.id,
                "title": p.title,
                "wave": p.wave,
                "status": p.status
            })
        })
        .collect();

    let result = json!({
        "phase": phase,
        "phase_name": phase_slug,
        "status": status,
        "wave": current_wave,
        "total_waves": max_wave,
        "plans": plans_json
    });

    let output = serde_json::to_string_pretty(&result).unwrap_or_else(|_| "{}".to_string());
    Ok((output, 0))
}

struct PlanInfo {
    id: String,
    title: String,
    wave: i64,
    status: String,
}

fn find_phase_dir(phases_dir: &Path, prefix: &str) -> Option<std::path::PathBuf> {
    if !phases_dir.is_dir() {
        return None;
    }

    let entries = fs::read_dir(phases_dir).ok()?;
    for entry in entries.flatten() {
        let name = entry.file_name().to_string_lossy().to_string();
        if name.starts_with(prefix) && entry.path().is_dir() {
            return Some(entry.path());
        }
    }
    None
}

fn collect_plans(phase_dir: &Path, phase: i64, events_file: &Path) -> Vec<PlanInfo> {
    let mut plans = Vec::new();

    let entries = match fs::read_dir(phase_dir) {
        Ok(e) => e,
        Err(_) => return plans,
    };

    let mut plan_files: Vec<String> = entries
        .flatten()
        .filter_map(|e| {
            let name = e.file_name().to_string_lossy().to_string();
            if name.ends_with("-PLAN.md") {
                Some(name)
            } else {
                None
            }
        })
        .collect();
    plan_files.sort();

    // Read event log once
    let event_lines = if events_file.exists() {
        fs::read_to_string(events_file).unwrap_or_default()
    } else {
        String::new()
    };

    for plan_file in &plan_files {
        let plan_id = plan_file.trim_end_matches("-PLAN.md").to_string();
        let plan_path = phase_dir.join(plan_file);
        let plan_content = fs::read_to_string(&plan_path).unwrap_or_default();

        // Extract title and wave from frontmatter-like content
        let title = extract_field(&plan_content, "title").unwrap_or_else(|| "unknown".to_string());
        let wave: i64 = extract_field(&plan_content, "wave")
            .and_then(|w| w.parse().ok())
            .unwrap_or(1);

        // Check if SUMMARY.md exists
        let summary_file = phase_dir.join(format!("{}-SUMMARY.md", plan_id));
        let mut status = if summary_file.exists() {
            "complete".to_string()
        } else {
            "pending".to_string()
        };

        // Cross-reference event log for plan_end events
        if status == "pending" && !event_lines.is_empty() {
            let plan_num = plan_id
                .split('-')
                .nth(1)
                .unwrap_or("")
                .to_string();

            if let Some(event_status) =
                check_event_log(&event_lines, phase, &plan_num)
            {
                status = event_status;
            }
        }

        plans.push(PlanInfo {
            id: plan_id,
            title,
            wave,
            status,
        });
    }

    plans
}

fn extract_field(content: &str, field: &str) -> Option<String> {
    for line in content.lines() {
        let trimmed = line.trim();
        let prefix = format!("{}:", field);
        if trimmed.starts_with(&prefix) {
            let value = trimmed[prefix.len()..].trim().trim_matches('"').to_string();
            if !value.is_empty() {
                return Some(value);
            }
        }
    }
    None
}

fn check_event_log(event_lines: &str, phase: i64, plan_num: &str) -> Option<String> {
    let mut last_status = None;

    for line in event_lines.lines() {
        if line.is_empty() {
            continue;
        }
        if !line.contains("\"plan_end\"") {
            continue;
        }

        if let Ok(event) = serde_json::from_str::<Value>(line) {
            let ev_type = event.get("type").and_then(|v| v.as_str()).unwrap_or("");
            if ev_type != "plan_end" {
                continue;
            }

            let ev_phase = event.get("phase").and_then(|v| v.as_i64()).unwrap_or(-1);
            if ev_phase != phase {
                continue;
            }

            let ev_plan = event
                .get("plan")
                .and_then(|v| {
                    v.as_str()
                        .map(|s| s.to_string())
                        .or_else(|| v.as_i64().map(|n| n.to_string()))
                })
                .unwrap_or_default();

            if ev_plan == plan_num || plan_num.is_empty() {
                let status = event
                    .get("data")
                    .and_then(|d| d.get("status"))
                    .and_then(|v| v.as_str())
                    .unwrap_or("unknown");
                if status == "complete" || status == "failed" {
                    last_status = Some(status.to_string());
                }
            }
        }
    }

    last_status
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn setup_test_env() -> TempDir {
        let dir = TempDir::new().unwrap();
        let planning = dir.path().join(".yolo-planning");
        let phases = planning.join("phases");
        let phase_dir = phases.join("01-setup");
        fs::create_dir_all(&phase_dir).unwrap();

        // Enable feature flag
        fs::write(
            planning.join("config.json"),
            r#"{"v3_event_recovery": true}"#,
        )
        .unwrap();

        // Create plan files
        fs::write(
            phase_dir.join("01-01-PLAN.md"),
            "title: \"Bootstrap project\"\nwave: 1\n",
        )
        .unwrap();
        fs::write(
            phase_dir.join("01-02-PLAN.md"),
            "title: \"Add tests\"\nwave: 1\n",
        )
        .unwrap();
        fs::write(
            phase_dir.join("01-03-PLAN.md"),
            "title: \"Deploy\"\nwave: 2\n",
        )
        .unwrap();

        dir
    }

    #[test]
    fn test_recover_all_pending() {
        let dir = setup_test_env();
        let args = vec!["1".into()];
        let (out, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);

        let result: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(result["phase"], 1);
        assert_eq!(result["phase_name"], "setup");
        assert_eq!(result["status"], "pending");
        assert_eq!(result["plans"].as_array().unwrap().len(), 3);
    }

    #[test]
    fn test_recover_partial_complete() {
        let dir = setup_test_env();
        let phase_dir = dir.path().join(".yolo-planning/phases/01-setup");

        // Mark first plan complete via SUMMARY.md
        fs::write(phase_dir.join("01-01-SUMMARY.md"), "---\nstatus: complete\n---\n").unwrap();

        let args = vec!["1".into()];
        let (out, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);

        let result: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(result["status"], "running");

        let plans = result["plans"].as_array().unwrap();
        assert_eq!(plans[0]["status"], "complete");
        assert_eq!(plans[1]["status"], "pending");
    }

    #[test]
    fn test_recover_all_complete() {
        let dir = setup_test_env();
        let phase_dir = dir.path().join(".yolo-planning/phases/01-setup");

        for id in &["01-01", "01-02", "01-03"] {
            fs::write(
                phase_dir.join(format!("{}-SUMMARY.md", id)),
                "---\nstatus: complete\n---\n",
            )
            .unwrap();
        }

        let args = vec!["1".into()];
        let (out, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);

        let result: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(result["status"], "complete");
    }

    #[test]
    fn test_recover_with_event_log() {
        let dir = setup_test_env();
        let events_dir = dir.path().join(".yolo-planning/.events");
        fs::create_dir_all(&events_dir).unwrap();

        // Add a plan_end event marking plan 02 as failed
        let event = json!({"type": "plan_end", "phase": 1, "plan": "02", "data": {"status": "failed"}});
        fs::write(
            events_dir.join("event-log.jsonl"),
            format!("{}\n", event),
        )
        .unwrap();

        let args = vec!["1".into()];
        let (out, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);

        let result: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(result["status"], "failed");

        let plans = result["plans"].as_array().unwrap();
        let plan2 = plans.iter().find(|p| p["id"] == "01-02").unwrap();
        assert_eq!(plan2["status"], "failed");
    }

    #[test]
    fn test_recover_feature_disabled() {
        let dir = TempDir::new().unwrap();
        let planning = dir.path().join(".yolo-planning");
        fs::create_dir_all(&planning).unwrap();
        fs::write(
            planning.join("config.json"),
            r#"{"v3_event_recovery": false}"#,
        )
        .unwrap();

        let args = vec!["1".into()];
        let (out, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
        assert_eq!(out, "{}");
    }

    #[test]
    fn test_recover_no_phase_dir() {
        let dir = TempDir::new().unwrap();
        let planning = dir.path().join(".yolo-planning");
        fs::create_dir_all(planning.join("phases")).unwrap();
        fs::write(
            planning.join("config.json"),
            r#"{"v3_event_recovery": true}"#,
        )
        .unwrap();

        let args = vec!["99".into()];
        let (out, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
        assert_eq!(out, "{}");
    }

    #[test]
    fn test_recover_wave_tracking() {
        let dir = setup_test_env();
        let phase_dir = dir.path().join(".yolo-planning/phases/01-setup");

        // Complete wave 1 plans
        fs::write(phase_dir.join("01-01-SUMMARY.md"), "---\nstatus: complete\n---\n").unwrap();
        fs::write(phase_dir.join("01-02-SUMMARY.md"), "---\nstatus: complete\n---\n").unwrap();

        let args = vec!["1".into()];
        let (out, _) = execute(&args, dir.path()).unwrap();
        let result: Value = serde_json::from_str(&out).unwrap();

        // Wave 1 done, wave 2 pending — current_wave should be 2
        assert_eq!(result["wave"], 2);
        assert_eq!(result["total_waves"], 2);
    }

    #[test]
    fn test_extract_field() {
        assert_eq!(
            extract_field("title: \"hello world\"\nwave: 2", "title"),
            Some("hello world".to_string())
        );
        assert_eq!(
            extract_field("title: \"hello world\"\nwave: 2", "wave"),
            Some("2".to_string())
        );
        assert_eq!(extract_field("nothing here", "title"), None);
    }
}
