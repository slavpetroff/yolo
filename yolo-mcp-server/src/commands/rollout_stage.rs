use serde_json::{json, Value};
use std::fs;
use std::path::Path;

/// Default rollout stages when no rollout-stages.json exists.
const DEFAULT_STAGES: &[(&str, &str)] = &[
    ("canary", "Single agent, limited scope"),
    ("partial", "Half of agents, expanded scope"),
    ("full", "All agents, full scope"),
];

/// CLI entry point: `yolo rollout <action> [stage]`
/// Actions: check, advance, status
pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    if args.len() < 3 {
        return Err("Usage: yolo rollout {check|advance|status} [stage]".to_string());
    }

    let action = &args[2];
    let planning_dir = cwd.join(".yolo-planning");

    match action.as_str() {
        "check" => rollout_check(&planning_dir),
        "advance" => rollout_advance(&planning_dir),
        "status" => rollout_status(&planning_dir),
        _ => Err(format!("Unknown rollout action: '{}'. Use: check, advance, status", action)),
    }
}

/// Load rollout stage definitions from rollout-stages.json or use defaults.
fn load_stages(planning_dir: &Path) -> Vec<(String, String)> {
    let stages_file = planning_dir.join("rollout-stages.json");
    if stages_file.exists()
        && let Ok(content) = fs::read_to_string(&stages_file)
        && let Ok(val) = serde_json::from_str::<Value>(&content)
        && let Some(stages) = val.get("stages").and_then(|v| v.as_array())
    {
        return stages.iter().filter_map(|s| {
            let name = s.get("name")?.as_str()?.to_string();
            let desc = s.get("description").and_then(|d| d.as_str()).unwrap_or("").to_string();
            Some((name, desc))
        }).collect();
    }
    DEFAULT_STAGES.iter().map(|(n, d)| (n.to_string(), d.to_string())).collect()
}

/// Count completed phases from the event log.
fn count_completed_phases(planning_dir: &Path) -> usize {
    let events_file = planning_dir.join(".events/event-log.jsonl");
    if !events_file.exists() {
        return 0;
    }

    let content = match fs::read_to_string(&events_file) {
        Ok(c) => c,
        Err(_) => return 0,
    };

    let mut completed_phases = std::collections::HashSet::new();
    for line in content.lines() {
        if let Ok(event) = serde_json::from_str::<Value>(line)
            && event.get("event").and_then(|e| e.as_str()) == Some("phase_end")
            && let Some(phase) = event.get("phase").and_then(|p| p.as_i64())
        {
            completed_phases.insert(phase);
        }
    }

    completed_phases.len()
}

/// Get the current rollout stage from config.json.
fn get_current_stage(planning_dir: &Path) -> Option<String> {
    let config_path = planning_dir.join("config.json");
    if !config_path.exists() {
        return None;
    }
    let content = fs::read_to_string(&config_path).ok()?;
    let config: Value = serde_json::from_str(&content).ok()?;
    config.get("rollout_stage").and_then(|v| v.as_str()).map(|s| s.to_string())
}

/// Set the rollout stage in config.json.
fn set_rollout_stage(planning_dir: &Path, stage: &str) -> Result<(), String> {
    let config_path = planning_dir.join("config.json");

    let mut config: Value = if config_path.exists() {
        let content = fs::read_to_string(&config_path)
            .map_err(|e| format!("Failed to read config: {}", e))?;
        serde_json::from_str(&content)
            .map_err(|e| format!("Invalid config JSON: {}", e))?
    } else {
        json!({})
    };

    config["rollout_stage"] = json!(stage);

    // Apply stage-specific flags
    match stage {
        "canary" => {
            config["max_agents"] = json!(1);
            config["rollout_scope"] = json!("limited");
        }
        "partial" => {
            config["max_agents"] = json!(4);
            config["rollout_scope"] = json!("expanded");
        }
        "full" => {
            config["max_agents"] = json!(8);
            config["rollout_scope"] = json!("full");
        }
        _ => {}
    }

    let output = serde_json::to_string_pretty(&config)
        .map_err(|e| format!("Failed to serialize config: {}", e))?;
    fs::write(&config_path, format!("{}\n", output))
        .map_err(|e| format!("Failed to write config: {}", e))?;

    Ok(())
}

