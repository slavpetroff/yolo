use std::error::Error;
use std::sync::Arc;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt};
use serde_json::{json, Value};
use crate::mcp::jsonrpc::{IncomingMessage, JsonRpcError, Notification, Request, Response};
use crate::mcp::retry::{self, CircuitBreaker, RetryConfig};
use crate::telemetry::db::TelemetryDb;
use crate::mcp::tools::ToolState;

pub async fn run_server<R: AsyncBufReadExt + Unpin, W: AsyncWriteExt + Unpin + Send + 'static>(
    mut reader: R,
    stdout: W,
    telemetry: Arc<TelemetryDb>,
    tool_state: Arc<ToolState>,
) -> Result<(), Box<dyn Error + Send + Sync>> {
    let circuit_breaker = Arc::new(tokio::sync::Mutex::new(CircuitBreaker::new()));
    let retry_config = RetryConfig::default();
    let (tx, mut rx) = tokio::sync::mpsc::channel::<String>(64);

    // Writer task: drains the channel and writes to stdout sequentially
    let writer_handle = tokio::spawn(async move {
        let mut stdout = stdout;
        while let Some(msg) = rx.recv().await {
            if stdout.write_all(msg.as_bytes()).await.is_err() {
                break;
            }
            if stdout.flush().await.is_err() {
                break;
            }
        }
    });

    let mut line = String::new();
    while reader.read_line(&mut line).await? > 0 {
        if line.trim().is_empty() {
            line.clear();
            continue;
        }

        let input_len = line.len();

        match serde_json::from_str::<IncomingMessage>(&line) {
            Ok(IncomingMessage::Request(req)) => {
                let tel = telemetry.clone();
                let ts = tool_state.clone();
                let resp_tx = tx.clone();
                let cb = circuit_breaker.clone();
                let rc = retry_config.clone();
                tokio::spawn(async move {
                    let response = handle_request(req, tel, ts, input_len, cb, rc).await;
                    if let Ok(response_str) = serde_json::to_string(&response) {
                        let _ = resp_tx.send(response_str + "\n").await;
                    }
                });
            }
            Ok(IncomingMessage::Notification(notif)) => {
                handle_notification(notif).await;
            }
            Ok(IncomingMessage::Response(_res)) => {
                // Not expecting responses from client
            }
            Err(e) => {
                let error_res = json!({
                    "jsonrpc": "2.0",
                    "id": Value::Null,
                    "error": {
                        "code": -32700,
                        "message": format!("Parse error: {}", e)
                    }
                });
                if let Ok(response_str) = serde_json::to_string(&error_res) {
                    let _ = tx.send(response_str + "\n").await;
                }
            }
        }
        line.clear();
    }

    // Drop the sender so the writer task can finish
    drop(tx);
    let _ = writer_handle.await;

    Ok(())
}

