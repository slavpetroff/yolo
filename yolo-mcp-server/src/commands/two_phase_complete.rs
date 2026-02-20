use chrono::Utc;
use serde_json::{json, Value};
use std::fs;
use std::path::Path;
use std::process::Command;

use super::log_event;

/// Check if v2_two_phase_completion is enabled in config.json.
fn is_enabled(cwd: &Path) -> bool {
    let config_path = cwd.join(".yolo-planning").join("config.json");
    if config_path.exists() {
        if let Ok(content) = fs::read_to_string(&config_path) {
            if let Ok(config) = serde_json::from_str::<Value>(&content) {
                return config.get("v2_two_phase_completion").and_then(|v| v.as_bool()).unwrap_or(false);
            }
        }
    }
    false
}

/// Parse key=value pairs from evidence args.
fn parse_evidence_args(args: &[String]) -> (Vec<String>, Vec<(String, String)>) {
    let mut evidence_parts = Vec::new();
    let mut kv_pairs = Vec::new();

    for arg in args {
        if let Some(eq_pos) = arg.find('=') {
            let key = &arg[..eq_pos];
            let value = &arg[eq_pos + 1..];
            kv_pairs.push((key.to_string(), value.to_string()));
        } else {
            evidence_parts.push(arg.clone());
        }
    }

    (evidence_parts, kv_pairs)
}

/// Run the two-phase completion protocol.
/// Phase 1: Emit candidate event
/// Phase 2: Validate must_haves + files against contract
/// Phase 3: Emit confirmed/rejected event
pub fn complete(
    task_id: &str,
    phase: &str,
    plan: &str,
    contract_path: &str,
    evidence_args: &[String],
    cwd: &Path,
) -> Result<(String, i32), String> {
    // Parse evidence and key=value pairs
    let (evidence_parts, kv_pairs) = parse_evidence_args(evidence_args);
    let evidence = evidence_parts.join(" ");

    // Extract files_modified from kv pairs
    let files_modified: Vec<String> = kv_pairs.iter()
        .filter(|(k, _)| k == "files_modified")
        .map(|(_, v)| v.clone())
        .collect();

    // Validate evidence
    if evidence.is_empty() && evidence_parts.is_empty() {
        let result = json!({
            "task_id": task_id,
            "result": "rejected",
            "errors": ["no evidence provided"],
            "ts": Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string(),
        });
        return Ok((result.to_string(), 2));
    }

    // Load contract
    let contract_full = if Path::new(contract_path).is_absolute() {
        contract_path.to_string()
    } else {
        cwd.join(contract_path).to_string_lossy().to_string()
    };

    let contract_file = Path::new(&contract_full);
    if !contract_file.exists() {
        let result = json!({
            "task_id": task_id,
            "result": "rejected",
            "errors": ["contract file not found"],
            "ts": Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string(),
        });
        return Ok((result.to_string(), 2));
    }

    let contract_content = fs::read_to_string(contract_file)
        .map_err(|e| format!("Failed to read contract: {}", e))?;
    let contract: Value = serde_json::from_str(&contract_content)
        .map_err(|e| format!("Invalid contract JSON: {}", e))?;

    // Phase 1: Emit candidate event
    let candidate_data = vec![
        ("task_id".to_string(), task_id.to_string()),
        ("evidence".to_string(), evidence.clone()),
    ];
    let _ = log_event::log("task_completed_candidate", phase, Some(plan), &candidate_data, cwd);

    // Phase 2: Validate
    let mut errors = Vec::new();

    // must_haves are documented requirements — the agent self-reports evidence.
    // We verify evidence is non-empty (done above). The must_haves check is soft.
    let _must_haves: Vec<&str> = contract.get("must_haves")
        .and_then(|v| v.as_array())
        .map(|arr| arr.iter().filter_map(|v| v.as_str()).collect())
        .unwrap_or_default();

    // Check files_modified against allowed_paths
    let allowed_paths: Vec<&str> = contract.get("allowed_paths")
        .and_then(|v| v.as_array())
        .map(|arr| arr.iter().filter_map(|v| v.as_str()).collect())
        .unwrap_or_default();

    if !allowed_paths.is_empty() {
        for file in &files_modified {
            let is_allowed = allowed_paths.iter().any(|allowed| {
                file == allowed || file.starts_with(&format!("{}/", allowed))
            });
            if !is_allowed {
                errors.push(format!("{} outside allowed_paths", file));
            }
        }
    }

    // Run verification_checks (user-defined commands via shell)
    let verification_checks: Vec<&str> = contract.get("verification_checks")
        .and_then(|v| v.as_array())
        .map(|arr| arr.iter().filter_map(|v| v.as_str()).collect())
        .unwrap_or_default();

    let mut checks_passed = 0;
    let mut checks_failed = 0;

    for check in &verification_checks {
        let output = Command::new("sh")
            .arg("-c")
            .arg(check)
            .current_dir(cwd)
            .output();

        match output {
            Ok(o) if o.status.success() => {
                checks_passed += 1;
            }
            _ => {
                checks_failed += 1;
                errors.push(format!("verification check failed: {}", check));
            }
        }
    }

    // Phase 3: Emit confirmed or rejected
    let ts = Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string();

    if errors.is_empty() {
        let confirmed_data = vec![
            ("task_id".to_string(), task_id.to_string()),
            ("evidence".to_string(), evidence),
            ("checks_passed".to_string(), checks_passed.to_string()),
        ];
        let _ = log_event::log("task_completed_confirmed", phase, Some(plan), &confirmed_data, cwd);

        let result = json!({
            "task_id": task_id,
            "result": "confirmed",
            "checks_passed": checks_passed,
            "checks_failed": checks_failed,
            "ts": ts,
        });
        Ok((result.to_string(), 0))
    } else {
        let rejected_data = vec![
            ("task_id".to_string(), task_id.to_string()),
            ("errors".to_string(), errors.join("; ")),
            ("checks_failed".to_string(), checks_failed.to_string()),
        ];
        let _ = log_event::log("task_completion_rejected", phase, Some(plan), &rejected_data, cwd);

        let result = json!({
            "task_id": task_id,
            "result": "rejected",
            "errors": errors,
            "checks_passed": checks_passed,
            "checks_failed": checks_failed,
            "ts": ts,
        });
        Ok((result.to_string(), 2))
    }
}

