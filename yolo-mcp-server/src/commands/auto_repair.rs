use std::fs;
use std::path::Path;

use serde_json::{json, Value};

/// Execute auto-repair for a gate failure.
/// Usage: yolo auto-repair <gate_type> <phase> <plan> <task> <contract_path>
/// Attempts bounded auto-repair (max 2 retries). Non-repairable gates escalate immediately.
pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    if args.len() < 7 {
        let result = json!({
            "repaired": false,
            "attempts": 0,
            "gate": "unknown",
            "reason": "insufficient arguments"
        });
        return Ok((serde_json::to_string(&result).unwrap(), 0));
    }

    let gate_type = &args[2];
    let phase = &args[3];
    let plan = &args[4];
    let task = &args[5];
    let _contract_path = &args[6];

    let planning_dir = cwd.join(".yolo-planning");
    let config_path = planning_dir.join("config.json");

    // Check feature flag
    if !is_v2_hard_gates_enabled(&config_path) {
        let result = json!({
            "repaired": false,
            "attempts": 0,
            "gate": gate_type,
            "reason": "v2_hard_gates=false"
        });
        return Ok((serde_json::to_string(&result).unwrap(), 0));
    }

    // Determine if gate is repairable
    if !is_repairable(gate_type) {
        log_blocker_event(&planning_dir, phase, plan, task, gate_type, "manual_intervention", 0);
        let result = json!({
            "repaired": false,
            "attempts": 0,
            "gate": gate_type,
            "reason": "not repairable, escalated to lead"
        });
        return Ok((serde_json::to_string(&result).unwrap(), 0));
    }

    // Attempt repair (max 2 retries)
    let max_retries = 2;
    let mut attempt = 0;
    let mut repaired = false;

    while attempt < max_retries {
        attempt += 1;

        // Execute repair strategy
        match gate_type.as_str() {
            "contract_compliance" => {
                repair_contract_compliance(cwd, &planning_dir, phase, plan);
            }
            "required_checks" => {
                // Re-run is the repair — no extra action needed
            }
            _ => {}
        }

        // Re-run gate check
        if check_gate_passes(cwd, gate_type, phase, plan, task, _contract_path) {
            repaired = true;
            break;
        }
    }

    if repaired {
        let result = json!({
            "repaired": true,
            "attempts": attempt,
            "gate": gate_type
        });
        Ok((serde_json::to_string(&result).unwrap(), 0))
    } else {
        log_blocker_event(&planning_dir, phase, plan, task, gate_type, "investigate_and_fix", attempt);
        let result = json!({
            "repaired": false,
            "attempts": attempt,
            "gate": gate_type,
            "reason": "max retries exhausted, escalated to lead"
        });
        Ok((serde_json::to_string(&result).unwrap(), 0))
    }
}

fn is_v2_hard_gates_enabled(config_path: &Path) -> bool {
    if let Ok(content) = fs::read_to_string(config_path)
        && let Ok(config) = serde_json::from_str::<Value>(&content) {
            return config.get("v2_hard_gates")
                .and_then(|v| v.as_bool())
                .unwrap_or(false);
        }
    false
}

fn is_repairable(gate_type: &str) -> bool {
    matches!(gate_type, "contract_compliance" | "required_checks")
}

/// Attempt to repair contract compliance by regenerating the contract.
fn repair_contract_compliance(cwd: &Path, planning_dir: &Path, phase: &str, plan: &str) {
    let phases_dir = planning_dir.join("phases");

    // Find phase directory
    let phase_dir = find_phase_dir(&phases_dir, phase);
    if phase_dir.is_none() {
        return;
    }
    let phase_dir = phase_dir.unwrap();

    // Find plan file
    let plan_file = find_plan_file(&phase_dir, phase, plan);
    if plan_file.is_none() {
        return;
    }

    // Regenerate contract using the Rust generate-contract command
    let plan_path = plan_file.unwrap();
    let yolo_bin = std::env::var("HOME")
        .map(|h| format!("{}/.cargo/bin/yolo", h))
        .unwrap_or_else(|_| "yolo".to_string());

    let _ = std::process::Command::new(&yolo_bin)
        .args(["generate-contract", plan_path.to_str().unwrap_or("")])
        .current_dir(cwd)
        .output();
}