async fn handle_request(
    req: Request,
    telemetry: Arc<TelemetryDb>,
    tool_state: Arc<ToolState>,
    input_len: usize,
    circuit_breaker: Arc<tokio::sync::Mutex<CircuitBreaker>>,
    retry_config: RetryConfig,
) -> Response {
    let start_time = std::time::Instant::now();
    let method = req.method.as_str();
    let mut success = true;
    let mut telemetry_name = method.to_string();
    let mut retry_count = 0u32;

    let result = match method {
        "initialize" => {
            Some(json!({
                "protocolVersion": "2024-11-05",
                "capabilities": {
                    "tools": {
                        "listChanged": true
                    }
                },
                "serverInfo": {
                    "name": "yolo-expert-mcp",
                    "version": "1.0.0"
                }
            }))
        }
        "tools/list" => {
            Some(json!({
                "tools": [
                    {
                        "name": "compile_context",
                        "description": "Compiles the global architectural prefix and dynamic agent diff tails.",
                        "inputSchema": {
                            "type": "object",
                            "properties": {
                                "phase": {"type": "integer"},
                                "role": {"type": "string"}
                            },
                            "required": ["phase", "role"]
                        }
                    },
                    {
                        "name": "acquire_lock",
                        "description": "Acquires an exclusive lock on a file.",
                        "inputSchema": {
                            "type": "object",
                            "properties": {
                                "task_id": {"type": "string"},
                                "file_path": {"type": "string"}
                            },
                            "required": ["task_id", "file_path"]
                        }
                    },
                    {
                        "name": "release_lock",
                        "description": "Releases an exclusive lock on a file.",
                        "inputSchema": {
                            "type": "object",
                            "properties": {
                                "task_id": {"type": "string"},
                                "file_path": {"type": "string"}
                            },
                            "required": ["task_id", "file_path"]
                        }
                    },
                    {
                        "name": "run_test_suite",
                        "description": "Executes the native test suite and returns stdout/stderr.",
                        "inputSchema": {
                            "type": "object",
                            "properties": {
                                "test_path": {"type": "string"}
                            },
                            "required": ["test_path"]
                        }
                    },
                    {
                        "name": "request_human_approval",
                        "description": "Halts execution and requests HITL assessment. Writes execution state to .yolo-planning/.execution-state.json with status and approval metadata. Returns structured JSON with `status` (\"paused\") and `approval` fields (requested_at, plan_path, state_file). Requires .yolo-planning/ directory to exist.",
                        "inputSchema": {
                            "type": "object",
                            "properties": {
                                "plan_path": {"type": "string"}
                            },
                            "required": ["plan_path"]
                        }
                    }
                ]
            }))
        }
        "tools/call" => {
            let params = req.params.clone().unwrap_or(json!({}));
            let name = params.get("name").and_then(|v| v.as_str()).unwrap_or("");
            let arguments = params.get("arguments").cloned();

            // Record actual tool name for telemetry instead of generic "tools/call"
            if !name.is_empty() {
                telemetry_name = name.to_string();
            }

            let (tool_res, retry_stats) = retry::retry_tool_call(
                name,
                arguments,
                tool_state.clone(),
                &retry_config,
                circuit_breaker.clone(),
            )
            .await;

            retry_count = retry_stats.attempts.saturating_sub(1);

            if retry_stats.retried {
                eprintln!(
                    "[retry] tool={} attempts={} circuit_opened={}",
                    name, retry_stats.attempts, retry_stats.circuit_opened
                );
            }

            Some(tool_res)
        }
        _ => {
            success = false;
            None
        }
    };

    let response = if let Some(res) = result {
        Response {
            jsonrpc: "2.0".to_string(),
            id: req.id.clone(),
            result: Some(res),
            error: None,
        }
    } else {
        Response {
            jsonrpc: "2.0".to_string(),
            id: req.id.clone(),
            result: None,
            error: Some(JsonRpcError {
                code: -32601,
                message: "Method not found".to_string(),
                data: None,
            }),
        }
    };

    // Compute output byte length from the serialized response
    let output_len = serde_json::to_string(&response).map(|s| s.len()).unwrap_or(0);

    let elapsed = start_time.elapsed().as_millis() as u64;
    let _ = telemetry.record_tool_call_with_retry(
        &telemetry_name,
        None,
        None,
        input_len,
        output_len,
        elapsed,
        success,
        retry_count,
    );

    response
}

