use std::error::Error;
use std::sync::Arc;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt};
use serde_json::{json, Value};
use crate::mcp::jsonrpc::{IncomingMessage, JsonRpcError, Notification, Request, Response};
use crate::telemetry::db::TelemetryDb;
use crate::mcp::tools::{self, ToolState};

pub async fn run_server<R: AsyncBufReadExt + Unpin, W: AsyncWriteExt + Unpin>(
    mut reader: R,
    mut stdout: W,
    telemetry: Arc<TelemetryDb>,
    tool_state: Arc<ToolState>,
) -> Result<(), Box<dyn Error>> {
    let mut line = String::new();
    while reader.read_line(&mut line).await? > 0 {
        if line.trim().is_empty() {
            line.clear();
            continue;
        }

        match serde_json::from_str::<IncomingMessage>(&line) {
            Ok(IncomingMessage::Request(req)) => {
                let response = handle_request(req, telemetry.clone(), tool_state.clone()).await;
                let response_str = serde_json::to_string(&response)? + "\n";
                stdout.write_all(response_str.as_bytes()).await?;
                stdout.flush().await?;
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
                let response_str = serde_json::to_string(&error_res)? + "\n";
                stdout.write_all(response_str.as_bytes()).await?;
                stdout.flush().await?;
            }
        }
        line.clear();
    }
    Ok(())
}

async fn handle_request(req: Request, telemetry: Arc<TelemetryDb>, tool_state: Arc<ToolState>) -> Response {
    let start_time = std::time::Instant::now();
    let method = req.method.as_str();
    let mut success = true;

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
                        "description": "Halts execution and requests HITL assessment.",
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
            
            let tool_res = tools::handle_tool_call(name, arguments, tool_state.clone()).await;
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

    let elapsed = start_time.elapsed().as_millis() as u64;
    let _ = telemetry.record_tool_call(
        method, 
        None, 
        None, 
        0, 
        0, 
        elapsed, 
        success
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

        let response = handle_request(req, telemetry, tool_state).await;
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

        let response = handle_request(req, telemetry, tool_state).await;
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

        let response = handle_request(req, telemetry, tool_state).await;
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

        let response = handle_request(req, telemetry, tool_state).await;
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
        let mut writer = Vec::new();

        let res = run_server(reader, &mut writer, telemetry, tool_state).await;
        assert!(res.is_ok());

        let output = String::from_utf8(writer).unwrap();
        assert!(output.contains("yolo-expert-mcp"));
        assert!(output.contains("-32700"));

        let _ = std::fs::remove_file(&db_path);
    }
}
