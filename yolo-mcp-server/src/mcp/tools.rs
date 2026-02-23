use serde_json::{json, Value};
use std::collections::HashMap;
use std::path::Path;
use std::process::Output;
use std::sync::{Arc, Mutex};
use tokio::process::Command;
use tokio::time::{timeout, Duration};

use crate::commands::tier_context;

pub struct ToolState {
    locks: Mutex<HashMap<String, String>>, // file_path -> task_id
    last_prefix_hashes: Mutex<HashMap<String, String>>, // role -> last prefix_hash
}

impl ToolState {
    pub fn new() -> Self {
        Self {
            locks: Mutex::new(HashMap::new()),
            last_prefix_hashes: Mutex::new(HashMap::new()),
        }
    }
}

/// Default command timeout in milliseconds (30 seconds).
const DEFAULT_TIMEOUT_MS: u64 = 30_000;

/// Spawn a command with a timeout. On timeout, kill the child and return an error.
async fn run_command_with_timeout(cmd: &mut Command, timeout_ms: u64) -> Result<Output, String> {
    let child = cmd.kill_on_drop(true).spawn().map_err(|e| format!("Failed to spawn command: {}", e))?;
    match timeout(Duration::from_millis(timeout_ms), child.wait_with_output()).await {
        Ok(Ok(output)) => Ok(output),
        Ok(Err(e)) => Err(format!("Command failed: {}", e)),
        Err(_) => {
            // Timeout elapsed — child is killed on drop via kill_on_drop(true)
            Err(format!("Command timed out after {}ms", timeout_ms))
        }
    }
}