async fn handle_notification(notif: Notification) {
    if notif.method == "notifications/initialized" {
        // Client is fully initialized
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_db_path(name: &str) -> std::path::PathBuf {
        std::env::temp_dir().join(format!("yolo-test-{}-{}.db", name, std::process::id()))
    }

    fn default_cb() -> Arc<tokio::sync::Mutex<CircuitBreaker>> {
        Arc::new(tokio::sync::Mutex::new(CircuitBreaker::new()))
    }

    fn default_rc() -> RetryConfig {
        RetryConfig::default()
    }

    #[tokio::test]
    async fn test_handle_initialize() {
        let db_path = temp_db_path("init");
        let _ = std::fs::remove_file(&db_path);
        let telemetry = Arc::new(TelemetryDb::new(db_path.clone()).unwrap());
        let tool_state = Arc::new(ToolState::new());

        let req = Request {
            jsonrpc: "2.0".to_string(),
            id: json!(1),
            method: "initialize".to_string(),
            params: None,
        };

        let response = handle_request(req, telemetry, tool_state, 50, default_cb(), default_rc()).await;
        let result = response.result.unwrap();
        assert_eq!(result.get("serverInfo").unwrap().get("name").unwrap().as_str().unwrap(), "yolo-expert-mcp");
        let _ = std::fs::remove_file(&db_path);
    }

    #[tokio::test]
    async fn test_handle_tools_list() {
        let db_path = temp_db_path("list");
        let _ = std::fs::remove_file(&db_path);
        let telemetry = Arc::new(TelemetryDb::new(db_path.clone()).unwrap());
        let tool_state = Arc::new(ToolState::new());

        let req = Request {
            jsonrpc: "2.0".to_string(),
            id: json!(2),
            method: "tools/list".to_string(),
            params: None,
        };

        let response = handle_request(req, telemetry, tool_state, 48, default_cb(), default_rc()).await;
        let result = response.result.unwrap();
        let tools = result.get("tools").unwrap().as_array().unwrap();
        assert!(tools.len() > 0);
        let _ = std::fs::remove_file(&db_path);
    }

    #[tokio::test]
    async fn test_handle_tools_call() {
        let db_path = temp_db_path("call");
        let _ = std::fs::remove_file(&db_path);
        let telemetry = Arc::new(TelemetryDb::new(db_path.clone()).unwrap());
        let tool_state = Arc::new(ToolState::new());

        let req = Request {
            jsonrpc: "2.0".to_string(),
            id: json!(3),
            method: "tools/call".to_string(),
            params: Some(json!({
                "name": "unknown_tool",
                "arguments": {}
            })),
        };

        let response = handle_request(req, telemetry, tool_state, 80, default_cb(), default_rc()).await;
        let result = response.result.unwrap();
        assert_eq!(result.get("isError").unwrap().as_bool().unwrap(), true);
        let _ = std::fs::remove_file(&db_path);
    }

    #[tokio::test]
    async fn test_handle_unknown_method() {
        let db_path = temp_db_path("unknown");
        let _ = std::fs::remove_file(&db_path);
        let telemetry = Arc::new(TelemetryDb::new(db_path.clone()).unwrap());
        let tool_state = Arc::new(ToolState::new());

        let req = Request {
            jsonrpc: "2.0".to_string(),
            id: json!(4),
            method: "unknown_method".to_string(),
            params: None,
        };

        let response = handle_request(req, telemetry, tool_state, 55, default_cb(), default_rc()).await;
        assert!(response.error.is_some());
        assert_eq!(response.error.unwrap().code, -32601);
        let _ = std::fs::remove_file(&db_path);
    }

    #[tokio::test]
    async fn test_handle_notification_does_not_panic() {
        let notif = Notification {
            jsonrpc: "2.0".to_string(),
            method: "notifications/initialized".to_string(),
            params: None,
        };
        handle_notification(notif).await;

        let notif2 = Notification {
            jsonrpc: "2.0".to_string(),
            method: "unknown".to_string(),
            params: None,
        };
        handle_notification(notif2).await;
    }

    #[tokio::test]
    async fn test_run_server() {
        let db_path = temp_db_path("loop");
        let _ = std::fs::remove_file(&db_path);
        let telemetry = Arc::new(TelemetryDb::new(db_path.clone()).unwrap());
        let tool_state = Arc::new(ToolState::new());

        let input_data = "{\"jsonrpc\": \"2.0\", \"id\": 1, \"method\": \"initialize\"}\n\
                          {\"jsonrpc\": \"2.0\", \"method\": \"notifications/initialized\"}\n\
                          {\"jsonrpc\": \"2.0\", \"result\": {}}\n\
                          invalid json\n\
                          \n";

        let reader = tokio::io::BufReader::new(input_data.as_bytes());
        let (writer, mut read_half) = tokio::io::duplex(8192);

        let server_handle = tokio::spawn(async move {
            run_server(reader, writer, telemetry, tool_state).await
        });

        // Read all output from the server
        let mut output_buf = Vec::new();
        tokio::io::AsyncReadExt::read_to_end(&mut read_half, &mut output_buf).await.unwrap();

        let res = server_handle.await.unwrap();
        assert!(res.is_ok());

        let output = String::from_utf8(output_buf).unwrap();
        assert!(output.contains("yolo-expert-mcp"));
        assert!(output.contains("-32700"));

        let _ = std::fs::remove_file(&db_path);
    }

    #[tokio::test]
    async fn test_concurrent_requests() {
        let db_path = temp_db_path("concurrent");
        let _ = std::fs::remove_file(&db_path);
        let telemetry = Arc::new(TelemetryDb::new(db_path.clone()).unwrap());
        let tool_state = Arc::new(ToolState::new());

        // Send multiple requests that will be dispatched concurrently
        let mut input = String::new();
        for i in 1..=5 {
            input.push_str(&format!(
                "{{\"jsonrpc\": \"2.0\", \"id\": {}, \"method\": \"initialize\"}}\n",
                i
            ));
        }

        let (mut input_writer, input_reader) = tokio::io::duplex(8192);
        let reader = tokio::io::BufReader::new(input_reader);
        let (writer, mut read_half) = tokio::io::duplex(8192);

        // Write all input then close
        tokio::io::AsyncWriteExt::write_all(&mut input_writer, input.as_bytes()).await.unwrap();
        drop(input_writer);

        let server_handle = tokio::spawn(async move {
            run_server(reader, writer, telemetry, tool_state).await
        });

        let mut output_buf = Vec::new();
        tokio::io::AsyncReadExt::read_to_end(&mut read_half, &mut output_buf).await.unwrap();

        let res = server_handle.await.unwrap();
        assert!(res.is_ok());

        let output = String::from_utf8(output_buf).unwrap();

        // All 5 responses must be present (each is a separate JSON line)
        let response_lines: Vec<&str> = output.lines().filter(|l| !l.trim().is_empty()).collect();
        assert_eq!(response_lines.len(), 5, "Expected 5 responses, got {}", response_lines.len());

        // Each response should be valid JSON with a result
        for line in &response_lines {
            let parsed: Value = serde_json::from_str(line).expect("Response line should be valid JSON");
            assert!(parsed.get("result").is_some());
        }

        let _ = std::fs::remove_file(&db_path);
    }

    #[tokio::test]
    async fn test_telemetry_records_byte_lengths() {
        let db_path = temp_db_path("telemetry-bytes");
        let _ = std::fs::remove_file(&db_path);
        let telemetry = Arc::new(TelemetryDb::new(db_path.clone()).unwrap());
        let tool_state = Arc::new(ToolState::new());

        let input_line = r#"{"jsonrpc": "2.0", "id": 1, "method": "initialize"}"#;
        let input_len = input_line.len();

        let req = Request {
            jsonrpc: "2.0".to_string(),
            id: json!(1),
            method: "initialize".to_string(),
            params: None,
        };

        let _ = handle_request(req, telemetry.clone(), tool_state, input_len, default_cb(), default_rc()).await;

        // Query the telemetry DB file directly via rusqlite
        let conn = rusqlite::Connection::open(&db_path).unwrap();
        let row: (i64, i64) = conn.query_row(
            "SELECT input_length, output_length FROM tool_usage ORDER BY id DESC LIMIT 1",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        ).expect("Should have a telemetry record");

        assert!(row.0 > 0, "input_length should be > 0, got {}", row.0);
        assert!(row.1 > 0, "output_length should be > 0, got {}", row.1);
        assert_eq!(row.0, input_len as i64);

        let _ = std::fs::remove_file(&db_path);
    }

    #[tokio::test]
    async fn test_telemetry_records_tool_name() {
        let db_path = temp_db_path("telemetry-name");
        let _ = std::fs::remove_file(&db_path);
        let telemetry = Arc::new(TelemetryDb::new(db_path.clone()).unwrap());
        let tool_state = Arc::new(ToolState::new());

        let req = Request {
            jsonrpc: "2.0".to_string(),
            id: json!(5),
            method: "tools/call".to_string(),
            params: Some(json!({
                "name": "acquire_lock",
                "arguments": {"task_id": "T-99", "file_path": "test.rs"}
            })),
        };

        let _ = handle_request(req, telemetry.clone(), tool_state, 100, default_cb(), default_rc()).await;

        // Query the telemetry DB file directly via rusqlite
        let conn = rusqlite::Connection::open(&db_path).unwrap();
        let tool_name: String = conn.query_row(
            "SELECT tool_name FROM tool_usage ORDER BY id DESC LIMIT 1",
            [],
            |row| row.get(0),
        ).expect("Should have a telemetry record");

        assert_eq!(tool_name, "acquire_lock");

        let _ = std::fs::remove_file(&db_path);
    }

    // --- Integration tests for retry and circuit breaker ---

    #[tokio::test]
    async fn test_non_retryable_error_not_retried() {
        // "Unknown tool" errors should NOT be retried
        let db_path = temp_db_path("retry-nonretry");
        let _ = std::fs::remove_file(&db_path);
        let telemetry = Arc::new(TelemetryDb::new(db_path.clone()).unwrap());
        let tool_state = Arc::new(ToolState::new());

        let req = Request {
            jsonrpc: "2.0".to_string(),
            id: json!(10),
            method: "tools/call".to_string(),
            params: Some(json!({
                "name": "nonexistent_tool",
                "arguments": {}
            })),
        };

        let _ = handle_request(req, telemetry.clone(), tool_state, 80, default_cb(), default_rc()).await;

        let conn = rusqlite::Connection::open(&db_path).unwrap();
        let retry_count: i64 = conn.query_row(
            "SELECT retry_count FROM tool_usage ORDER BY id DESC LIMIT 1",
            [],
            |row| row.get(0),
        ).unwrap();

        assert_eq!(retry_count, 0, "Non-retryable errors should have retry_count=0");

        let _ = std::fs::remove_file(&db_path);
    }

    #[tokio::test]
    async fn test_retry_telemetry_records_zero_for_success() {
        // Successful tool calls should have retry_count=0
        let db_path = temp_db_path("retry-success-tel");
        let _ = std::fs::remove_file(&db_path);
        let telemetry = Arc::new(TelemetryDb::new(db_path.clone()).unwrap());
        let tool_state = Arc::new(ToolState::new());

        let req = Request {
            jsonrpc: "2.0".to_string(),
            id: json!(11),
            method: "tools/call".to_string(),
            params: Some(json!({
                "name": "acquire_lock",
                "arguments": {"task_id": "T-01", "file_path": "test.rs"}
            })),
        };

        let _ = handle_request(req, telemetry.clone(), tool_state, 100, default_cb(), default_rc()).await;

        let conn = rusqlite::Connection::open(&db_path).unwrap();
        let retry_count: i64 = conn.query_row(
            "SELECT retry_count FROM tool_usage ORDER BY id DESC LIMIT 1",
            [],
            |row| row.get(0),
        ).unwrap();

        assert_eq!(retry_count, 0, "Successful calls should have retry_count=0");

        let _ = std::fs::remove_file(&db_path);
    }

    #[tokio::test]
    async fn test_circuit_breaker_returns_error_when_open() {
        // Directly test that circuit breaker blocks calls when open
        let tool_state = Arc::new(ToolState::new());
        let config = RetryConfig { max_retries: 0, base_delay_ms: 1, max_delay_ms: 1 };
        let cb = Arc::new(tokio::sync::Mutex::new(CircuitBreaker::new()));

        // Manually open the circuit breaker for a tool
        {
            let mut breaker = cb.lock().await;
            breaker.failure_threshold = 1;
            breaker.record_failure("acquire_lock");
        }

        let (result, stats) = retry::retry_tool_call(
            "acquire_lock",
            Some(json!({"task_id": "T-01", "file_path": "test.rs"})),
            tool_state,
            &config,
            cb,
        ).await;

        assert_eq!(result.get("isError").unwrap().as_bool().unwrap(), true);
        let text = result["content"][0]["text"].as_str().unwrap();
        assert!(text.contains("Circuit breaker open"), "Expected circuit breaker message, got: {}", text);
        assert_eq!(stats.attempts, 0);
        assert!(stats.circuit_opened);
    }

    #[tokio::test]
    async fn test_retry_with_lock_conflict() {
        // acquire_lock conflict returns isError:true with "Conflict: Locked by" which IS retryable
        let tool_state = Arc::new(ToolState::new());
        let config = RetryConfig { max_retries: 2, base_delay_ms: 1, max_delay_ms: 1 };
        let cb = Arc::new(tokio::sync::Mutex::new(CircuitBreaker::new()));

        // First acquire the lock with T-01
        let _ = crate::mcp::tools::handle_tool_call(
            "acquire_lock",
            Some(json!({"task_id": "T-01", "file_path": "contested.rs"})),
            tool_state.clone(),
        ).await;

        // Now try to acquire with T-02 -- this will fail with retryable error each time
        let (result, stats) = retry::retry_tool_call(
            "acquire_lock",
            Some(json!({"task_id": "T-02", "file_path": "contested.rs"})),
            tool_state,
            &config,
            cb,
        ).await;

        assert_eq!(result.get("isError").unwrap().as_bool().unwrap(), true);
        assert!(stats.retried, "Lock conflict should trigger retries");
        // max_retries=2 means up to 3 total attempts (1 initial + 2 retries)
        assert_eq!(stats.attempts, 3, "Should have 3 attempts (1 + 2 retries)");
    }

    #[tokio::test]
    async fn test_circuit_breaker_opens_after_consecutive_failures() {
        let tool_state = Arc::new(ToolState::new());
        let config = RetryConfig { max_retries: 0, base_delay_ms: 1, max_delay_ms: 1 };
        let cb = Arc::new(tokio::sync::Mutex::new(CircuitBreaker::new()));

        // Set threshold low for test
        {
            let mut breaker = cb.lock().await;
            breaker.failure_threshold = 3;
        }

        // First acquire the lock with T-01 to create conflict
        let _ = crate::mcp::tools::handle_tool_call(
            "acquire_lock",
            Some(json!({"task_id": "T-01", "file_path": "cb-test.rs"})),
            tool_state.clone(),
        ).await;

        // Make 3 failing calls (max_retries=0 so each is 1 attempt + immediate failure recorded)
        for i in 0..3 {
            let (result, _) = retry::retry_tool_call(
                "acquire_lock",
                Some(json!({"task_id": "T-02", "file_path": "cb-test.rs"})),
                tool_state.clone(),
                &config,
                cb.clone(),
            ).await;
            assert_eq!(result.get("isError").unwrap().as_bool().unwrap(), true, "Call {} should fail", i);
        }

        // Circuit should now be open
        let breaker = cb.lock().await;
        assert!(breaker.is_open("acquire_lock"), "Circuit breaker should be open after 3 failures");
    }

    #[tokio::test]
    async fn test_input_validation_errors_not_retried() {
        // "No test_path" errors should NOT be retried
        let tool_state = Arc::new(ToolState::new());
        let config = RetryConfig { max_retries: 3, base_delay_ms: 1, max_delay_ms: 1 };
        let cb = Arc::new(tokio::sync::Mutex::new(CircuitBreaker::new()));

        let (result, stats) = retry::retry_tool_call(
            "run_test_suite",
            Some(json!({})),
            tool_state,
            &config,
            cb,
        ).await;

        assert_eq!(result.get("isError").unwrap().as_bool().unwrap(), true);
        assert_eq!(stats.attempts, 1, "Input validation error should not be retried");
        assert!(!stats.retried);
    }
}
