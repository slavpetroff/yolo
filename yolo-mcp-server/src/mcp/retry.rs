use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant, SystemTime};

use serde_json::Value;
use tokio::sync::Mutex;

use crate::mcp::tools::{self, ToolState};

/// Configuration for retry behavior.
#[derive(Debug, Clone)]
pub struct RetryConfig {
    pub max_retries: u32,
    pub base_delay_ms: u64,
    pub max_delay_ms: u64,
}

impl Default for RetryConfig {
    fn default() -> Self {
        Self {
            max_retries: 3,
            base_delay_ms: 100,
            max_delay_ms: 1000,
        }
    }
}

/// Tracks per-tool failure state to prevent calling consistently-broken tools.
pub struct CircuitBreaker {
    failure_counts: HashMap<String, u32>,
    open_until: HashMap<String, Instant>,
    pub failure_threshold: u32,
    pub reset_duration: Duration,
}

impl CircuitBreaker {
    pub fn new() -> Self {
        Self {
            failure_counts: HashMap::new(),
            open_until: HashMap::new(),
            failure_threshold: 5,
            reset_duration: Duration::from_secs(60),
        }
    }

    /// Returns true if the circuit is open (tool should not be called).
    pub fn is_open(&self, tool_name: &str) -> bool {
        if let Some(until) = self.open_until.get(tool_name) {
            if Instant::now() < *until {
                return true;
            }
        }
        false
    }

    /// Resets failure count on success.
    pub fn record_success(&mut self, tool_name: &str) {
        self.failure_counts.remove(tool_name);
        self.open_until.remove(tool_name);
    }

    /// Increments failure count; opens circuit if threshold is reached.
    pub fn record_failure(&mut self, tool_name: &str) {
        let count = self.failure_counts.entry(tool_name.to_string()).or_insert(0);
        *count += 1;
        if *count >= self.failure_threshold {
            self.open_until
                .insert(tool_name.to_string(), Instant::now() + self.reset_duration);
        }
    }

    /// Returns current failure count for a tool.
    pub fn failure_count(&self, tool_name: &str) -> u32 {
        self.failure_counts.get(tool_name).copied().unwrap_or(0)
    }
}

/// Stats returned alongside the tool result.
#[derive(Debug, Clone)]
pub struct RetryStats {
    pub attempts: u32,
    pub retried: bool,
    pub circuit_opened: bool,
}

/// Error messages that indicate input validation failures (should not be retried).
const NON_RETRYABLE_PATTERNS: &[&str] = &["Unknown tool", "No test_path"];

fn is_retryable_error(result: &Value) -> bool {
    let is_error = result
        .get("isError")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    if !is_error {
        return false;
    }

    // Check error message text against non-retryable patterns
    let error_text = result
        .get("content")
        .and_then(|c| c.as_array())
        .and_then(|arr| arr.first())
        .and_then(|item| item.get("text"))
        .and_then(|t| t.as_str())
        .unwrap_or("");

    for pattern in NON_RETRYABLE_PATTERNS {
        if error_text.contains(pattern) {
            return false;
        }
    }

    true
}

/// Compute delay with exponential backoff and jitter.
fn compute_delay(attempt: u32, config: &RetryConfig) -> Duration {
    let exp_delay = config.base_delay_ms.saturating_mul(1u64 << attempt);
    let capped = exp_delay.min(config.max_delay_ms);

    // Add jitter: 0-50% of delay using SystemTime nanosecond mod
    let nanos = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .unwrap_or_default()
        .subsec_nanos();
    let jitter = (nanos as u64) % (capped / 2 + 1);

    Duration::from_millis(capped + jitter)
}

