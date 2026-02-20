use chrono::Utc;
use serde_json::{json, Value};
use std::fs;
use std::io::Write;
use std::path::Path;

/// Notification handler: log notification metadata to `.notification-log.jsonl`.
///
/// - Extracts notification_type, message, title from input
/// - Appends JSON line to `.yolo-planning/.notification-log.jsonl`
/// - Always exit 0
pub fn handle_notification(input: &Value) -> (Value, i32) {
    let planning = Path::new(".yolo-planning");

    // Guard: only log if planning directory exists
    if !planning.is_dir() {
        return (Value::Null, 0);
    }

    let timestamp = Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string();
    let ntype = input
        .get("notification_type")
        .and_then(|v| v.as_str())
        .unwrap_or("unknown");
    let message = input
        .get("message")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let title = input.get("title").and_then(|v| v.as_str()).unwrap_or("");

    let entry = json!({
        "timestamp": timestamp,
        "type": ntype,
        "title": title,
        "message": message,
    });

    let log_path = planning.join(".notification-log.jsonl");
    let line = match serde_json::to_string(&entry) {
        Ok(s) => s,
        Err(_) => return (Value::Null, 0),
    };

    if let Ok(mut f) = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&log_path)
    {
        let _ = writeln!(f, "{}", line);
    }

    (Value::Null, 0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_handle_notification_no_planning() {
        // Without .yolo-planning dir, returns null, exit 0
        let input = json!({"notification_type": "info", "message": "test"});
        let (output, code) = handle_notification(&input);
        assert_eq!(code, 0);
        assert_eq!(output, Value::Null);
    }

    #[test]
    fn test_handle_notification_with_dir() {
        let dir = tempfile::tempdir().unwrap();
        let planning = dir.path().join(".yolo-planning");
        fs::create_dir_all(&planning).unwrap();

        // We test the JSON construction directly since handle_notification uses
        // a hardcoded path. The real integration test verifies end-to-end.
        let timestamp = Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string();
        let entry = json!({
            "timestamp": timestamp,
            "type": "warning",
            "title": "Test Title",
            "message": "Test message body",
        });

        let log_path = planning.join(".notification-log.jsonl");
        let line = serde_json::to_string(&entry).unwrap();
        let mut f = fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(&log_path)
            .unwrap();
        writeln!(f, "{}", line).unwrap();

        let content = fs::read_to_string(&log_path).unwrap();
        let parsed: Value = serde_json::from_str(content.trim()).unwrap();
        assert_eq!(parsed["type"], "warning");
        assert_eq!(parsed["title"], "Test Title");
        assert_eq!(parsed["message"], "Test message body");
    }

    #[test]
    fn test_handle_notification_missing_fields() {
        let input = json!({});
        let (output, code) = handle_notification(&input);
        assert_eq!(code, 0);
        assert_eq!(output, Value::Null);
    }

    #[test]
    fn test_notification_entry_format() {
        let input = json!({
            "notification_type": "error",
            "message": "Something failed",
            "title": "Error Alert"
        });

        let ntype = input
            .get("notification_type")
            .and_then(|v| v.as_str())
            .unwrap_or("unknown");
        let message = input
            .get("message")
            .and_then(|v| v.as_str())
            .unwrap_or("");
        let title = input.get("title").and_then(|v| v.as_str()).unwrap_or("");

        assert_eq!(ntype, "error");
        assert_eq!(message, "Something failed");
        assert_eq!(title, "Error Alert");
    }

    #[test]
    fn test_notification_defaults() {
        let input = json!({"other_field": "value"});

        let ntype = input
            .get("notification_type")
            .and_then(|v| v.as_str())
            .unwrap_or("unknown");
        let message = input
            .get("message")
            .and_then(|v| v.as_str())
            .unwrap_or("");
        let title = input.get("title").and_then(|v| v.as_str()).unwrap_or("");

        assert_eq!(ntype, "unknown");
        assert_eq!(message, "");
        assert_eq!(title, "");
    }
}