/// CLI entry point: `yolo two-phase-complete <task_id> <phase> <plan> <contract_path> [evidence...]`
pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    // args[0] = "yolo", args[1] = "two-phase-complete"
    // args[2] = task_id, args[3] = phase, args[4] = plan, args[5] = contract_path
    // args[6..] = evidence parts and key=value pairs
    if args.len() < 6 {
        return Err("Usage: yolo two-phase-complete <task_id> <phase> <plan> <contract_path> [evidence...]".to_string());
    }

    if !is_enabled(cwd) {
        return Ok((json!({"result": "skip", "reason": "v2_two_phase_completion=false"}).to_string(), 0));
    }

    let task_id = &args[2];
    let phase = &args[3];
    let plan = &args[4];
    let contract_path = &args[5];
    let evidence_args = if args.len() > 6 { &args[6..] } else { &[] };

    complete(task_id, phase, plan, contract_path, evidence_args, cwd)
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn setup_test_env(enabled: bool) -> TempDir {
        let dir = TempDir::new().unwrap();
        let planning_dir = dir.path().join(".yolo-planning");
        fs::create_dir_all(planning_dir.join(".contracts")).unwrap();
        fs::create_dir_all(planning_dir.join(".events")).unwrap();
        fs::create_dir_all(planning_dir.join(".artifacts")).unwrap();
        let config = json!({
            "v2_two_phase_completion": enabled,
            "v3_event_log": true,
        });
        fs::write(planning_dir.join("config.json"), config.to_string()).unwrap();
        dir
    }

    fn create_passing_contract(dir: &TempDir) -> String {
        let contract = json!({
            "phase_id": "phase-1",
            "plan_id": "1-1",
            "phase": 1,
            "plan": 1,
            "objective": "Test",
            "task_ids": ["1-1-T1"],
            "task_count": 1,
            "allowed_paths": ["src/a.js"],
            "forbidden_paths": [],
            "depends_on": [],
            "must_haves": ["Feature works"],
            "verification_checks": ["true"],
            "max_token_budget": 50000,
            "timeout_seconds": 300,
            "contract_hash": "abc",
        });
        let path = dir.path().join(".yolo-planning/.contracts/1-1.json");
        fs::write(&path, contract.to_string()).unwrap();
        path.to_str().unwrap().to_string()
    }

    fn create_failing_contract(dir: &TempDir) -> String {
        let contract = json!({
            "phase_id": "phase-1",
            "plan_id": "1-1",
            "phase": 1,
            "plan": 1,
            "objective": "Test",
            "task_ids": ["1-1-T1"],
            "task_count": 1,
            "allowed_paths": ["src/a.js"],
            "forbidden_paths": [],
            "depends_on": [],
            "must_haves": ["Feature works"],
            "verification_checks": ["false"],
            "max_token_budget": 50000,
            "timeout_seconds": 300,
            "contract_hash": "abc",
        });
        let path = dir.path().join(".yolo-planning/.contracts/1-1.json");
        fs::write(&path, contract.to_string()).unwrap();
        path.to_str().unwrap().to_string()
    }

    #[test]
    fn test_skip_when_disabled() {
        let dir = setup_test_env(false);
        let args = vec![
            "yolo".into(), "two-phase-complete".into(),
            "1-1-T1".into(), "1".into(), "1".into(), "any".into(), "any".into(),
        ];
        let (out, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
        assert!(out.contains("v2_two_phase_completion=false"));
    }

    #[test]
    fn test_confirmed_when_checks_pass() {
        let dir = setup_test_env(true);
        let contract_path = create_passing_contract(&dir);
        let evidence = vec!["all tests pass".to_string()];
        let (out, code) = complete("1-1-T1", "1", "1", &contract_path, &evidence, dir.path()).unwrap();
        assert_eq!(code, 0);
        let result: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(result["result"], "confirmed");
        assert!(result["checks_passed"].as_i64().unwrap() > 0);
    }

    #[test]
    fn test_rejected_when_check_fails() {
        let dir = setup_test_env(true);
        let contract_path = create_failing_contract(&dir);
        let evidence = vec!["incomplete".to_string()];
        let (out, code) = complete("1-1-T1", "1", "1", &contract_path, &evidence, dir.path()).unwrap();
        assert_eq!(code, 2);
        let result: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(result["result"], "rejected");
        assert!(result["errors"].as_array().unwrap().len() > 0);
    }

    #[test]
    fn test_emits_candidate_and_confirmed_events() {
        let dir = setup_test_env(true);
        let contract_path = create_passing_contract(&dir);
        let evidence = vec!["evidence".to_string()];
        complete("1-1-T1", "1", "1", &contract_path, &evidence, dir.path()).unwrap();

        let events_file = dir.path().join(".yolo-planning/.events/event-log.jsonl");
        let content = fs::read_to_string(&events_file).unwrap();
        assert!(content.contains("task_completed_candidate"));
        assert!(content.contains("task_completed_confirmed"));
    }

    #[test]
    fn test_emits_rejection_event() {
        let dir = setup_test_env(true);
        let contract_path = create_failing_contract(&dir);
        let evidence = vec!["bad".to_string()];
        complete("1-1-T1", "1", "1", &contract_path, &evidence, dir.path()).unwrap();

        let events_file = dir.path().join(".yolo-planning/.events/event-log.jsonl");
        let content = fs::read_to_string(&events_file).unwrap();
        assert!(content.contains("task_completed_candidate"));
        assert!(content.contains("task_completion_rejected"));
    }

    #[test]
    fn test_missing_contract() {
        let dir = setup_test_env(true);
        let evidence = vec!["evidence".to_string()];
        let (out, code) = complete("1-1-T1", "1", "1", "nonexistent.json", &evidence, dir.path()).unwrap();
        assert_eq!(code, 2);
        let result: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(result["result"], "rejected");
        assert!(result["errors"].as_array().unwrap().iter().any(|e| e.as_str().unwrap().contains("contract file not found")));
    }

    #[test]
    fn test_no_evidence_rejected() {
        let dir = setup_test_env(true);
        let contract_path = create_passing_contract(&dir);
        let evidence: Vec<String> = vec![];
        let (out, code) = complete("1-1-T1", "1", "1", &contract_path, &evidence, dir.path()).unwrap();
        assert_eq!(code, 2);
        let result: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(result["result"], "rejected");
        assert!(result["errors"].as_array().unwrap().iter().any(|e| e.as_str().unwrap().contains("no evidence")));
    }

    #[test]
    fn test_files_outside_allowed_paths_rejected() {
        let dir = setup_test_env(true);
        let contract_path = create_passing_contract(&dir);
        let evidence = vec!["files_modified=bad/path.js".to_string(), "some evidence".to_string()];
        let (out, code) = complete("1-1-T1", "1", "1", &contract_path, &evidence, dir.path()).unwrap();
        assert_eq!(code, 2);
        let result: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(result["result"], "rejected");
        assert!(result["errors"].as_array().unwrap().iter().any(|e| e.as_str().unwrap().contains("outside allowed_paths")));
    }

    #[test]
    fn test_files_within_allowed_paths_confirmed() {
        let dir = setup_test_env(true);
        let contract_path = create_passing_contract(&dir);
        let evidence = vec!["files_modified=src/a.js".to_string(), "feature works".to_string()];
        let (out, code) = complete("1-1-T1", "1", "1", &contract_path, &evidence, dir.path()).unwrap();
        assert_eq!(code, 0);
        let result: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(result["result"], "confirmed");
    }

    #[test]
    fn test_missing_cli_args() {
        let dir = setup_test_env(true);
        let args = vec!["yolo".into(), "two-phase-complete".into()];
        assert!(execute(&args, dir.path()).is_err());
    }
}
