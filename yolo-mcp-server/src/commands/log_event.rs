use chrono::Utc;
use serde_json::{json, Value};
use std::env;
use std::fs;
use std::path::Path;
use std::time::Instant;
use uuid::Uuid;

pub struct LogResult {
    pub written: bool,
    pub event_id: Option<String>,
    pub reason: Option<String>,
}

/// Allowed event types for v2_typed_protocol validation.
const ALLOWED_EVENT_TYPES: &[&str] = &[
    // V1
    "phase_start", "phase_end", "plan_start", "plan_end",
    "agent_spawn", "agent_shutdown", "error", "checkpoint",
    // V2
    "phase_planned", "task_created", "task_claimed", "task_started",
    "artifact_written", "gate_passed", "gate_failed",
    "task_completed_candidate", "task_completed_confirmed",
    "task_blocked", "task_reassigned", "shutdown_sent", "shutdown_received",
    // Internal / metric types
    "token_overage", "token_cap_escalated", "file_conflict", "smart_route",
    "contract_revision", "cache_hit", "task_completion_rejected",
    "snapshot_restored", "state_recovered", "message_rejected",
    // Token tracking
    "agent_token_usage",
    // Feedback loop events
    "review_loop_start", "review_loop_cycle", "review_loop_end",
    "qa_loop_start", "qa_loop_cycle", "qa_loop_end",
];

/// Parse key=value pairs from a slice of args, also extracting the first non-kv arg as plan.
fn parse_args(args: &[String]) -> (Option<String>, Vec<(String, String)>) {
    let mut plan: Option<String> = None;
    let mut data_pairs: Vec<(String, String)> = Vec::new();

    for arg in args {
        if let Some(eq_pos) = arg.find('=') {
            let key = arg[..eq_pos].to_string();
            let value = arg[eq_pos + 1..].to_string();
            data_pairs.push((key, value));
        } else if plan.is_none() {
            plan = Some(arg.clone());
        }
    }

    (plan, data_pairs)
}

/// Core logging function callable from other Rust code.
/// Appends a JSON line to `.yolo-planning/.events/event-log.jsonl`.
/// Never fails fatally — returns Ok with LogResult on any path.
pub fn log(
    event_type: &str,
    phase: &str,
    plan: Option<&str>,
    data_pairs: &[(String, String)],
    cwd: &Path,
) -> Result<LogResult, String> {
    let planning_dir = cwd.join(".yolo-planning");
    let config_path = planning_dir.join("config.json");

    // Check v3_event_log flag
    if config_path.exists() {
        if let Ok(config_str) = fs::read_to_string(&config_path) {
            if let Ok(config) = serde_json::from_str::<Value>(&config_str) {
                let enabled = config.get("v3_event_log").and_then(|v| v.as_bool()).unwrap_or(false);
                if !enabled {
                    return Ok(LogResult {
                        written: false,
                        event_id: None,
                        reason: Some("v3_event_log disabled".to_string()),
                    });
                }
            }
        }
    }

    // Validate event type when v2_typed_protocol=true
    if config_path.exists() {
        if let Ok(config_str) = fs::read_to_string(&config_path) {
            if let Ok(config) = serde_json::from_str::<Value>(&config_str) {
                let typed = config.get("v2_typed_protocol").and_then(|v| v.as_bool()).unwrap_or(false);
                if typed && !ALLOWED_EVENT_TYPES.contains(&event_type) {
                    eprintln!(
                        "[log-event] WARNING: unknown event type '{}' rejected by v2_typed_protocol",
                        event_type
                    );
                    return Ok(LogResult {
                        written: false,
                        event_id: None,
                        reason: Some("unknown event type rejected".to_string()),
                    });
                }
            }
        }
    }

    // Resolve correlation_id: env var → execution-state.json → ""
    let mut correlation_id = env::var("YOLO_CORRELATION_ID").unwrap_or_default();

    if correlation_id.is_empty() {
        let exec_state_path = planning_dir.join(".execution-state.json");
        if exec_state_path.exists() {
            if let Ok(state_str) = fs::read_to_string(&exec_state_path) {
                if let Ok(state) = serde_json::from_str::<Value>(&state_str) {
                    correlation_id = state
                        .get("correlation_id")
                        .and_then(|v| v.as_str())
                        .unwrap_or("")
                        .to_string();
                }
            }
        }
    }

    let ts = Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string();
    let event_id = Uuid::new_v4().to_string();

    // Build JSON object
    let mut obj = json!({
        "ts": ts,
        "event_id": event_id,
        "correlation_id": correlation_id,
        "event": event_type,
        "phase": phase.parse::<i64>().unwrap_or(0),
    });

    if let Some(p) = plan {
        if let Ok(plan_num) = p.parse::<i64>() {
            obj["plan"] = json!(plan_num);
        }
    }

    if !data_pairs.is_empty() {
        let mut data_obj = serde_json::Map::new();
        for (k, v) in data_pairs {
            data_obj.insert(k.clone(), json!(v));
        }
        obj["data"] = Value::Object(data_obj);
    }

    // Ensure .events/ directory exists
    let events_dir = planning_dir.join(".events");
    let _ = fs::create_dir_all(&events_dir);

    // Append atomically
    let events_file = events_dir.join("event-log.jsonl");
    let line = format!("{}\n", serde_json::to_string(&obj).unwrap_or_default());

    use std::io::Write;
    if let Ok(mut file) = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&events_file)
    {
        let _ = file.write_all(line.as_bytes());
    }

    Ok(LogResult {
        written: true,
        event_id: Some(event_id),
        reason: None,
    })
}