/// Check: report current stage and whether advancement criteria are met.
fn rollout_check(planning_dir: &Path) -> Result<(String, i32), String> {
    let stages = load_stages(planning_dir);
    let current = get_current_stage(planning_dir);
    let completed = count_completed_phases(planning_dir);

    let current_idx = current.as_ref()
        .and_then(|c| stages.iter().position(|(name, _)| name == c))
        .unwrap_or(0);

    let can_advance = current_idx + 1 < stages.len();
    let next_stage = if can_advance {
        Some(&stages[current_idx + 1])
    } else {
        None
    };

    let result = json!({
        "current_stage": current.unwrap_or_else(|| stages[0].0.clone()),
        "current_index": current_idx,
        "total_stages": stages.len(),
        "completed_phases": completed,
        "can_advance": can_advance,
        "next_stage": next_stage.map(|(n, _)| n.as_str()),
    });

    Ok((serde_json::to_string_pretty(&result).unwrap_or_default(), 0))
}

/// Advance to the next rollout stage.
fn rollout_advance(planning_dir: &Path) -> Result<(String, i32), String> {
    let stages = load_stages(planning_dir);
    let current = get_current_stage(planning_dir);

    let current_idx = current.as_ref()
        .and_then(|c| stages.iter().position(|(name, _)| name == c))
        .unwrap_or(0);

    if current_idx + 1 >= stages.len() {
        return Ok(("Already at final rollout stage".to_string(), 0));
    }

    let next = &stages[current_idx + 1];
    set_rollout_stage(planning_dir, &next.0)?;

    // Log the advancement event
    let events_dir = planning_dir.join(".events");
    let _ = fs::create_dir_all(&events_dir);
    let events_file = events_dir.join("event-log.jsonl");
    let event = json!({
        "event": "rollout_advance",
        "data": {
            "from": current.unwrap_or_else(|| stages[0].0.clone()),
            "to": next.0,
        }
    });
    if let Ok(line) = serde_json::to_string(&event) {
        let _ = fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(&events_file)
            .and_then(|mut f| {
                use std::io::Write;
                writeln!(f, "{}", line)
            });
    }

    let result = json!({
        "advanced": true,
        "from_stage": stages[current_idx].0,
        "to_stage": next.0,
        "description": next.1,
    });

    Ok((serde_json::to_string_pretty(&result).unwrap_or_default(), 0))
}