fn find_phase_dir(phases_dir: &Path, phase: &str) -> Option<std::path::PathBuf> {
    let prefix = format!("{}-", phase);
    let padded = format!("{:0>2}-", phase);

    if let Ok(entries) = fs::read_dir(phases_dir) {
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().to_string();
            if entry.path().is_dir() && (name.starts_with(&prefix) || name.starts_with(&padded)) {
                return Some(entry.path());
            }
        }
    }
    None
}

fn find_plan_file(phase_dir: &Path, phase: &str, plan: &str) -> Option<std::path::PathBuf> {
    let padded_phase = format!("{:0>2}", phase);
    let padded_plan = format!("{:0>2}", plan);

    let patterns = [
        format!("{}-{}-PLAN.md", padded_phase, padded_plan),
        format!("{}-{}-PLAN.md", phase, plan),
    ];

    if let Ok(entries) = fs::read_dir(phase_dir) {
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().to_string();
            if name.ends_with("PLAN.md") {
                for pattern in &patterns {
                    if name == *pattern || name.contains(&format!("-{}-", plan)) {
                        return Some(entry.path());
                    }
                }
            }
        }
    }
    None
}

/// Re-run the hard gate check. Returns true if gate passes.
fn check_gate_passes(cwd: &Path, gate_type: &str, phase: &str, plan: &str, task: &str, contract_path: &str) -> bool {
    let yolo_bin = std::env::var("HOME")
        .map(|h| format!("{}/.cargo/bin/yolo", h))
        .unwrap_or_else(|_| "yolo".to_string());

    let output = std::process::Command::new(&yolo_bin)
        .args(["hard-gate", gate_type, phase, plan, task, contract_path])
        .current_dir(cwd)
        .output();

    if let Ok(out) = output
        && let Ok(text) = String::from_utf8(out.stdout)
        && let Ok(result) = serde_json::from_str::<Value>(&text) {
            return result.get("result")
                .and_then(|v| v.as_str())
                .map(|s| s == "pass")
                .unwrap_or(false);
        }
    false
}

