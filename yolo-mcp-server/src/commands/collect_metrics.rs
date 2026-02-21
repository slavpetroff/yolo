use chrono::Utc;
use serde_json::json;
use std::fs;
use std::path::Path;
use std::time::Instant;

pub struct CollectResult {
    pub written: bool,
    pub metrics_file: String,
}

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

/// Core metrics collection function callable from other Rust code.
/// Appends a JSON line to `.yolo-planning/.metrics/run-metrics.jsonl`.
/// Never fails fatally — returns Ok with CollectResult.
pub fn collect(
    event: &str,
    phase: &str,
    plan: Option<&str>,
    data_pairs: &[(String, String)],
    cwd: &Path,
) -> Result<CollectResult, String> {
    let planning_dir = cwd.join(".yolo-planning");
    let metrics_dir = planning_dir.join(".metrics");

    // Create .metrics/ directory if needed
    let _ = fs::create_dir_all(&metrics_dir);

    let ts = Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string();

    // Build JSON object
    let mut obj = json!({
        "ts": ts,
        "event": event,
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
        obj["data"] = serde_json::Value::Object(data_obj);
    }

    // Append atomically
    let metrics_file = metrics_dir.join("run-metrics.jsonl");
    let line = format!("{}\n", serde_json::to_string(&obj).unwrap_or_default());

    use std::io::Write;
    if let Ok(mut file) = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&metrics_file)
    {
        let _ = file.write_all(line.as_bytes());
    }

    Ok(CollectResult {
        written: true,
        metrics_file: metrics_file.to_string_lossy().to_string(),
    })
}

