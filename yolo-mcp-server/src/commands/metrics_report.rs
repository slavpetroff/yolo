use std::path::Path;
use std::fs;
use chrono::{DateTime, Utc};
use serde_json::Value;

pub fn generate_metrics_report(cwd: &Path, phase_filter: Option<&str>) -> Result<(String, i32), String> {
    let planning_dir = cwd.join(".yolo-planning");
    let metrics_file = planning_dir.join(".metrics").join("run-metrics.jsonl");
    let events_file = planning_dir.join(".events").join("event-log.jsonl");
    let config_file = planning_dir.join("config.json");

    if !metrics_file.exists() && !events_file.exists() {
        let msg = "# Metrics Report\n\nNo metrics data found. Enable `v3_metrics=true` and `v3_event_log=true` in config.\n".to_string();
        return Ok((msg, 0));
    }

    let mut out = String::new();
    let now: DateTime<Utc> = Utc::now();
    out.push_str("# YOLO Observability Report\n\n");
    out.push_str(&format!("Generated: {}\n", now.format("%Y-%m-%dT%H:%M:%SZ")));
    
    if let Some(pf) = phase_filter {
        out.push_str(&format!("Phase filter: {}\n", pf));
    }
    out.push_str("\n");

    // Load data
    let events: Vec<Value> = load_jsonl(&events_file);
    let metrics: Vec<Value> = load_jsonl(&metrics_file);

    // Filter by phase if needed
    let events: Vec<Value> = if let Some(pf) = phase_filter {
        events.into_iter().filter(|v| v["phase"].as_str() == Some(pf) || v["phase"].as_i64() == pf.parse::<i64>().ok()).collect()
    } else {
        events
    };

    let metrics: Vec<Value> = if let Some(pf) = phase_filter {
        metrics.into_iter().filter(|v| v["phase"].as_str() == Some(pf) || v["phase"].as_i64() == pf.parse::<i64>().ok()).collect()
    } else {
        metrics
    };

    // --- Metric 1: Task Latency ---
    out.push_str("## Task Latency\n");
    let task_starts: Vec<&Value> = events.iter().filter(|e| e["event"] == "task_started").collect();
    let task_confirms: Vec<&Value> = events.iter().filter(|e| e["event"] == "task_completed_confirmed").collect();
    
    let start_count = task_starts.len();
    let confirm_count = task_confirms.len();
    
    out.push_str(&format!("- Tasks started: {}\n", start_count));
    out.push_str(&format!("- Tasks confirmed: {}\n", confirm_count));

    let mut median_latency = "N/A".to_string();
    if start_count > 0 && confirm_count > 0 {
        let mut latencies: Vec<f64> = vec![];
        for confirm in &task_confirms {
            if let Some(task_id) = confirm["data"]["task_id"].as_str() {
                if let Some(start) = task_starts.iter().find(|s| s["data"]["task_id"].as_str() == Some(task_id)) {
                    if let (Some(start_ts), Some(end_ts)) = (start["ts"].as_str(), confirm["ts"].as_str()) {
                        if let (Ok(s_time), Ok(e_time)) = (DateTime::parse_from_rfc3339(start_ts), DateTime::parse_from_rfc3339(end_ts)) {
                            let duration = e_time.signed_duration_since(s_time).num_seconds();
                            latencies.push(duration as f64);
                        }
                    }
                }
            }
        }
        
        if !latencies.is_empty() {
            latencies.sort_by(|a, b| a.partial_cmp(b).unwrap());
            let mid = latencies.len() / 2;
            let median = if latencies.len() % 2 == 1 {
                latencies[mid]
            } else {
                (latencies[mid - 1] + latencies[mid]) / 2.0
            };
            median_latency = format!("{}s", median);
        }
    }
    out.push_str(&format!("- Median latency: {}\n\n", median_latency));

    // --- Metric 2: Tokens per Task ---
    out.push_str("## Tokens per Task\n");
    let overage_count = metrics.iter().filter(|m| m["event"] == "token_overage").count();
    out.push_str(&format!("- Token overage events: {}\n\n", overage_count));

    // --- Metric 3: Gate Failure Rate ---
    out.push_str("## Gate Failure Rate\n");
    let gate_passed = events.iter().filter(|e| e["event"] == "gate_passed").count();
    let gate_failed = events.iter().filter(|e| e["event"] == "gate_failed").count();
    let gate_total = gate_passed + gate_failed;
    
    let mut fr = 0;
    if gate_total > 0 {
        fr = (gate_failed * 100) / gate_total;
        out.push_str(&format!("- Passed: {} / Failed: {} / Total: {}\n", gate_passed, gate_failed, gate_total));
        out.push_str(&format!("- Failure rate: {}%\n", fr));
    } else {
        out.push_str("- No gate events recorded\n");
    }
    out.push_str("\n");

    // --- Metric 4: Lease Conflicts ---
    out.push_str("## Lease Conflicts\n");
    let conflicts = metrics.iter().filter(|m| m["event"] == "file_conflict").count();
    out.push_str(&format!("- Conflicts detected: {}\n\n", conflicts));

    // --- Metric 5: Resume Success ---
    out.push_str("## Resume Success\n");
    let resumes = events.iter().filter(|e| e["event"] == "snapshot_restored" || e["event"] == "state_recovered").count();
    out.push_str(&format!("- Successful resumes: {}\n\n", resumes));

    // --- Metric 6: Regression Escape ---
    out.push_str("## Regression Escape\n");
    let rejections = events.iter().filter(|e| e["event"] == "task_completion_rejected").count();
    out.push_str(&format!("- Task completion rejections: {}\n\n", rejections));

    // --- Metric 7: Fallback Executions ---
    out.push_str("## Fallback Executions\n");
    let smart_routes = metrics.iter().filter(|m| m["event"] == "smart_route").count();
    let fallbacks = metrics.iter().filter(|m| m["event"] == "smart_route" && m["data"]["routed"] == "turbo").count();
    if smart_routes > 0 {
        let fallback_pct = (fallbacks * 100) / smart_routes;
        out.push_str(&format!("- Smart routes: {} / Turbo fallbacks: {}\n", smart_routes, fallbacks));
        out.push_str(&format!("- Fallback rate: {}%\n", fallback_pct));
    } else {
        out.push_str("- No smart routing data\n");
    }
    out.push_str("\n");

    // Context Profile
    let mut profile_effort = "unknown".to_string();
    let mut profile_autonomy = "unknown".to_string();
    if config_file.exists() {
        if let Ok(content) = fs::read_to_string(&config_file) {
            if let Ok(cfg) = serde_json::from_str::<Value>(&content) {
                profile_effort = cfg["effort"].as_str().unwrap_or("unknown").to_string();
                profile_autonomy = cfg["autonomy"].as_str().unwrap_or("unknown").to_string();
            }
        }
    }

    // Summary Table
    out.push_str("## Summary\n\n");
    out.push_str(&format!("Profile: effort={}, autonomy={}\n\n", profile_effort, profile_autonomy));
    out.push_str("| Metric | Value |\n|--------|-------|\n");
    
    out.push_str(&format!("| Tasks started | {} |\n", start_count));
    out.push_str(&format!("| Tasks confirmed | {} |\n", confirm_count));
    out.push_str(&format!("| Median latency | {} |\n", median_latency));
    out.push_str(&format!("| Token overages | {} |\n", overage_count));
    out.push_str(&format!("| Gate failure rate | {}% ({}/{}) |\n", fr, gate_failed, gate_total));
    out.push_str(&format!("| Lease conflicts | {} |\n", conflicts));
    out.push_str(&format!("| Resume successes | {} |\n", resumes));
    out.push_str(&format!("| Completion rejections | {} |\n\n", rejections));

    // Breakdown
    out.push_str("## Profile x Autonomy Breakdown\n\n");
    
    let mut has_segmented_data = false;
    let gate_with_autonomy = events.iter().filter(|e| (e["event"] == "gate_passed" || e["event"] == "gate_failed") && (e["data"]["autonomy"].is_string() || e["autonomy"].is_string())).count();
    let smart_route_count = smart_routes;

    if gate_with_autonomy > 0 || smart_route_count > 0 {
        has_segmented_data = true;
    }

    if has_segmented_data {
        out.push_str("| Profile | Autonomy | Gate Events | Routes |\n|---------|----------|-------------|--------|\n");
        
        let mut autonomy_counts: std::collections::HashMap<String, usize> = std::collections::HashMap::new();
        for e in events.iter().filter(|e| e["event"] == "gate_passed" || e["event"] == "gate_failed") {
            if let Some(auto) = e["autonomy"].as_str().or(e["data"]["autonomy"].as_str()) {
                *autonomy_counts.entry(auto.to_string()).or_insert(0) += 1;
            }
        }
        
        if !autonomy_counts.is_empty() {
            for (auto, count) in autonomy_counts {
                out.push_str(&format!("| {} | {} | {} | {} |\n", profile_effort, auto, count, smart_route_count));
            }
        } else if smart_route_count > 0 {
            out.push_str(&format!("| {} | {} | 0 | {} |\n", profile_effort, profile_autonomy, smart_route_count));
        }
    } else {
        out.push_str("No segmented data available.\n");
    }

    Ok((out, 0))
}