pub async fn handle_tool_call(name: &str, params: Option<Value>, state: Arc<ToolState>) -> Value {
    match name {
        "compile_context" => {
            let phase = params.as_ref().and_then(|p| p.get("phase")).and_then(|p| p.as_i64()).unwrap_or(0);
            let role = params.as_ref()
                .and_then(|p| p.get("role"))
                .and_then(|r| r.as_str())
                .unwrap_or("default");

            // Build tiered context using the tier_context module
            let planning_dir = Path::new(".yolo-planning");
            let phases_dir = planning_dir.join("phases");
            let mut ctx = tier_context::build_tiered_context(
                planning_dir,
                role,
                phase,
                Some(&phases_dir),
                None,
            );

            // Append async git diff to tier3 (async operation not available in sync tier builder)
            if let Ok(diff) = Command::new("git").arg("diff").arg("HEAD").output().await {
                let diff_str = String::from_utf8_lossy(&diff.stdout);
                if !diff_str.trim().is_empty() {
                    ctx.tier3.push_str("Recent Uncommitted Diffs:\n```diff\n");
                    ctx.tier3.push_str(&diff_str);
                    ctx.tier3.push_str("\n```\n");
                } else {
                    ctx.tier3.push_str("No recent file diffs found.\n");
                }
            } else {
                ctx.tier3.push_str("No recent file diffs found.\n");
            }

            ctx.tier3.push_str("\n--- END COMPILED CONTEXT ---\n");

            // Capture tier sizes before recomputing combined
            let tier1_size = ctx.tier1.len();
            let tier2_size = ctx.tier2.len();
            let tier3_size = ctx.tier3.len();
            let total_size = tier1_size + tier2_size + tier3_size;

            // Backward-compatible stable_prefix = tier1 + "\n" + tier2
            let stable_prefix = format!("{}\n{}", ctx.tier1, ctx.tier2);
            let prefix_hash = tier_context::sha256_of(&stable_prefix);
            let prefix_bytes = stable_prefix.len();
            let volatile_bytes = ctx.tier3.len();

            // Determine cache hit/miss by comparing prefix_hash to previous call for this role
            let (cache_hit, cache_read_tokens_estimate, cache_write_tokens_estimate) = {
                let mut hashes = state.last_prefix_hashes.lock().unwrap();
                let prev = hashes.get(role).cloned();
                hashes.insert(role.to_string(), prefix_hash.clone());
                match prev {
                    Some(ref old_hash) if old_hash == &prefix_hash => {
                        (true, prefix_bytes, 0usize)
                    }
                    _ => {
                        (false, 0usize, prefix_bytes)
                    }
                }
            };

            let input_tokens_estimate = prefix_bytes + volatile_bytes;

            // Build structured metadata and append as trailing comment
            let meta = json!({
                "ok": true,
                "cmd": "compile-context",
                "tier1_size": tier1_size,
                "tier2_size": tier2_size,
                "tier3_size": tier3_size,
                "total_size": total_size,
                "cache_hit": cache_hit,
                "output_path": ".yolo-planning",
                "role": role,
                "phase": phase
            });
            let meta_str = serde_json::to_string(&meta).unwrap_or_default();

            // Recompute combined after appending git diff + meta comment
            ctx.combined = format!("{}\n{}\n{}\n<!-- compile_context_meta: {} -->",
                ctx.tier1, ctx.tier2, ctx.tier3, meta_str);

            json!({
                "content": [{"type": "text", "text": ctx.combined}],
                "tier1_prefix": ctx.tier1,
                "tier2_prefix": ctx.tier2,
                "volatile_tail": ctx.tier3,
                "tier1_hash": ctx.tier1_hash,
                "tier2_hash": ctx.tier2_hash,
                "stable_prefix": stable_prefix,
                "prefix_hash": prefix_hash,
                "prefix_bytes": prefix_bytes,
                "volatile_bytes": volatile_bytes,
                "input_tokens_estimate": input_tokens_estimate,
                "cache_hit": cache_hit,
                "tier1_size": tier1_size,
                "tier2_size": tier2_size,
                "tier3_size": tier3_size,
                "total_size": total_size,
                "cache_read_tokens_estimate": cache_read_tokens_estimate,
                "cache_write_tokens_estimate": cache_write_tokens_estimate
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
            
            // Auto-detect test runner from project context
            let mut cmd = if Path::new("Cargo.toml").exists() {
                let mut c = Command::new("cargo");
                c.arg("test");
                if !test_path.is_empty() {
                    c.arg("--").arg(test_path);
                }
                c
            } else if Path::new("tests").is_dir() && has_bats_files("tests") {
                let mut c = Command::new("bats");
                c.arg(test_path);
                c
            } else if Path::new("pytest.ini").exists() || has_pytest_config() {
                let mut c = Command::new("pytest");
                c.arg(test_path);
                c
            } else if Path::new("package.json").exists() {
                let mut c = Command::new("npm");
                c.arg("test").arg("--").arg(test_path);
                c
            } else {
                return json!({ "content": [{"type": "text", "text": "No test runner detected. Looked for: Cargo.toml, tests/*.bats, pytest.ini/pyproject.toml, package.json"}], "isError": true });
            };

            let output = cmd.output().await;
                
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

/// Check if a directory contains .bats test files.
fn has_bats_files(dir: &str) -> bool {
    if let Ok(entries) = std::fs::read_dir(dir) {
        for entry in entries.flatten() {
            if entry.path().extension().is_some_and(|e| e == "bats") {
                return true;
            }
        }
    }
    false
}

/// Check if pyproject.toml contains a [tool.pytest] section.
fn has_pytest_config() -> bool {
    if let Ok(content) = std::fs::read_to_string("pyproject.toml") {
        return content.contains("[tool.pytest");
    }
    false
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    // Serialize tests that change process-wide cwd to avoid race conditions.
    static CWD_MUTEX: std::sync::Mutex<()> = std::sync::Mutex::new(());

    /// RAII guard that restores the working directory on drop (even on panic).
    /// Must be created AFTER acquiring CWD_MUTEX so it drops BEFORE the mutex guard.
    struct CwdGuard(std::path::PathBuf);
    impl Drop for CwdGuard {
        fn drop(&mut self) {
            let _ = std::env::set_current_dir(&self.0);
        }
    }

    /// Acquire the CWD mutex (handles poison from prior panics) and save/restore cwd.
    fn lock_and_chdir(target: &std::path::Path) -> (std::sync::MutexGuard<'static, ()>, CwdGuard) {
        let guard = CWD_MUTEX.lock().unwrap_or_else(|e| e.into_inner());
        let orig = std::env::current_dir().expect("cwd must be valid when mutex is held");
        let cwd_guard = CwdGuard(orig);
        std::env::set_current_dir(target).expect("failed to chdir to temp dir");
        (guard, cwd_guard)
    }

    #[tokio::test]
    async fn test_compile_context_returns_content() {
        let tmp = std::env::temp_dir().join(format!("yolo-test-compile-ctx-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&tmp);
        std::fs::create_dir_all(tmp.join(".yolo-planning/codebase")).unwrap();
        std::fs::write(tmp.join(".yolo-planning/codebase/ARCHITECTURE.md"), "DUMMY ARCH CONTENT").unwrap();

        let (_lock, _cwd) = lock_and_chdir(&tmp);
        // Clear global tier cache after acquiring lock to avoid races
        let _ = tier_context::invalidate_tier_cache();
        let state = Arc::new(ToolState::new());
        let params = Some(json!({"phase": 4, "role": "architect"}));

        let result = handle_tool_call("compile_context", params, state).await;
        let content_arr = result.get("content").unwrap().as_array().unwrap();
        let text = content_arr[0].get("text").unwrap().as_str().unwrap();

        // Combined text contains tier headers and content
        assert!(text.contains("TIER 1: SHARED BASE"));
        assert!(text.contains("TIER 2: ROLE FAMILY (planning)"));
        assert!(text.contains("DUMMY ARCH CONTENT"));

        // Verify backward-compat and new tier fields
        assert!(result.get("stable_prefix").is_some());
        assert!(result.get("volatile_tail").is_some());
        assert!(result.get("prefix_hash").is_some());
        assert!(result.get("prefix_bytes").is_some());
        assert!(result.get("tier1_prefix").is_some());
        assert!(result.get("tier2_prefix").is_some());
        assert!(result.get("tier1_hash").is_some());
        assert!(result.get("tier2_hash").is_some());

        let tier1 = result["tier1_prefix"].as_str().unwrap();
        let tier2 = result["tier2_prefix"].as_str().unwrap();
        let stable = result["stable_prefix"].as_str().unwrap();
        let volatile = result["volatile_tail"].as_str().unwrap();

        // Tier 1 has shared base header, tier 2 has role family header
        assert!(tier1.contains("TIER 1: SHARED BASE"));
        assert!(tier2.contains("TIER 2: ROLE FAMILY (planning)"));
        // stable_prefix = tier1 + "\n" + tier2
        assert_eq!(stable, &format!("{}\n{}", tier1, tier2));
        // Volatile tail contains tier 3 header
        assert!(volatile.contains("TIER 3: VOLATILE TAIL (phase=4)"));
        // Architecture content is in tier 2 for planning family
        assert!(tier2.contains("DUMMY ARCH CONTENT"));

        // Verify structured metadata comment in combined text
        assert!(text.contains("<!-- compile_context_meta:"));
        // Verify tier size fields in response
        assert!(result.get("tier1_size").is_some());
        assert!(result.get("tier2_size").is_some());
        assert!(result.get("tier3_size").is_some());
        assert!(result.get("total_size").is_some());
        assert!(result.get("cache_hit").is_some());
        let total = result["total_size"].as_u64().unwrap();
        let t1 = result["tier1_size"].as_u64().unwrap();
        let t2 = result["tier2_size"].as_u64().unwrap();
        let t3 = result["tier3_size"].as_u64().unwrap();
        assert_eq!(total, t1 + t2 + t3);

        let _ = std::fs::remove_dir_all(&tmp);
    }

    #[tokio::test]
    async fn test_compile_context_token_estimates() {
        let tmp = std::env::temp_dir().join(format!("yolo-test-token-est-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&tmp);
        std::fs::create_dir_all(tmp.join(".yolo-planning/codebase")).unwrap();
        std::fs::write(tmp.join(".yolo-planning/codebase/CONVENTIONS.md"), "CONV").unwrap();

        let (_lock, _cwd) = lock_and_chdir(&tmp);
        let _ = tier_context::invalidate_tier_cache();
        let state = Arc::new(ToolState::new());
        let params = Some(json!({"phase": 1, "role": "dev"}));

        let result = handle_tool_call("compile_context", params, state).await;

        // Verify token estimate fields exist
        assert!(result.get("input_tokens_estimate").is_some());
        assert!(result.get("cache_read_tokens_estimate").is_some());
        assert!(result.get("cache_write_tokens_estimate").is_some());
        assert!(result.get("volatile_bytes").is_some());

        let input_est = result["input_tokens_estimate"].as_u64().unwrap();
        let prefix_bytes = result["prefix_bytes"].as_u64().unwrap();
        let volatile_bytes = result["volatile_bytes"].as_u64().unwrap();
        assert_eq!(input_est, prefix_bytes + volatile_bytes);

        // prefix_bytes = tier1.len() + tier2.len() + 1 (newline separator)
        let tier1 = result["tier1_prefix"].as_str().unwrap();
        let tier2 = result["tier2_prefix"].as_str().unwrap();
        assert_eq!(prefix_bytes as usize, tier1.len() + tier2.len() + 1);

        // First call should be cache write (no previous hash)
        assert_eq!(result["cache_hit"].as_bool().unwrap(), false);
        assert_eq!(result["cache_read_tokens_estimate"].as_u64().unwrap(), 0);
        assert!(result["cache_write_tokens_estimate"].as_u64().unwrap() > 0);

        let _ = std::fs::remove_dir_all(&tmp);
    }

    #[tokio::test]
    async fn test_compile_context_cache_hit_on_second_call() {
        let tmp = std::env::temp_dir().join(format!("yolo-test-cache-hit-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&tmp);
        std::fs::create_dir_all(tmp.join(".yolo-planning/codebase")).unwrap();
        std::fs::write(tmp.join(".yolo-planning/codebase/CONVENTIONS.md"), "CONV").unwrap();

        let (_lock, _cwd) = lock_and_chdir(&tmp);
        let _ = tier_context::invalidate_tier_cache();
        let state = Arc::new(ToolState::new());
        let params = Some(json!({"phase": 1, "role": "dev"}));

        // First call
        let r1 = handle_tool_call("compile_context", params.clone(), state.clone()).await;
        let hash1 = r1["prefix_hash"].as_str().unwrap().to_string();
        assert_eq!(r1["cache_hit"].as_bool().unwrap(), false);

        // Second call with same role — prefix_hash should match
        let r2 = handle_tool_call("compile_context", params, state).await;
        let hash2 = r2["prefix_hash"].as_str().unwrap().to_string();

        assert_eq!(hash1, hash2);
        assert_eq!(r2["cache_hit"].as_bool().unwrap(), true);

        // Second call should be cache read
        assert!(r2["cache_read_tokens_estimate"].as_u64().unwrap() > 0);
        assert_eq!(r2["cache_write_tokens_estimate"].as_u64().unwrap(), 0);

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

    #[tokio::test]
    async fn test_compile_context_role_filtering() {
        let tmp = std::env::temp_dir().join(format!("yolo-test-role-filter-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&tmp);
        std::fs::create_dir_all(tmp.join(".yolo-planning/codebase")).unwrap();
        std::fs::write(tmp.join(".yolo-planning/codebase/ARCHITECTURE.md"), "ARCH_CONTENT_MARKER").unwrap();
        std::fs::write(tmp.join(".yolo-planning/codebase/STACK.md"), "STACK_CONTENT_MARKER").unwrap();
        std::fs::write(tmp.join(".yolo-planning/codebase/CONVENTIONS.md"), "CONV_CONTENT_MARKER").unwrap();
        std::fs::write(tmp.join(".yolo-planning/codebase/ROADMAP.md"), "ROADMAP_CONTENT_MARKER").unwrap();

        std::fs::write(tmp.join(".yolo-planning/codebase/REQUIREMENTS.md"), "REQ_CONTENT_MARKER").unwrap();

        let (_lock, _cwd) = lock_and_chdir(&tmp);
        // Clear global tier cache after acquiring lock to avoid races
        let _ = tier_context::invalidate_tier_cache();
        let state = Arc::new(ToolState::new());

        // Dev (execution family): tier1=CONVENTIONS+STACK, tier2=ROADMAP only
        let dev_result = handle_tool_call("compile_context", Some(json!({"phase": 0, "role": "dev"})), state.clone()).await;
        let dev_tier1 = dev_result["tier1_prefix"].as_str().unwrap();
        let dev_tier2 = dev_result["tier2_prefix"].as_str().unwrap();
        // Tier 1: CONVENTIONS + STACK (shared base for all roles)
        assert!(dev_tier1.contains("CONV_CONTENT_MARKER"));
        assert!(dev_tier1.contains("STACK_CONTENT_MARKER"));
        // Tier 2 execution: ROADMAP only
        assert!(dev_tier2.contains("ROADMAP_CONTENT_MARKER"));
        assert!(!dev_tier2.contains("ARCH_CONTENT_MARKER"));
        assert!(!dev_tier2.contains("REQ_CONTENT_MARKER"));

        // Architect (planning family): tier1=CONVENTIONS+STACK, tier2=ARCHITECTURE+ROADMAP+REQUIREMENTS
        let arch_result = handle_tool_call("compile_context", Some(json!({"phase": 0, "role": "architect"})), state.clone()).await;
        let arch_tier1 = arch_result["tier1_prefix"].as_str().unwrap();
        let arch_tier2 = arch_result["tier2_prefix"].as_str().unwrap();
        assert!(arch_tier1.contains("CONV_CONTENT_MARKER"));
        assert!(arch_tier1.contains("STACK_CONTENT_MARKER"));
        assert!(arch_tier2.contains("ARCH_CONTENT_MARKER"));
        assert!(arch_tier2.contains("ROADMAP_CONTENT_MARKER"));
        assert!(arch_tier2.contains("REQ_CONTENT_MARKER"));

        // QA (execution family): same tier structure as dev
        let qa_result = handle_tool_call("compile_context", Some(json!({"phase": 0, "role": "qa"})), state.clone()).await;
        let qa_tier1 = qa_result["tier1_prefix"].as_str().unwrap();
        let qa_tier2 = qa_result["tier2_prefix"].as_str().unwrap();
        assert!(qa_tier1.contains("CONV_CONTENT_MARKER"));
        assert!(qa_tier1.contains("STACK_CONTENT_MARKER"));
        assert!(qa_tier2.contains("ROADMAP_CONTENT_MARKER"));
        assert!(!qa_tier2.contains("ARCH_CONTENT_MARKER"));

        let _ = std::fs::remove_dir_all(&tmp);
    }

    #[tokio::test]
    async fn test_compile_context_phase_filtering() {
        let tmp = std::env::temp_dir().join(format!("yolo-test-phase-filter-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&tmp);
        std::fs::create_dir_all(tmp.join(".yolo-planning/codebase")).unwrap();
        std::fs::create_dir_all(tmp.join(".yolo-planning/phases/03")).unwrap();
        std::fs::write(tmp.join(".yolo-planning/codebase/CONVENTIONS.md"), "CONV").unwrap();
        std::fs::write(tmp.join(".yolo-planning/phases/03/03-01-PLAN.md"), "PHASE3_PLAN_CONTENT").unwrap();

        let (_lock, _cwd) = lock_and_chdir(&tmp);
        let _ = tier_context::invalidate_tier_cache();
        let state = Arc::new(ToolState::new());

        // Phase 3 should include the plan file
        let result = handle_tool_call("compile_context", Some(json!({"phase": 3, "role": "dev"})), state.clone()).await;
        let text = result["content"][0]["text"].as_str().unwrap();
        assert!(text.contains("PHASE3_PLAN_CONTENT"));
        assert!(text.contains("Phase 3 Plan"));

        // Phase 0 should NOT include the plan file
        let result0 = handle_tool_call("compile_context", Some(json!({"phase": 0, "role": "dev"})), state.clone()).await;
        let text0 = result0["content"][0]["text"].as_str().unwrap();
        assert!(!text0.contains("PHASE3_PLAN_CONTENT"));

        let _ = std::fs::remove_dir_all(&tmp);
    }

    #[tokio::test]
    async fn test_run_test_suite_detects_cargo() {
        let tmp = std::env::temp_dir().join(format!("yolo-test-cargo-detect-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&tmp);
        std::fs::create_dir_all(&tmp).unwrap();
        std::fs::write(tmp.join("Cargo.toml"), "[package]\nname = \"test\"").unwrap();

        let (_lock, _cwd) = lock_and_chdir(&tmp);
        let state = Arc::new(ToolState::new());

        let result = handle_tool_call("run_test_suite", Some(json!({"test_path": "my_test"})), state).await;
        let text = result["content"][0]["text"].as_str().unwrap();
        // cargo test will fail in the temp dir (no real project), but the error should
        // reference cargo, not npm
        assert!(text.contains("cargo") || text.contains("Cargo") || text.contains("STDOUT"));

        let _ = std::fs::remove_dir_all(&tmp);
    }

    #[tokio::test]
    async fn test_run_test_suite_detects_bats() {
        let tmp = std::env::temp_dir().join(format!("yolo-test-bats-detect-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&tmp);
        std::fs::create_dir_all(tmp.join("tests")).unwrap();
        std::fs::write(tmp.join("tests/foo.bats"), "@test 'hello' { true; }").unwrap();

        let (_lock, _cwd) = lock_and_chdir(&tmp);
        let state = Arc::new(ToolState::new());

        let result = handle_tool_call("run_test_suite", Some(json!({"test_path": "tests/foo.bats"})), state).await;
        let text = result["content"][0]["text"].as_str().unwrap();
        // Should attempt bats, not npm
        assert!(!text.contains("npm"));

        let _ = std::fs::remove_dir_all(&tmp);
    }

    #[tokio::test]
    async fn test_run_test_suite_no_runner() {
        let tmp = std::env::temp_dir().join(format!("yolo-test-no-runner-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&tmp);
        std::fs::create_dir_all(&tmp).unwrap();

        let (_lock, _cwd) = lock_and_chdir(&tmp);
        let state = Arc::new(ToolState::new());

        let result = handle_tool_call("run_test_suite", Some(json!({"test_path": "some_test"})), state).await;
        assert_eq!(result.get("isError").unwrap(), true);
        let text = result["content"][0]["text"].as_str().unwrap();
        assert!(text.contains("No test runner detected"));

        let _ = std::fs::remove_dir_all(&tmp);
    }

    /// Sets up a full planning directory with all tier files for cross-agent tests.
    fn setup_full_planning(prefix: &str) -> std::path::PathBuf {
        let tmp = std::env::temp_dir().join(format!("yolo-test-{}-{}", prefix, std::process::id()));
        let _ = std::fs::remove_dir_all(&tmp);
        std::fs::create_dir_all(tmp.join(".yolo-planning/codebase")).unwrap();
        std::fs::write(tmp.join(".yolo-planning/codebase/CONVENTIONS.md"), "Convention rules").unwrap();
        std::fs::write(tmp.join(".yolo-planning/codebase/STACK.md"), "Stack: Rust").unwrap();
        std::fs::write(tmp.join(".yolo-planning/codebase/ARCHITECTURE.md"), "Architecture overview").unwrap();
        std::fs::write(tmp.join(".yolo-planning/codebase/ROADMAP.md"), "Roadmap content").unwrap();
        std::fs::write(tmp.join(".yolo-planning/codebase/REQUIREMENTS.md"), "Requirements list").unwrap();
        tmp
    }

    #[tokio::test]
    async fn test_tier1_identical_across_all_roles() {
        let tmp = setup_full_planning("tier1-ident");
        let (_lock, _cwd) = lock_and_chdir(&tmp);
        let _ = tier_context::invalidate_tier_cache();
        let state = Arc::new(ToolState::new());

        let roles = ["dev", "architect", "lead", "qa"];
        let mut tier1s = Vec::new();
        let mut tier1_hashes = Vec::new();

        for role in &roles {
            let result = handle_tool_call(
                "compile_context",
                Some(json!({"phase": 0, "role": role})),
                state.clone(),
            ).await;
            tier1s.push(result["tier1_prefix"].as_str().unwrap().to_string());
            tier1_hashes.push(result["tier1_hash"].as_str().unwrap().to_string());
        }

        // All tier1 content must be byte-identical
        for i in 1..roles.len() {
            assert_eq!(tier1s[0], tier1s[i], "tier1 mismatch for role {}", roles[i]);
            assert_eq!(tier1_hashes[0], tier1_hashes[i], "tier1_hash mismatch for role {}", roles[i]);
        }

        let _ = std::fs::remove_dir_all(&tmp);
    }

    #[tokio::test]
    async fn test_tier2_identical_within_planning_family() {
        let tmp = setup_full_planning("tier2-planning");
        let (_lock, _cwd) = lock_and_chdir(&tmp);
        let _ = tier_context::invalidate_tier_cache();
        let state = Arc::new(ToolState::new());

        let lead = handle_tool_call("compile_context", Some(json!({"phase": 0, "role": "lead"})), state.clone()).await;
        let arch = handle_tool_call("compile_context", Some(json!({"phase": 0, "role": "architect"})), state.clone()).await;

        assert_eq!(
            lead["tier2_prefix"].as_str().unwrap(),
            arch["tier2_prefix"].as_str().unwrap(),
        );
        assert_eq!(
            lead["tier2_hash"].as_str().unwrap(),
            arch["tier2_hash"].as_str().unwrap(),
        );

        let _ = std::fs::remove_dir_all(&tmp);
    }

    #[tokio::test]
    async fn test_tier2_identical_within_execution_family() {
        let tmp = setup_full_planning("tier2-exec");
        let (_lock, _cwd) = lock_and_chdir(&tmp);
        let _ = tier_context::invalidate_tier_cache();
        let state = Arc::new(ToolState::new());

        let dev = handle_tool_call("compile_context", Some(json!({"phase": 0, "role": "dev"})), state.clone()).await;
        let qa = handle_tool_call("compile_context", Some(json!({"phase": 0, "role": "qa"})), state.clone()).await;

        assert_eq!(
            dev["tier2_prefix"].as_str().unwrap(),
            qa["tier2_prefix"].as_str().unwrap(),
        );
        assert_eq!(
            dev["tier2_hash"].as_str().unwrap(),
            qa["tier2_hash"].as_str().unwrap(),
        );

        let _ = std::fs::remove_dir_all(&tmp);
    }

    #[tokio::test]
    async fn test_tier2_different_across_families() {
        let tmp = setup_full_planning("tier2-diff");
        let (_lock, _cwd) = lock_and_chdir(&tmp);
        let _ = tier_context::invalidate_tier_cache();
        let state = Arc::new(ToolState::new());

        let dev = handle_tool_call("compile_context", Some(json!({"phase": 0, "role": "dev"})), state.clone()).await;
        let lead = handle_tool_call("compile_context", Some(json!({"phase": 0, "role": "lead"})), state.clone()).await;

        assert_ne!(
            dev["tier2_hash"].as_str().unwrap(),
            lead["tier2_hash"].as_str().unwrap(),
        );

        let _ = std::fs::remove_dir_all(&tmp);
    }

    #[tokio::test]
    async fn test_tier_separation_content_correctness() {
        let tmp = setup_full_planning("tier-content");
        let (_lock, _cwd) = lock_and_chdir(&tmp);
        let _ = tier_context::invalidate_tier_cache();
        let state = Arc::new(ToolState::new());

        // Check planning family tier content
        let arch = handle_tool_call("compile_context", Some(json!({"phase": 0, "role": "architect"})), state.clone()).await;
        let arch_tier1 = arch["tier1_prefix"].as_str().unwrap();
        let arch_tier2 = arch["tier2_prefix"].as_str().unwrap();

        // Tier 1 contains CONVENTIONS.md + STACK.md
        assert!(arch_tier1.contains("Convention rules"));
        assert!(arch_tier1.contains("Stack: Rust"));
        // Tier 2 planning contains ARCHITECTURE.md, ROADMAP.md, REQUIREMENTS.md
        assert!(arch_tier2.contains("Architecture overview"));
        assert!(arch_tier2.contains("Roadmap content"));
        assert!(arch_tier2.contains("Requirements list"));

        // Check execution family tier content
        let dev = handle_tool_call("compile_context", Some(json!({"phase": 0, "role": "dev"})), state.clone()).await;
        let dev_tier1 = dev["tier1_prefix"].as_str().unwrap();
        let dev_tier2 = dev["tier2_prefix"].as_str().unwrap();

        // Tier 1 same as architect
        assert!(dev_tier1.contains("Convention rules"));
        assert!(dev_tier1.contains("Stack: Rust"));
        // Tier 2 execution contains ROADMAP.md only
        assert!(dev_tier2.contains("Roadmap content"));
        assert!(!dev_tier2.contains("Architecture overview"));
        assert!(!dev_tier2.contains("Requirements list"));

        let _ = std::fs::remove_dir_all(&tmp);
    }
}