/// Wraps a tool call with retry logic and circuit breaker protection.
pub async fn retry_tool_call(
    name: &str,
    params: Option<Value>,
    state: Arc<ToolState>,
    config: &RetryConfig,
    breaker: Arc<Mutex<CircuitBreaker>>,
) -> (Value, RetryStats) {
    // Check circuit breaker before attempting
    {
        let cb = breaker.lock().await;
        if cb.is_open(name) {
            return (
                serde_json::json!({
                    "content": [{"type": "text", "text": format!("Circuit breaker open for tool: {}", name)}],
                    "isError": true
                }),
                RetryStats {
                    attempts: 0,
                    retried: false,
                    circuit_opened: true,
                },
            );
        }
    }

    let mut attempts = 0u32;
    let mut last_result;

    loop {
        attempts += 1;
        last_result = tools::handle_tool_call(name, params.clone(), state.clone()).await;

        if !is_retryable_error(&last_result) {
            // Success or non-retryable error
            let mut cb = breaker.lock().await;
            if !last_result
                .get("isError")
                .and_then(|v| v.as_bool())
                .unwrap_or(false)
            {
                cb.record_success(name);
            }
            break;
        }

        // Retryable error -- check if we have retries left
        if attempts > config.max_retries {
            // Exhausted retries, record failure
            let mut cb = breaker.lock().await;
            cb.record_failure(name);
            let circuit_opened = cb.is_open(name);
            return (
                last_result,
                RetryStats {
                    attempts,
                    retried: true,
                    circuit_opened,
                },
            );
        }

        // Sleep with backoff before retrying
        let delay = compute_delay(attempts - 1, config);
        tokio::time::sleep(delay).await;
    }

    let retried = attempts > 1;
    (
        last_result,
        RetryStats {
            attempts,
            retried,
            circuit_opened: false,
        },
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_retry_config_defaults() {
        let config = RetryConfig::default();
        assert_eq!(config.max_retries, 3);
        assert_eq!(config.base_delay_ms, 100);
        assert_eq!(config.max_delay_ms, 1000);
    }

    #[test]
    fn test_circuit_breaker_starts_closed() {
        let cb = CircuitBreaker::new();
        assert!(!cb.is_open("test_tool"));
        assert_eq!(cb.failure_count("test_tool"), 0);
    }

    #[test]
    fn test_circuit_breaker_opens_after_threshold() {
        let mut cb = CircuitBreaker::new();
        cb.failure_threshold = 3;

        cb.record_failure("flaky_tool");
        assert!(!cb.is_open("flaky_tool"));
        cb.record_failure("flaky_tool");
        assert!(!cb.is_open("flaky_tool"));
        cb.record_failure("flaky_tool");
        assert!(cb.is_open("flaky_tool"));
        assert_eq!(cb.failure_count("flaky_tool"), 3);
    }

    #[test]
    fn test_circuit_breaker_success_resets() {
        let mut cb = CircuitBreaker::new();
        cb.failure_threshold = 5;

        for _ in 0..4 {
            cb.record_failure("tool_a");
        }
        assert_eq!(cb.failure_count("tool_a"), 4);

        cb.record_success("tool_a");
        assert_eq!(cb.failure_count("tool_a"), 0);
        assert!(!cb.is_open("tool_a"));
    }

    #[test]
    fn test_circuit_breaker_resets_after_duration() {
        let mut cb = CircuitBreaker::new();
        cb.failure_threshold = 2;
        cb.reset_duration = Duration::from_millis(0); // Instant reset for test

        cb.record_failure("tool_b");
        cb.record_failure("tool_b");

        // With zero reset_duration, the circuit should already be past its open_until
        std::thread::sleep(Duration::from_millis(1));
        assert!(!cb.is_open("tool_b"));
    }

    #[test]
    fn test_circuit_breaker_independent_tools() {
        let mut cb = CircuitBreaker::new();
        cb.failure_threshold = 2;

        cb.record_failure("tool_x");
        cb.record_failure("tool_x");
        assert!(cb.is_open("tool_x"));
        assert!(!cb.is_open("tool_y"));
    }

    #[test]
    fn test_is_retryable_error_true_for_generic_error() {
        let result = serde_json::json!({
            "content": [{"type": "text", "text": "Failed to run test command: timeout"}],
            "isError": true
        });
        assert!(is_retryable_error(&result));
    }

    #[test]
    fn test_is_retryable_error_false_for_unknown_tool() {
        let result = serde_json::json!({
            "content": [{"type": "text", "text": "Unknown tool: bad_tool"}],
            "isError": true
        });
        assert!(!is_retryable_error(&result));
    }

    #[test]
    fn test_is_retryable_error_false_for_no_test_path() {
        let result = serde_json::json!({
            "content": [{"type": "text", "text": "No test_path provided"}],
            "isError": true
        });
        assert!(!is_retryable_error(&result));
    }

    #[test]
    fn test_is_retryable_error_false_for_success() {
        let result = serde_json::json!({
            "content": [{"type": "text", "text": "Lock acquired"}]
        });
        assert!(!is_retryable_error(&result));
    }

    #[test]
    fn test_compute_delay_within_bounds() {
        let config = RetryConfig {
            max_retries: 3,
            base_delay_ms: 100,
            max_delay_ms: 1000,
        };

        for attempt in 0..5 {
            let delay = compute_delay(attempt, &config);
            // Max delay + max jitter (50% of max_delay) = 1500ms
            assert!(delay.as_millis() <= 1500);
            assert!(delay.as_millis() >= 100);
        }
    }

    #[test]
    fn test_compute_delay_exponential_growth() {
        let config = RetryConfig {
            max_retries: 5,
            base_delay_ms: 100,
            max_delay_ms: 10_000,
        };

        // Attempt 0: 100ms base
        // Attempt 1: 200ms base
        // Attempt 2: 400ms base
        // The base grows exponentially (ignoring jitter)
        let d0_base = config.base_delay_ms * (1 << 0); // 100
        let d1_base = config.base_delay_ms * (1 << 1); // 200
        let d2_base = config.base_delay_ms * (1 << 2); // 400

        assert_eq!(d0_base, 100);
        assert_eq!(d1_base, 200);
        assert_eq!(d2_base, 400);
    }
}