fn load_jsonl(path: &Path) -> Vec<Value> {
    let mut res = Vec::new();
    if let Ok(content) = fs::read_to_string(path) {
        for line in content.lines() {
            if let Ok(v) = serde_json::from_str::<Value>(line) {
                res.push(v);
            }
        }
    }
    res
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;
    use serde_json::json;

    #[test]
    fn test_generate_metrics_report_no_data() {
        let dir = tempdir().unwrap();
        let (out, code) = generate_metrics_report(dir.path(), None).unwrap();
        assert_eq!(code, 0);
        assert!(out.contains("No metrics data found"));
    }

    #[test]
    fn test_generate_metrics_report_with_data() {
        let dir = tempdir().unwrap();
        let plan_dir = dir.path().join(".yolo-planning");
        fs::create_dir(&plan_dir).unwrap();
        fs::create_dir(plan_dir.join(".metrics")).unwrap();
        fs::create_dir(plan_dir.join(".events")).unwrap();
        
        let events_file = plan_dir.join(".events").join("event-log.jsonl");
        fs::write(&events_file, r#"
{"event": "task_started", "ts": "2023-10-01T12:00:00Z", "data": {"task_id": "1"}, "phase": "1"}
{"event": "task_completed_confirmed", "ts": "2023-10-01T12:05:00Z", "data": {"task_id": "1"}, "phase": "1"}
{"event": "gate_failed", "ts": "2023-10-01T12:01:00Z", "autonomy": "low"}
{"event": "snapshot_restored", "ts": "2023-10-01T12:02:00Z"}
        "#).unwrap();

        let metrics_file = plan_dir.join(".metrics").join("run-metrics.jsonl");
        fs::write(&metrics_file, r#"
{"event": "token_overage", "phase": "1"}
{"event": "file_conflict"}
{"event": "smart_route", "data": {"routed": "turbo"}}
        "#).unwrap();

        let config_file = plan_dir.join("config.json");
        fs::write(&config_file, json!({"effort": "high", "autonomy": "full"}).to_string()).unwrap();

        let (out, code) = generate_metrics_report(dir.path(), None).unwrap();
        assert_eq!(code, 0);
        assert!(out.contains("## Task Latency"));
        assert!(out.contains("300s")); // 5 minutes latency
        assert!(out.contains("Token overage events: 1"));
        assert!(out.contains("Failure rate: 100%"));
        assert!(out.contains("Conflicts detected: 1"));
        assert!(out.contains("Successful resumes: 1"));
        assert!(out.contains("Fallback rate: 100%"));
        assert!(out.contains("Profile: effort=high, autonomy=full"));
    }
}