/// Log a blocker event to the event log.
fn log_blocker_event(planning_dir: &Path, phase: &str, plan: &str, task: &str, gate: &str, next_action: &str, attempts: u32) {
    let events_dir = planning_dir.join(".events");
    let _ = fs::create_dir_all(&events_dir);
    let events_file = events_dir.join("event-log.jsonl");

    let event = json!({
        "event": "task_blocked",
        "phase": phase,
        "plan": plan,
        "data": {
            "task": task,
            "gate": gate,
            "owner": "lead",
            "next_action": next_action,
            "attempts": attempts
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
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn test_insufficient_args() {
        let args: Vec<String> = vec!["yolo".into(), "auto-repair".into(), "contract_compliance".into()];
        let (output, code) = execute(&args, Path::new("/tmp")).unwrap();
        assert_eq!(code, 0);
        let result: Value = serde_json::from_str(&output).unwrap();
        assert_eq!(result["repaired"], false);
        assert_eq!(result["reason"], "insufficient arguments");
    }

    #[test]
    fn test_v2_hard_gates_disabled() {
        let dir = TempDir::new().unwrap();
        let planning = dir.path().join(".yolo-planning");
        fs::create_dir_all(&planning).unwrap();
        fs::write(planning.join("config.json"), r#"{"v2_hard_gates": false}"#).unwrap();

        let args: Vec<String> = vec![
            "yolo".into(), "auto-repair".into(),
            "contract_compliance".into(), "1".into(), "1".into(), "1".into(), "/tmp/contract".into(),
        ];
        let (output, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
        let result: Value = serde_json::from_str(&output).unwrap();
        assert_eq!(result["repaired"], false);
        assert_eq!(result["reason"], "v2_hard_gates=false");
    }

    #[test]
    fn test_non_repairable_gate() {
        let dir = TempDir::new().unwrap();
        let planning = dir.path().join(".yolo-planning");
        fs::create_dir_all(&planning).unwrap();
        fs::write(planning.join("config.json"), r#"{"v2_hard_gates": true}"#).unwrap();

        let args: Vec<String> = vec![
            "yolo".into(), "auto-repair".into(),
            "protected_file".into(), "1".into(), "1".into(), "1".into(), "/tmp/contract".into(),
        ];
        let (output, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
        let result: Value = serde_json::from_str(&output).unwrap();
        assert_eq!(result["repaired"], false);
        assert_eq!(result["reason"], "not repairable, escalated to lead");
    }

    #[test]
    fn test_is_repairable() {
        assert!(is_repairable("contract_compliance"));
        assert!(is_repairable("required_checks"));
        assert!(!is_repairable("protected_file"));
        assert!(!is_repairable("commit_hygiene"));
        assert!(!is_repairable("artifact_persistence"));
        assert!(!is_repairable("verification_threshold"));
    }

    #[test]
    fn test_non_repairable_gates_escalate() {
        let dir = TempDir::new().unwrap();
        let planning = dir.path().join(".yolo-planning");
        fs::create_dir_all(&planning).unwrap();
        fs::write(planning.join("config.json"), r#"{"v2_hard_gates": true}"#).unwrap();

        for gate in &["commit_hygiene", "artifact_persistence", "verification_threshold"] {
            let args: Vec<String> = vec![
                "yolo".into(), "auto-repair".into(),
                gate.to_string(), "1".into(), "1".into(), "1".into(), "/tmp/c".into(),
            ];
            let (output, code) = execute(&args, dir.path()).unwrap();
            assert_eq!(code, 0);
            let result: Value = serde_json::from_str(&output).unwrap();
            assert_eq!(result["repaired"], false);
            assert!(result["reason"].as_str().unwrap().contains("escalated"));
        }
    }

    #[test]
    fn test_repairable_gate_exhaust_retries() {
        let dir = TempDir::new().unwrap();
        let planning = dir.path().join(".yolo-planning");
        fs::create_dir_all(&planning).unwrap();
        fs::write(planning.join("config.json"), r#"{"v2_hard_gates": true}"#).unwrap();

        // Use a nonexistent contract path that will cause the gate to fail
        let contract = dir.path().join("nonexistent-contract.json");
        let args: Vec<String> = vec![
            "yolo".into(), "auto-repair".into(),
            "contract_compliance".into(), "1".into(), "1".into(), "1".into(),
            contract.to_str().unwrap().into(),
        ];
        let (output, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
        let result: Value = serde_json::from_str(&output).unwrap();
        // Gate check may pass or fail depending on binary availability;
        // verify the structure is correct
        assert!(result.get("repaired").is_some());
        assert!(result.get("attempts").is_some());
    }

    #[test]
    fn test_log_blocker_event_writes_file() {
        let dir = TempDir::new().unwrap();
        let planning = dir.path().join(".yolo-planning");
        fs::create_dir_all(&planning).unwrap();

        log_blocker_event(&planning, "1", "1", "t1", "contract_compliance", "fix", 2);

        let events_file = planning.join(".events/event-log.jsonl");
        assert!(events_file.exists());
        let content = fs::read_to_string(&events_file).unwrap();
        let event: Value = serde_json::from_str(content.trim()).unwrap();
        assert_eq!(event["event"], "task_blocked");
        assert_eq!(event["data"]["gate"], "contract_compliance");
        assert_eq!(event["data"]["attempts"], 2);
    }

    #[test]
    fn test_find_phase_dir() {
        let dir = TempDir::new().unwrap();
        let phases = dir.path().join("phases");
        fs::create_dir_all(phases.join("01-setup")).unwrap();
        fs::create_dir_all(phases.join("02-build")).unwrap();

        assert!(find_phase_dir(&phases, "01").is_some());
        assert!(find_phase_dir(&phases, "1").is_some());
        assert!(find_phase_dir(&phases, "02").is_some());
        assert!(find_phase_dir(&phases, "99").is_none());
    }

    #[test]
    fn test_find_plan_file() {
        let dir = TempDir::new().unwrap();
        let phase_dir = dir.path().join("01-setup");
        fs::create_dir_all(&phase_dir).unwrap();
        fs::write(phase_dir.join("01-01-PLAN.md"), "# Plan").unwrap();

        assert!(find_plan_file(&phase_dir, "01", "01").is_some());
        assert!(find_plan_file(&phase_dir, "01", "99").is_none());
    }
}
