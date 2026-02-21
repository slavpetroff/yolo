use serde::Serialize;
use serde_json::Value;
use std::time::Instant;

pub const EXIT_SUCCESS: i32 = 0;
pub const EXIT_ERROR: i32 = 1;
pub const EXIT_PARTIAL: i32 = 2;
pub const EXIT_SKIPPED: i32 = 3;

pub struct Timer(Instant);

impl Timer {
    pub fn start() -> Self {
        Self(Instant::now())
    }

    pub fn elapsed_ms(&self) -> u64 {
        self.0.elapsed().as_millis() as u64
    }
}

#[derive(Serialize)]
pub struct StructuredResponse {
    pub ok: bool,
    pub cmd: String,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub changed: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub delta: Option<Value>,
    pub elapsed_ms: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

impl StructuredResponse {
    pub fn success(cmd: &str) -> Self {
        Self {
            ok: true,
            cmd: cmd.to_string(),
            changed: Vec::new(),
            delta: None,
            elapsed_ms: 0,
            error: None,
        }
    }

    pub fn error(cmd: &str, msg: &str) -> Self {
        Self {
            ok: false,
            cmd: cmd.to_string(),
            changed: Vec::new(),
            delta: None,
            elapsed_ms: 0,
            error: Some(msg.to_string()),
        }
    }

    pub fn with_changed(mut self, files: Vec<String>) -> Self {
        self.changed = files;
        self
    }

    pub fn with_delta(mut self, value: Value) -> Self {
        self.delta = Some(value);
        self
    }

    pub fn with_elapsed(mut self, ms: u64) -> Self {
        self.elapsed_ms = ms;
        self
    }

    pub fn to_json_string(&self) -> String {
        serde_json::to_string(self).unwrap_or_else(|e| {
            format!(r#"{{"ok":false,"cmd":"{}","error":"serialization failed: {}","elapsed_ms":0}}"#, self.cmd, e)
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn test_success_constructor() {
        let resp = StructuredResponse::success("update-state");
        assert!(resp.ok);
        assert_eq!(resp.cmd, "update-state");
        assert!(resp.changed.is_empty());
        assert!(resp.delta.is_none());
        assert_eq!(resp.elapsed_ms, 0);
        assert!(resp.error.is_none());
    }

    #[test]
    fn test_error_constructor() {
        let resp = StructuredResponse::error("update-state", "file not found");
        assert!(!resp.ok);
        assert_eq!(resp.cmd, "update-state");
        assert_eq!(resp.error.as_deref(), Some("file not found"));
    }

    #[test]
    fn test_builder_with_changed() {
        let resp = StructuredResponse::success("update-state")
            .with_changed(vec!["STATE.md".to_string(), "ROADMAP.md".to_string()]);
        assert_eq!(resp.changed.len(), 2);
        assert_eq!(resp.changed[0], "STATE.md");
    }

    #[test]
    fn test_builder_with_delta() {
        let resp = StructuredResponse::success("update-state")
            .with_delta(json!({"plans_before": 0, "plans_after": 1}));
        assert!(resp.delta.is_some());
        assert_eq!(resp.delta.as_ref().unwrap()["plans_before"], 0);
    }

    #[test]
    fn test_builder_with_elapsed() {
        let resp = StructuredResponse::success("test").with_elapsed(42);
        assert_eq!(resp.elapsed_ms, 42);
    }

    #[test]
    fn test_to_json_string_success() {
        let resp = StructuredResponse::success("update-state")
            .with_changed(vec!["STATE.md".to_string()])
            .with_delta(json!({"trigger": "plan"}))
            .with_elapsed(10);

        let json_str = resp.to_json_string();
        let parsed: Value = serde_json::from_str(&json_str).unwrap();

        assert_eq!(parsed["ok"], true);
        assert_eq!(parsed["cmd"], "update-state");
        assert_eq!(parsed["changed"][0], "STATE.md");
        assert_eq!(parsed["delta"]["trigger"], "plan");
        assert_eq!(parsed["elapsed_ms"], 10);
        // error should be absent (skip_serializing_if)
        assert!(parsed.get("error").is_none());
    }

    #[test]
    fn test_to_json_string_error() {
        let resp = StructuredResponse::error("update-state", "bad input");
        let json_str = resp.to_json_string();
        let parsed: Value = serde_json::from_str(&json_str).unwrap();

        assert_eq!(parsed["ok"], false);
        assert_eq!(parsed["error"], "bad input");
        // changed should be absent when empty
        assert!(parsed.get("changed").is_none());
        // delta should be absent when None
        assert!(parsed.get("delta").is_none());
    }

    #[test]
    fn test_timer_elapsed() {
        let timer = Timer::start();
        std::thread::sleep(std::time::Duration::from_millis(10));
        let ms = timer.elapsed_ms();
        assert!(ms >= 5, "Timer should have elapsed at least 5ms, got {}", ms);
    }

    #[test]
    fn test_exit_code_constants() {
        assert_eq!(EXIT_SUCCESS, 0);
        assert_eq!(EXIT_ERROR, 1);
        assert_eq!(EXIT_PARTIAL, 2);
        assert_eq!(EXIT_SKIPPED, 3);
    }
}