/// Status: show all stages with current highlighted.
fn rollout_status(planning_dir: &Path) -> Result<(String, i32), String> {
    let stages = load_stages(planning_dir);
    let current = get_current_stage(planning_dir);
    let completed = count_completed_phases(planning_dir);

    let current_name = current.unwrap_or_else(|| stages[0].0.clone());

    let mut output = String::new();
    output.push_str("Rollout Stages:\n");

    for (i, (name, desc)) in stages.iter().enumerate() {
        let marker = if *name == current_name { ">>>" } else { "   " };
        output.push_str(&format!("{} {}. {} — {}\n", marker, i + 1, name, desc));
    }

    output.push_str(&format!("\nCompleted phases: {}\n", completed));
    output.push_str(&format!("Current stage: {}\n", current_name));

    Ok((output, 0))
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn setup_env() -> TempDir {
        let dir = TempDir::new().unwrap();
        let planning = dir.path().join(".yolo-planning");
        fs::create_dir_all(&planning).unwrap();
        fs::write(planning.join("config.json"), r#"{"v3_event_log": true}"#).unwrap();
        dir
    }

    fn setup_env_with_stages() -> TempDir {
        let dir = setup_env();
        let planning = dir.path().join(".yolo-planning");
        let stages = json!({
            "stages": [
                {"name": "alpha", "description": "Alpha testing"},
                {"name": "beta", "description": "Beta testing"},
                {"name": "ga", "description": "General availability"},
            ]
        });
        fs::write(planning.join("rollout-stages.json"), stages.to_string()).unwrap();
        dir
    }

    #[test]
    fn test_execute_insufficient_args() {
        let dir = TempDir::new().unwrap();
        let args: Vec<String> = vec!["yolo".into(), "rollout".into()];
        let result = execute(&args, dir.path());
        assert!(result.is_err());
    }

    #[test]
    fn test_execute_unknown_action() {
        let dir = TempDir::new().unwrap();
        let args: Vec<String> = vec!["yolo".into(), "rollout".into(), "invalid".into()];
        let result = execute(&args, dir.path());
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Unknown rollout action"));
    }

    #[test]
    fn test_load_default_stages() {
        let dir = TempDir::new().unwrap();
        let planning = dir.path().join("planning");
        fs::create_dir(&planning).unwrap();
        let stages = load_stages(&planning);
        assert_eq!(stages.len(), 3);
        assert_eq!(stages[0].0, "canary");
        assert_eq!(stages[1].0, "partial");
        assert_eq!(stages[2].0, "full");
    }

    #[test]
    fn test_load_custom_stages() {
        let dir = setup_env_with_stages();
        let planning = dir.path().join(".yolo-planning");
        let stages = load_stages(&planning);
        assert_eq!(stages.len(), 3);
        assert_eq!(stages[0].0, "alpha");
        assert_eq!(stages[1].0, "beta");
        assert_eq!(stages[2].0, "ga");
    }

    #[test]
    fn test_count_completed_phases_empty() {
        let dir = TempDir::new().unwrap();
        assert_eq!(count_completed_phases(dir.path()), 0);
    }

    #[test]
    fn test_count_completed_phases() {
        let dir = setup_env();
        let planning = dir.path().join(".yolo-planning");
        let events_dir = planning.join(".events");
        fs::create_dir_all(&events_dir).unwrap();

        let events = format!(
            "{}\n{}\n{}\n",
            json!({"event": "phase_end", "phase": 1}),
            json!({"event": "phase_end", "phase": 2}),
            json!({"event": "phase_start", "phase": 3}),
        );
        fs::write(events_dir.join("event-log.jsonl"), events).unwrap();

        assert_eq!(count_completed_phases(&planning), 2);
    }

    #[test]
    fn test_rollout_check_default() {
        let dir = setup_env();
        let planning = dir.path().join(".yolo-planning");
        let (output, code) = rollout_check(&planning).unwrap();
        assert_eq!(code, 0);
        let result: Value = serde_json::from_str(&output).unwrap();
        assert_eq!(result["current_stage"], "canary");
        assert_eq!(result["can_advance"], true);
        assert_eq!(result["next_stage"], "partial");
    }

    #[test]
    fn test_rollout_advance() {
        let dir = setup_env();
        let planning = dir.path().join(".yolo-planning");

        let (output, code) = rollout_advance(&planning).unwrap();
        assert_eq!(code, 0);
        let result: Value = serde_json::from_str(&output).unwrap();
        assert_eq!(result["advanced"], true);
        assert_eq!(result["to_stage"], "partial");

        // Verify config was updated
        let config: Value = serde_json::from_str(
            &fs::read_to_string(planning.join("config.json")).unwrap()
        ).unwrap();
        assert_eq!(config["rollout_stage"], "partial");
        assert_eq!(config["max_agents"], 4);
        assert_eq!(config["rollout_scope"], "expanded");
    }

    #[test]
    fn test_rollout_advance_twice() {
        let dir = setup_env();
        let planning = dir.path().join(".yolo-planning");

        // Advance to partial
        rollout_advance(&planning).unwrap();
        // Advance to full
        let (output, _) = rollout_advance(&planning).unwrap();
        let result: Value = serde_json::from_str(&output).unwrap();
        assert_eq!(result["to_stage"], "full");

        // Verify config
        let config: Value = serde_json::from_str(
            &fs::read_to_string(planning.join("config.json")).unwrap()
        ).unwrap();
        assert_eq!(config["rollout_stage"], "full");
        assert_eq!(config["max_agents"], 8);
    }

    #[test]
    fn test_rollout_advance_at_final_stage() {
        let dir = setup_env();
        let planning = dir.path().join(".yolo-planning");

        // Set to final stage
        set_rollout_stage(&planning, "full").unwrap();

        let (output, code) = rollout_advance(&planning).unwrap();
        assert_eq!(code, 0);
        assert!(output.contains("Already at final"));
    }

    #[test]
    fn test_rollout_status() {
        let dir = setup_env();
        let planning = dir.path().join(".yolo-planning");
        set_rollout_stage(&planning, "partial").unwrap();

        let (output, code) = rollout_status(&planning).unwrap();
        assert_eq!(code, 0);
        assert!(output.contains(">>> 2. partial"));
        assert!(output.contains("Current stage: partial"));
    }

    #[test]
    fn test_set_rollout_stage_creates_config() {
        let dir = TempDir::new().unwrap();
        let planning = dir.path().join("planning");
        fs::create_dir(&planning).unwrap();

        set_rollout_stage(&planning, "canary").unwrap();

        let config: Value = serde_json::from_str(
            &fs::read_to_string(planning.join("config.json")).unwrap()
        ).unwrap();
        assert_eq!(config["rollout_stage"], "canary");
        assert_eq!(config["max_agents"], 1);
    }

    #[test]
    fn test_execute_check() {
        let dir = setup_env();
        let args: Vec<String> = vec!["yolo".into(), "rollout".into(), "check".into()];
        let (output, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
        assert!(output.contains("current_stage"));
    }

    #[test]
    fn test_execute_status() {
        let dir = setup_env();
        let args: Vec<String> = vec!["yolo".into(), "rollout".into(), "status".into()];
        let (output, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
        assert!(output.contains("Rollout Stages:"));
    }

    #[test]
    fn test_execute_advance() {
        let dir = setup_env();
        let args: Vec<String> = vec!["yolo".into(), "rollout".into(), "advance".into()];
        let (output, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
        assert!(output.contains("advanced"));
    }
}
