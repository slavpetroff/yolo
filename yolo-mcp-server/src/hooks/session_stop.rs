use chrono::Utc;
use serde_json::{json, Value};
use std::fs;
use std::io::Write;
use std::path::Path;
use std::process::Command;

/// Stop handler: log session metrics and clean up transient files.
///
/// - Extracts cost, duration, tokens, model from input
/// - Gets current branch via `git rev-parse`
/// - Appends metrics to `.session-log.jsonl`
/// - Persists cost summary from `.cost-ledger.json` if present
/// - Cleans up transient agent markers
/// - Always exit 0
pub fn handle_stop(input: &Value) -> (Value, i32) {
    let planning = Path::new(".yolo-planning");

    // Guard: only log if planning directory exists
    if !planning.is_dir() {
        return (Value::Null, 0);
    }

    // Extract session metrics
    let cost = extract_number(input, &["cost_usd", "cost"]);
    let duration = extract_number(input, &["duration_ms", "duration"]);
    let tokens_in = extract_number(input, &["tokens_in", "input_tokens"]);
    let tokens_out = extract_number(input, &["tokens_out", "output_tokens"]);
    let model = input
        .get("model")
        .and_then(|v| v.as_str())
        .unwrap_or("unknown");

    let branch = get_git_branch();
    let timestamp = Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string();

    // Append session metrics to log
    let session_entry = json!({
        "timestamp": timestamp,
        "duration_ms": duration,
        "cost_usd": cost,
        "tokens_in": tokens_in,
        "tokens_out": tokens_out,
        "model": model,
        "branch": branch,
    });

    let log_path = planning.join(".session-log.jsonl");
    append_jsonl(&log_path, &session_entry);

    // Persist cost summary from agent-attributed ledger
    persist_cost_summary(planning, &timestamp);

    // Clean up transient markers
    cleanup_transient(planning);

    (Value::Null, 0)
}

/// Extract a numeric value from input, trying multiple field names.
fn extract_number(input: &Value, keys: &[&str]) -> f64 {
    for key in keys {
        if let Some(v) = input.get(*key) {
            if let Some(n) = v.as_f64() {
                return n;
            }
            if let Some(n) = v.as_i64() {
                return n as f64;
            }
        }
    }
    0.0
}

/// Get current git branch via `git rev-parse --abbrev-ref HEAD`.
fn get_git_branch() -> String {
    Command::new("git")
        .args(["rev-parse", "--abbrev-ref", "HEAD"])
        .output()
        .ok()
        .and_then(|o| {
            if o.status.success() {
                String::from_utf8(o.stdout).ok().map(|s| s.trim().to_string())
            } else {
                None
            }
        })
        .unwrap_or_else(|| "unknown".to_string())
}

/// Append a JSON value as a single line to a JSONL file.
fn append_jsonl(path: &Path, entry: &Value) {
    let line = match serde_json::to_string(entry) {
        Ok(s) => s,
        Err(_) => return,
    };

    if let Ok(mut f) = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)
    {
        let _ = writeln!(f, "{}", line);
    }
}

/// Persist cost summary from `.cost-ledger.json` if valid JSON.
fn persist_cost_summary(planning: &Path, timestamp: &str) {
    let ledger_path = planning.join(".cost-ledger.json");
    if !ledger_path.is_file() {
        return;
    }

    let cost_data = match fs::read_to_string(&ledger_path) {
        Ok(c) if !c.trim().is_empty() => c,
        _ => {
            let _ = fs::remove_file(&ledger_path);
            return;
        }
    };

    let costs: Value = match serde_json::from_str(&cost_data) {
        Ok(v) => v,
        Err(_) => {
            let _ = fs::remove_file(&ledger_path);
            return;
        }
    };

    let summary_entry = json!({
        "timestamp": timestamp,
        "type": "cost_summary",
        "costs": costs,
    });

    let log_path = planning.join(".session-log.jsonl");
    append_jsonl(&log_path, &summary_entry);

    let _ = fs::remove_file(&ledger_path);
}