/// CLI entry point: `yolo log-event <type> <phase> [plan] [key=value...]`
pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    let start = Instant::now();

    // args[0] = "yolo", args[1] = "log-event", args[2] = type, args[3] = phase, ...
    if args.len() < 4 {
        return Err("Usage: yolo log-event <type> <phase> [plan] [key=value...]".to_string());
    }

    let event_type = &args[2];
    let phase = &args[3];
    let remaining = if args.len() > 4 { &args[4..] } else { &[] };

    let (plan, data_pairs) = parse_args(&remaining.to_vec());

    let result = log(event_type, phase, plan.as_deref(), &data_pairs, cwd)?;

    let mut delta = serde_json::Map::new();
    delta.insert("written".to_string(), json!(result.written));
    if let Some(eid) = &result.event_id {
        delta.insert("event_type".to_string(), json!(event_type));
        delta.insert("phase".to_string(), json!(phase.parse::<i64>().unwrap_or(0)));
        delta.insert("event_id".to_string(), json!(eid));
    }
    if let Some(reason) = &result.reason {
        delta.insert("reason".to_string(), json!(reason));
    }

    let exit_code = if result.written { 0 } else { 3 };

    let envelope = json!({
        "ok": true,
        "cmd": "log-event",
        "delta": delta,
        "elapsed_ms": start.elapsed().as_millis() as u64
    });

    Ok((serde_json::to_string(&envelope).unwrap_or_default(), exit_code))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use tempfile::TempDir;

    fn setup_test_env(v3_event_log: bool, v2_typed_protocol: bool) -> TempDir {
        let dir = TempDir::new().unwrap();
        let planning_dir = dir.path().join(".yolo-planning");
        fs::create_dir_all(&planning_dir).unwrap();
        let config = serde_json::json!({
            "v3_event_log": v3_event_log,
            "v2_typed_protocol": v2_typed_protocol,
        });
        fs::write(planning_dir.join("config.json"), config.to_string()).unwrap();
        dir
    }

    #[test]
    fn test_log_event_disabled() {
        let dir = setup_test_env(false, false);
        let result = log("phase_start", "1", None, &[], dir.path());
        assert!(result.is_ok());
        let lr = result.unwrap();
        assert!(!lr.written);
        assert_eq!(lr.reason.as_deref(), Some("v3_event_log disabled"));
        let events_file = dir.path().join(".yolo-planning/.events/event-log.jsonl");
        assert!(!events_file.exists());
    }

    #[test]
    fn test_log_event_basic() {
        let dir = setup_test_env(true, false);
        let result = log("phase_start", "1", None, &[], dir.path());
        assert!(result.is_ok());
        let lr = result.unwrap();
        assert!(lr.written);
        assert!(lr.event_id.is_some());
        assert!(lr.reason.is_none());
        let events_file = dir.path().join(".yolo-planning/.events/event-log.jsonl");
        assert!(events_file.exists());
        let content = fs::read_to_string(&events_file).unwrap();
        let entry: serde_json::Value = serde_json::from_str(content.trim()).unwrap();
        assert_eq!(entry["event"], "phase_start");
        assert_eq!(entry["phase"], 1);
        assert!(entry["event_id"].as_str().unwrap().len() > 0);
    }

    #[test]
    fn test_log_event_with_plan_and_data() {
        let dir = setup_test_env(true, false);
        let data = vec![
            ("gate".to_string(), "contract_compliance".to_string()),
            ("task".to_string(), "2".to_string()),
        ];
        let result = log("gate_passed", "1", Some("3"), &data, dir.path());
        assert!(result.is_ok());
        let events_file = dir.path().join(".yolo-planning/.events/event-log.jsonl");
        let content = fs::read_to_string(&events_file).unwrap();
        let entry: serde_json::Value = serde_json::from_str(content.trim()).unwrap();
        assert_eq!(entry["plan"], 3);
        assert_eq!(entry["data"]["gate"], "contract_compliance");
        assert_eq!(entry["data"]["task"], "2");
    }

    #[test]
    fn test_log_event_typed_protocol_rejects_unknown() {
        let dir = setup_test_env(true, true);
        let result = log("totally_unknown_event", "1", None, &[], dir.path());
        assert!(result.is_ok());
        let lr = result.unwrap();
        assert!(!lr.written);
        assert_eq!(lr.reason.as_deref(), Some("unknown event type rejected"));
        let events_file = dir.path().join(".yolo-planning/.events/event-log.jsonl");
        assert!(!events_file.exists());
    }

    #[test]
    fn test_log_event_typed_protocol_accepts_known() {
        let dir = setup_test_env(true, true);
        let result = log("gate_passed", "1", None, &[], dir.path());
        assert!(result.is_ok());
        let events_file = dir.path().join(".yolo-planning/.events/event-log.jsonl");
        assert!(events_file.exists());
    }

    #[test]
    fn test_correlation_id_from_env() {
        let dir = setup_test_env(true, false);
        unsafe { env::set_var("YOLO_CORRELATION_ID", "test-corr-id-123"); }
        let result = log("phase_start", "1", None, &[], dir.path());
        unsafe { env::remove_var("YOLO_CORRELATION_ID"); }
        assert!(result.is_ok());
        let events_file = dir.path().join(".yolo-planning/.events/event-log.jsonl");
        let content = fs::read_to_string(&events_file).unwrap();
        let entry: serde_json::Value = serde_json::from_str(content.trim()).unwrap();
        assert_eq!(entry["correlation_id"], "test-corr-id-123");
    }

    #[test]
    fn test_correlation_id_from_execution_state() {
        let dir = setup_test_env(true, false);
        let planning_dir = dir.path().join(".yolo-planning");
        let state = serde_json::json!({"correlation_id": "state-corr-456"});
        fs::write(planning_dir.join(".execution-state.json"), state.to_string()).unwrap();

        // Ensure env var is not set
        unsafe { env::remove_var("YOLO_CORRELATION_ID"); }
        let result = log("phase_start", "1", None, &[], dir.path());
        assert!(result.is_ok());
        let events_file = dir.path().join(".yolo-planning/.events/event-log.jsonl");
        let content = fs::read_to_string(&events_file).unwrap();
        let entry: serde_json::Value = serde_json::from_str(content.trim()).unwrap();
        assert_eq!(entry["correlation_id"], "state-corr-456");
    }

    #[test]
    fn test_parse_args_key_value() {
        let args: Vec<String> = vec![
            "gate=contract".to_string(),
            "task=2".to_string(),
        ];
        let (plan, pairs) = parse_args(&args);
        assert!(plan.is_none());
        assert_eq!(pairs.len(), 2);
        assert_eq!(pairs[0], ("gate".to_string(), "contract".to_string()));
    }

    #[test]
    fn test_parse_args_plan_and_kv() {
        let args: Vec<String> = vec![
            "5".to_string(),
            "gate=contract".to_string(),
        ];
        let (plan, pairs) = parse_args(&args);
        assert_eq!(plan, Some("5".to_string()));
        assert_eq!(pairs.len(), 1);
    }

    #[test]
    fn test_execute_cli() {
        let dir = setup_test_env(true, false);
        let args: Vec<String> = vec![
            "yolo".into(), "log-event".into(), "phase_start".into(), "1".into(),
        ];
        let result = execute(&args, dir.path());
        assert!(result.is_ok());
        let (output, code) = result.unwrap();
        assert_eq!(code, 0);

        let envelope: serde_json::Value = serde_json::from_str(&output).unwrap();
        assert_eq!(envelope["ok"], true);
        assert_eq!(envelope["cmd"], "log-event");
        assert_eq!(envelope["delta"]["written"], true);
        assert_eq!(envelope["delta"]["event_type"], "phase_start");
        assert_eq!(envelope["delta"]["phase"], 1);
        assert!(envelope["delta"]["event_id"].as_str().unwrap().len() > 0);
        assert!(envelope["elapsed_ms"].is_u64());
    }

    #[test]
    fn test_execute_cli_disabled_returns_skipped() {
        let dir = setup_test_env(false, false);
        let args: Vec<String> = vec![
            "yolo".into(), "log-event".into(), "phase_start".into(), "1".into(),
        ];
        let (output, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 3);

        let envelope: serde_json::Value = serde_json::from_str(&output).unwrap();
        assert_eq!(envelope["ok"], true);
        assert_eq!(envelope["delta"]["written"], false);
        assert_eq!(envelope["delta"]["reason"], "v3_event_log disabled");
    }

    #[test]
    fn test_execute_cli_typed_protocol_rejects_returns_skipped() {
        let dir = setup_test_env(true, true);
        let args: Vec<String> = vec![
            "yolo".into(), "log-event".into(), "totally_unknown".into(), "1".into(),
        ];
        let (output, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 3);

        let envelope: serde_json::Value = serde_json::from_str(&output).unwrap();
        assert_eq!(envelope["ok"], true);
        assert_eq!(envelope["delta"]["written"], false);
        assert_eq!(envelope["delta"]["reason"], "unknown event type rejected");
    }

    #[test]
    fn test_execute_cli_insufficient_args() {
        let dir = setup_test_env(true, false);
        let args: Vec<String> = vec!["yolo".into(), "log-event".into()];
        let result = execute(&args, dir.path());
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Usage:"));
    }

    #[test]
    fn test_agent_token_usage_accepted_by_typed_protocol() {
        let dir = setup_test_env(true, true);
        let data = vec![
            ("role".to_string(), "dev".to_string()),
            ("input_tokens".to_string(), "5000".to_string()),
            ("output_tokens".to_string(), "1200".to_string()),
            ("cache_read".to_string(), "3000".to_string()),
            ("cache_write".to_string(), "800".to_string()),
        ];
        let result = log("agent_token_usage", "1", None, &data, dir.path());
        assert!(result.is_ok());
        let events_file = dir.path().join(".yolo-planning/.events/event-log.jsonl");
        assert!(events_file.exists());
        let content = fs::read_to_string(&events_file).unwrap();
        let entry: serde_json::Value = serde_json::from_str(content.trim()).unwrap();
        assert_eq!(entry["event"], "agent_token_usage");
        assert_eq!(entry["data"]["input_tokens"], "5000");
        assert_eq!(entry["data"]["role"], "dev");
    }

    #[test]
    fn test_directory_creation() {
        let dir = setup_test_env(true, false);
        let events_dir = dir.path().join(".yolo-planning/.events");
        assert!(!events_dir.exists());
        let _ = log("phase_start", "1", None, &[], dir.path());
        assert!(events_dir.exists());
    }
}