/// CLI entry point: `yolo collect-metrics <event> <phase> [plan] [key=value...]`
pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    let start = Instant::now();

    // args[0] = "yolo", args[1] = "collect-metrics", args[2] = event, args[3] = phase, ...
    if args.len() < 4 {
        return Err("Usage: yolo collect-metrics <event> <phase> [plan] [key=value...]".to_string());
    }

    let event = &args[2];
    let phase = &args[3];
    let remaining = if args.len() > 4 { &args[4..] } else { &[] };

    let (plan, data_pairs) = parse_args(&remaining.to_vec());

    let result = collect(event, phase, plan.as_deref(), &data_pairs, cwd)?;

    let envelope = json!({
        "ok": true,
        "cmd": "collect-metrics",
        "delta": {
            "event": event,
            "phase": phase.parse::<i64>().unwrap_or(0),
            "written": result.written,
            "metrics_file": result.metrics_file
        },
        "elapsed_ms": start.elapsed().as_millis() as u64
    });

    Ok((serde_json::to_string(&envelope).unwrap_or_default(), 0))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use tempfile::TempDir;

    fn setup_test_env() -> TempDir {
        let dir = TempDir::new().unwrap();
        let planning_dir = dir.path().join(".yolo-planning");
        fs::create_dir_all(&planning_dir).unwrap();
        dir
    }

    #[test]
    fn test_collect_basic() {
        let dir = setup_test_env();
        let result = collect("cache_hit", "1", None, &[], dir.path());
        assert!(result.is_ok());
        let cr = result.unwrap();
        assert!(cr.written);
        assert!(cr.metrics_file.contains("run-metrics.jsonl"));
        let metrics_file = dir.path().join(".yolo-planning/.metrics/run-metrics.jsonl");
        assert!(metrics_file.exists());
        let content = fs::read_to_string(&metrics_file).unwrap();
        let entry: serde_json::Value = serde_json::from_str(content.trim()).unwrap();
        assert_eq!(entry["event"], "cache_hit");
        assert_eq!(entry["phase"], 1);
    }

    #[test]
    fn test_collect_with_plan() {
        let dir = setup_test_env();
        let result = collect("execute_task", "2", Some("3"), &[], dir.path());
        assert!(result.is_ok());
        let metrics_file = dir.path().join(".yolo-planning/.metrics/run-metrics.jsonl");
        let content = fs::read_to_string(&metrics_file).unwrap();
        let entry: serde_json::Value = serde_json::from_str(content.trim()).unwrap();
        assert_eq!(entry["plan"], 3);
    }

    #[test]
    fn test_collect_with_data_pairs() {
        let dir = setup_test_env();
        let data = vec![
            ("gate".to_string(), "contract_compliance".to_string()),
            ("task".to_string(), "1".to_string()),
        ];
        let result = collect("gate_pass", "1", Some("2"), &data, dir.path());
        assert!(result.is_ok());
        let metrics_file = dir.path().join(".yolo-planning/.metrics/run-metrics.jsonl");
        let content = fs::read_to_string(&metrics_file).unwrap();
        let entry: serde_json::Value = serde_json::from_str(content.trim()).unwrap();
        assert_eq!(entry["data"]["gate"], "contract_compliance");
        assert_eq!(entry["data"]["task"], "1");
    }

    #[test]
    fn test_directory_creation() {
        let dir = setup_test_env();
        let metrics_dir = dir.path().join(".yolo-planning/.metrics");
        assert!(!metrics_dir.exists());
        let _ = collect("cache_hit", "1", None, &[], dir.path());
        assert!(metrics_dir.exists());
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
        let dir = setup_test_env();
        let args: Vec<String> = vec![
            "yolo".into(), "collect-metrics".into(), "cache_hit".into(), "1".into(),
        ];
        let result = execute(&args, dir.path());
        assert!(result.is_ok());
        let (output, code) = result.unwrap();
        assert_eq!(code, 0);

        let envelope: serde_json::Value = serde_json::from_str(&output).unwrap();
        assert_eq!(envelope["ok"], true);
        assert_eq!(envelope["cmd"], "collect-metrics");
        assert_eq!(envelope["delta"]["event"], "cache_hit");
        assert_eq!(envelope["delta"]["phase"], 1);
        assert_eq!(envelope["delta"]["written"], true);
        assert!(envelope["delta"]["metrics_file"].as_str().unwrap().contains("run-metrics.jsonl"));
        assert!(envelope["elapsed_ms"].is_u64());
    }

    #[test]
    fn test_execute_cli_with_kv() {
        let dir = setup_test_env();
        let args: Vec<String> = vec![
            "yolo".into(), "collect-metrics".into(), "gate_pass".into(),
            "1".into(), "2".into(), "gate=contract".into(),
        ];
        let result = execute(&args, dir.path());
        assert!(result.is_ok());
        let metrics_file = dir.path().join(".yolo-planning/.metrics/run-metrics.jsonl");
        let content = fs::read_to_string(&metrics_file).unwrap();
        let entry: serde_json::Value = serde_json::from_str(content.trim()).unwrap();
        assert_eq!(entry["plan"], 2);
        assert_eq!(entry["data"]["gate"], "contract");
    }

    #[test]
    fn test_execute_cli_insufficient_args() {
        let dir = setup_test_env();
        let args: Vec<String> = vec!["yolo".into(), "collect-metrics".into()];
        let result = execute(&args, dir.path());
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Usage:"));
    }

    #[test]
    fn test_collect_agent_token_usage() {
        let dir = setup_test_env();
        let data = vec![
            ("input_tokens".to_string(), "5000".to_string()),
            ("output_tokens".to_string(), "1200".to_string()),
            ("cache_read_tokens".to_string(), "3000".to_string()),
            ("cache_write_tokens".to_string(), "800".to_string()),
            ("agent_role".to_string(), "dev".to_string()),
        ];
        let result = collect("agent_token_usage", "1", Some("1"), &data, dir.path());
        assert!(result.is_ok());
        let metrics_file = dir.path().join(".yolo-planning/.metrics/run-metrics.jsonl");
        assert!(metrics_file.exists());
        let content = fs::read_to_string(&metrics_file).unwrap();
        let entry: serde_json::Value = serde_json::from_str(content.trim()).unwrap();
        assert_eq!(entry["event"], "agent_token_usage");
        assert_eq!(entry["phase"], 1);
        assert_eq!(entry["plan"], 1);
        assert_eq!(entry["data"]["input_tokens"], "5000");
        assert_eq!(entry["data"]["output_tokens"], "1200");
        assert_eq!(entry["data"]["cache_read_tokens"], "3000");
        assert_eq!(entry["data"]["cache_write_tokens"], "800");
        assert_eq!(entry["data"]["agent_role"], "dev");
    }

    #[test]
    fn test_multiple_appends() {
        let dir = setup_test_env();
        let _ = collect("event_a", "1", None, &[], dir.path());
        let _ = collect("event_b", "2", None, &[], dir.path());
        let metrics_file = dir.path().join(".yolo-planning/.metrics/run-metrics.jsonl");
        let content = fs::read_to_string(&metrics_file).unwrap();
        let lines: Vec<&str> = content.trim().lines().collect();
        assert_eq!(lines.len(), 2);
    }
}