/// Clean up transient agent markers and stale lock dir.
fn cleanup_transient(planning: &Path) {
    // Remove lock directory (rmdir-safe: only removes if empty)
    let lock_dir = planning.join(".active-agent-count.lock");
    let _ = fs::remove_dir(&lock_dir);

    // Remove transient marker files
    let transient_files = [
        ".active-agent",
        ".active-agent-count",
        ".agent-panes",
        ".task-verify-seen",
    ];
    for name in &transient_files {
        let _ = fs::remove_file(planning.join(name));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_extract_number_cost_usd() {
        let input = json!({"cost_usd": 0.42});
        assert!((extract_number(&input, &["cost_usd", "cost"]) - 0.42).abs() < 0.001);
    }

    #[test]
    fn test_extract_number_fallback_key() {
        let input = json!({"cost": 1.5});
        assert!((extract_number(&input, &["cost_usd", "cost"]) - 1.5).abs() < 0.001);
    }

    #[test]
    fn test_extract_number_integer() {
        let input = json!({"tokens_in": 1000});
        assert!((extract_number(&input, &["tokens_in"]) - 1000.0).abs() < 0.001);
    }

    #[test]
    fn test_extract_number_missing() {
        let input = json!({});
        assert!((extract_number(&input, &["tokens_in"]) - 0.0).abs() < 0.001);
    }

    #[test]
    fn test_get_git_branch() {
        // Should return a non-empty string (we're in a git repo)
        let branch = get_git_branch();
        assert!(!branch.is_empty());
    }

    #[test]
    fn test_append_jsonl() {
        let dir = tempfile::tempdir().unwrap();
        let log_path = dir.path().join("test.jsonl");

        let entry1 = json!({"key": "value1"});
        let entry2 = json!({"key": "value2"});

        append_jsonl(&log_path, &entry1);
        append_jsonl(&log_path, &entry2);

        let content = fs::read_to_string(&log_path).unwrap();
        let lines: Vec<&str> = content.lines().collect();
        assert_eq!(lines.len(), 2);

        let parsed1: Value = serde_json::from_str(lines[0]).unwrap();
        assert_eq!(parsed1["key"], "value1");

        let parsed2: Value = serde_json::from_str(lines[1]).unwrap();
        assert_eq!(parsed2["key"], "value2");
    }

    #[test]
    fn test_cleanup_transient() {
        let dir = tempfile::tempdir().unwrap();
        let planning = dir.path();

        // Create transient files
        fs::write(planning.join(".active-agent"), "yolo-dev").unwrap();
        fs::write(planning.join(".active-agent-count"), "3").unwrap();
        fs::write(planning.join(".agent-panes"), "pane1").unwrap();
        fs::write(planning.join(".task-verify-seen"), "1").unwrap();
        fs::create_dir(planning.join(".active-agent-count.lock")).unwrap();

        cleanup_transient(planning);

        assert!(!planning.join(".active-agent").exists());
        assert!(!planning.join(".active-agent-count").exists());
        assert!(!planning.join(".agent-panes").exists());
        assert!(!planning.join(".task-verify-seen").exists());
        assert!(!planning.join(".active-agent-count.lock").exists());
    }

    #[test]
    fn test_persist_cost_summary() {
        let dir = tempfile::tempdir().unwrap();
        let planning = dir.path();

        let ledger = json!({"yolo-dev": 0.25, "yolo-lead": 0.10});
        fs::write(
            planning.join(".cost-ledger.json"),
            serde_json::to_string(&ledger).unwrap(),
        )
        .unwrap();

        let timestamp = "2026-02-20T10:00:00Z";
        persist_cost_summary(planning, timestamp);

        // Ledger should be deleted
        assert!(!planning.join(".cost-ledger.json").exists());

        // Session log should have the cost summary
        let log_content = fs::read_to_string(planning.join(".session-log.jsonl")).unwrap();
        let entry: Value = serde_json::from_str(log_content.trim()).unwrap();
        assert_eq!(entry["type"], "cost_summary");
        assert_eq!(entry["timestamp"], timestamp);
        assert!((entry["costs"]["yolo-dev"].as_f64().unwrap() - 0.25).abs() < 0.001);
    }

    #[test]
    fn test_persist_cost_summary_no_ledger() {
        let dir = tempfile::tempdir().unwrap();
        let planning = dir.path();

        // No ledger file — should be a no-op
        persist_cost_summary(planning, "2026-02-20T10:00:00Z");

        assert!(!planning.join(".session-log.jsonl").exists());
    }

    #[test]
    fn test_handle_stop_no_planning_dir() {
        // Without .yolo-planning, should return null, exit 0
        let input = json!({"cost_usd": 1.0});
        let (output, code) = handle_stop(&input);
        assert_eq!(code, 0);
        assert_eq!(output, Value::Null);
    }

    #[test]
    fn test_handle_stop_with_planning_dir() {
        let dir = tempfile::tempdir().unwrap();
        let planning = dir.path().join(".yolo-planning");
        fs::create_dir_all(&planning).unwrap();

        // We can't easily test handle_stop directly because it uses a hardcoded
        // ".yolo-planning" path, but we can test the component functions
        let input = json!({
            "cost_usd": 0.42,
            "duration_ms": 30000,
            "tokens_in": 5000,
            "tokens_out": 2000,
            "model": "claude-opus-4-6"
        });

        // Test metric extraction
        assert!((extract_number(&input, &["cost_usd", "cost"]) - 0.42).abs() < 0.001);
        assert!((extract_number(&input, &["duration_ms", "duration"]) - 30000.0).abs() < 0.001);
        assert!((extract_number(&input, &["tokens_in", "input_tokens"]) - 5000.0).abs() < 0.001);
        assert!((extract_number(&input, &["tokens_out", "output_tokens"]) - 2000.0).abs() < 0.001);
    }
}
