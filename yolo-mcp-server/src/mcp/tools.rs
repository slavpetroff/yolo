use serde_json::{json, Value};
use tokio::fs;
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use tokio::process::Command;

pub struct ToolState {
    locks: Mutex<HashMap<String, String>>, // file_path -> task_id
}

impl ToolState {
    pub fn new() -> Self {
        Self {
            locks: Mutex::new(HashMap::new()),
        }
    }
}

pub async fn handle_tool_call(name: &str, params: Option<Value>, state: Arc<ToolState>) -> Value {
    match name {
        "compile_context" => {
            let phase = params.as_ref().and_then(|p| p.get("phase")).and_then(|p| p.as_i64()).unwrap_or(0);
            
            let mut prefix = String::from("--- GLOBAL PROJECT STATE DO NOT MODIFY PREFIX ---\n");
            
            let files_to_read = vec![
                ".yolo-planning/codebase/ARCHITECTURE.md",
                ".yolo-planning/codebase/STACK.md",
                ".yolo-planning/codebase/CONVENTIONS.md",
                ".yolo-planning/ROADMAP.md",
                ".yolo-planning/REQUIREMENTS.md"
            ];

            for path in files_to_read {
                if let Ok(content) = fs::read_to_string(path).await {
                    prefix.push_str(&format!("\n# {}\n{}\n", path, content));
                }
            }
            
            prefix.push_str("\n--- END GLOBAL STATE ---\n\n--- VOLATILE TAIL ---\n");
            
            // Try to get git diff for volatile tail
            if let Ok(diff) = Command::new("git").arg("diff").arg("HEAD").output().await {
                let diff_str = String::from_utf8_lossy(&diff.stdout);
                if !diff_str.trim().is_empty() {
                    prefix.push_str("Recent Uncommitted Diffs:\n```diff\n");
                    prefix.push_str(&diff_str);
                    prefix.push_str("\n```\n");
                } else {
                    prefix.push_str("No recent file diffs found.\n");
                }
            } else {
                prefix.push_str("No recent file diffs found.\n");
            }
            
            json!({
                "content": [{"type": "text", "text": prefix}]
            })
        }
        "acquire_lock" => {
            let p = params.unwrap_or(json!({}));
            let task_id = p.get("task_id").and_then(|v| v.as_str()).unwrap_or("unknown");
            let file_path = p.get("file_path").and_then(|v| v.as_str()).unwrap_or("unknown");
            
            let mut locks = state.locks.lock().unwrap();
            if let Some(owner) = locks.get(file_path) {
                if owner == task_id {
                    json!({ "content": [{"type": "text", "text": format!("Already hold lock on {}", file_path)}] })
                } else {
                    json!({ "content": [{"type": "text", "text": format!("Conflict: Locked by {}", owner)}], "isError": true })
                }
            } else {
                locks.insert(file_path.to_string(), task_id.to_string());
                json!({ "content": [{"type": "text", "text": format!("Lock acquired for {}", file_path)}] })
            }
        }
        "release_lock" => {
            let p = params.unwrap_or(json!({}));
            let task_id = p.get("task_id").and_then(|v| v.as_str()).unwrap_or("unknown");
            let file_path = p.get("file_path").and_then(|v| v.as_str()).unwrap_or("unknown");
            
            let mut locks = state.locks.lock().unwrap();
            match locks.get(file_path) {
                Some(owner) if owner == task_id => {
                    locks.remove(file_path);
                    json!({ "content": [{"type": "text", "text": format!("Lock released on {}", file_path)}] })
                }
                Some(owner) => {
                    json!({ "content": [{"type": "text", "text": format!("Cannot release: Owned by {}", owner)}], "isError": true })
                }
                None => {
                    // Safe to ignore if not locked
                    json!({ "content": [{"type": "text", "text": "File was not locked"}] })
                }
            }
        }
        "run_test_suite" => {
            let p = params.unwrap_or(json!({}));
            let test_path = p.get("test_path").and_then(|v| v.as_str()).unwrap_or("");
            
            if test_path.is_empty() {
                return json!({ "content": [{"type": "text", "text": "No test_path provided"}], "isError": true });
            }
            
            let output = Command::new("npm")
                .arg("test")
                .arg(test_path)
                .output()
                .await;
                
            match output {
                Ok(out) => {
                    let stdout = String::from_utf8_lossy(&out.stdout);
                    let stderr = String::from_utf8_lossy(&out.stderr);
                    json!({ "content": [{"type": "text", "text": format!("STDOUT:\n{}\nSTDERR:\n{}", stdout, stderr)}] })
                }
                Err(e) => {
                    json!({ "content": [{"type": "text", "text": format!("Failed to run test command: {}", e)}], "isError": true })
                }
            }
        }
        "request_human_approval" => {
            let p = params.unwrap_or(json!({}));
            let plan_path = p.get("plan_path").and_then(|v| v.as_str()).unwrap_or("");
            
            // For MVP, we simulate a HITL pause.
            // In a real Claude deployment, this tool would return a specific text format 
            // that the Claude orchestrator catches as a prompt request.
            json!({ 
                "content": [{
                    "type": "text", 
                    "text": format!("HITL Request Triggered for {}. Execution halted pending vision approval.", plan_path)
                }] 
            })
        }
        _ => json!({ "content": [{"type": "text", "text": format!("Unknown tool: {}", name)}], "isError": true })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[tokio::test]
    async fn test_compile_context_returns_content() {
        let state = Arc::new(ToolState::new());
        let params = Some(json!({"phase": 4}));

        // Use a temp dir to avoid race conditions with parallel tests
        let tmp = std::env::temp_dir().join(format!("yolo-test-compile-ctx-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&tmp);
        std::fs::create_dir_all(tmp.join(".yolo-planning/codebase")).unwrap();
        std::fs::write(tmp.join(".yolo-planning/codebase/ARCHITECTURE.md"), "DUMMY ARCH CONTENT").unwrap();

        let orig_dir = std::env::current_dir().unwrap();
        // Safety: set_current_dir is not unsafe, but affects the process-wide cwd
        let _ = std::env::set_current_dir(&tmp);

        let result = handle_tool_call("compile_context", params, state).await;
        let content_arr = result.get("content").unwrap().as_array().unwrap();
        let text = content_arr[0].get("text").unwrap().as_str().unwrap();

        assert!(text.contains("GLOBAL PROJECT STATE"));
        assert!(text.contains("DUMMY ARCH CONTENT"));

        let _ = std::env::set_current_dir(&orig_dir);
        let _ = std::fs::remove_dir_all(&tmp);
    }

    #[tokio::test]
    async fn test_lock_acquire_and_release() {
        let state = Arc::new(ToolState::new());
        
        // Acquire
        let acq_params = Some(json!({"task_id": "T-01", "file_path": "src/main.rs"}));
        let res1 = handle_tool_call("acquire_lock", acq_params.clone(), state.clone()).await;
        assert!(res1.get("isError").is_none());
        
        // Re-acquire same lock (Already hold lock)
        let res1_repeat = handle_tool_call("acquire_lock", acq_params.clone(), state.clone()).await;
        let repeat_text = res1_repeat.get("content").unwrap().as_array().unwrap()[0].get("text").unwrap().as_str().unwrap();
        assert!(repeat_text.contains("Already hold lock"));

        // Conflict
        let conflict_params = Some(json!({"task_id": "T-02", "file_path": "src/main.rs"}));
        let res2 = handle_tool_call("acquire_lock", conflict_params, state.clone()).await;
        assert_eq!(res2.get("isError").unwrap(), true);
        
        // Release
        let res3 = handle_tool_call("release_lock", acq_params.clone(), state.clone()).await;
        assert!(res3.get("isError").is_none());
        
        // Acquire again with T-02
        let conflict_params = Some(json!({"task_id": "T-02", "file_path": "src/main.rs"}));
        let res4 = handle_tool_call("acquire_lock", conflict_params, state).await;
        assert!(res4.get("isError").is_none());
    }

    #[tokio::test]
    async fn test_request_human_approval() {
        let state = Arc::new(ToolState::new());
        let params = Some(json!({"plan_path": "ROADMAP.md"}));
        
        let result = handle_tool_call("request_human_approval", params, state).await;
        let text = result.get("content").unwrap().as_array().unwrap()[0].get("text").unwrap().as_str().unwrap();
        
        assert!(text.contains("HITL Request Triggered"));
        assert!(text.contains("ROADMAP.md"));
    }

    #[tokio::test]
    async fn test_request_human_approval_missing_param() {
        let state = Arc::new(ToolState::new());
        let result = handle_tool_call("request_human_approval", None, state).await;
        let content = result.get("content").unwrap().as_array().unwrap()[0].get("text").unwrap().as_str().unwrap();
        assert!(content.contains("HITL Request Triggered"));
    }

    #[tokio::test]
    async fn test_run_test_suite_missing_param() {
        let state = Arc::new(ToolState::new());
        let result = handle_tool_call("run_test_suite", Some(json!({})), state.clone()).await;
        assert_eq!(result.get("isError").unwrap(), true);
        
        let result2 = handle_tool_call("run_test_suite", None, state).await;
        assert_eq!(result2.get("isError").unwrap(), true);
    }

    #[tokio::test]
    async fn test_run_test_suite_execution() {
        let state = Arc::new(ToolState::new());
        let params = Some(json!({"test_path": "____nonexistent"}));
        let result = handle_tool_call("run_test_suite", params, state).await;
        
        if result.get("isError").is_some() {
             assert_eq!(result.get("isError").unwrap(), true);
        } else {
             let text = result.get("content").unwrap().as_array().unwrap()[0].get("text").unwrap().as_str().unwrap();
             assert!(text.contains("STDERR") || text.contains("STDOUT"));
        }
    }

    #[tokio::test]
    async fn test_unknown_tool() {
        let state = Arc::new(ToolState::new());
        let result = handle_tool_call("unknown_fake_tool", None, state).await;
        assert_eq!(result.get("isError").unwrap(), true);
    }

    #[tokio::test]
    async fn test_lock_missing_params() {
        let state = Arc::new(ToolState::new());
        let res1 = handle_tool_call("acquire_lock", None, state.clone()).await;
        assert!(res1.get("content").is_some());
        
        let res2 = handle_tool_call("release_lock", None, state).await;
        assert!(res2.get("content").is_some());
    }

    #[tokio::test]
    async fn test_release_lock_unowned() {
        let state = Arc::new(ToolState::new());
        let _ = handle_tool_call("acquire_lock", Some(json!({"task_id": "T-01", "file_path": "f1"})), state.clone()).await;
        
        let res = handle_tool_call("release_lock", Some(json!({"task_id": "T-02", "file_path": "f1"})), state.clone()).await;
        assert_eq!(res.get("isError").unwrap(), true);

        let res2 = handle_tool_call("release_lock", Some(json!({"task_id": "T-02", "file_path": "f2"})), state.clone()).await;
        assert!(res2.get("content").is_some());
    }
}
