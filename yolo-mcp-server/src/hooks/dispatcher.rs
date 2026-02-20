use serde_json::Value;

use super::agent_health;
use super::agent_start;
use super::agent_stop;
use super::blocker_notify;
use super::compaction_instructions;
use super::notification_log;
use super::post_compact;
use super::prompt_preflight;
use super::security_filter;
use super::map_staleness;
use super::session_stop;
use super::skill_hook_dispatch;
use super::validate_summary;
use super::types::{HookEvent, HookInput, HookOutput};
use super::utils;

/// Dispatch a hook event to the appropriate handler.
///
/// - Parses `stdin_json` into a `HookInput`
/// - Routes to the handler for `event`
/// - On handler error: logs to `.hook-errors.log`, returns exit 0 (graceful degradation)
/// - On handler returning exit 2: passes through (intentional block)
/// - Never panics
pub fn dispatch(event: &HookEvent, stdin_json: &str) -> (String, i32) {
    let input = match serde_json::from_str::<HookInput>(stdin_json) {
        Ok(input) => input,
        Err(e) => {
            // Bad JSON — log and degrade gracefully
            if let Some(planning_dir) = find_planning_dir() {
                utils::log_hook_error(&planning_dir, &format!("{:?}", event), 1);
                utils::log_hook_message(
                    &planning_dir,
                    &format!("Failed to parse hook stdin: {}", e),
                );
            }
            return (String::new(), 0);
        }
    };

    let result = route_event(event, &input);

    match result {
        Ok(output) => (output.stdout, output.exit_code),
        Err(err_msg) => {
            // Handler error — log and degrade gracefully
            if let Some(planning_dir) = find_planning_dir() {
                utils::log_hook_error(&planning_dir, &format!("{:?}", event), 1);
                utils::log_hook_message(
                    &planning_dir,
                    &format!("Hook handler error for {:?}: {}", event, err_msg),
                );
            }
            (String::new(), 0)
        }
    }
}

/// Route an event to its handler function.
/// All hook events are wired to native Rust handlers.
fn route_event(event: &HookEvent, input: &HookInput) -> Result<HookOutput, String> {
    let planning_dir = find_planning_dir();

    match event {
        HookEvent::SessionStart => handle_session_start(input),
        HookEvent::PreToolUse => {
            // Security filter runs first — exit 2 = block
            let sf_result = security_filter::handle(input)?;
            if sf_result.exit_code == 2 {
                return Ok(sf_result);
            }
            Ok(HookOutput::empty())
        }
        HookEvent::PostToolUse => handle_post_tool_use(input),
        HookEvent::PreCompact => handle_pre_compact(input),
        HookEvent::SubagentStart => {
            if let Some(ref pd) = planning_dir {
                let start_result = agent_start::handle(input, pd);
                let _ = agent_health::cmd_start(input, pd);
                start_result
            } else {
                Ok(HookOutput::empty())
            }
        }
        HookEvent::SubagentStop => {
            if let Some(ref pd) = planning_dir {
                let stop_result = agent_stop::handle(input, pd);
                let _ = agent_health::cmd_stop(input, pd);
                stop_result
            } else {
                Ok(HookOutput::empty())
            }
        }
        HookEvent::TeammateIdle => {
            if let Some(ref pd) = planning_dir {
                agent_health::cmd_idle(input, pd)
            } else {
                Ok(HookOutput::empty())
            }
        }
        HookEvent::TaskCompleted => handle_task_completed(input),
        HookEvent::UserPromptSubmit => prompt_preflight::handle(input),
        HookEvent::Notification => handle_notification(input),
        HookEvent::Stop => handle_stop(input),
    }
}

/// PostToolUse handler: runs validators then skill_hook_dispatch.
/// Non-blocking: always returns exit 0 with advisory context.
fn handle_post_tool_use(input: &HookInput) -> Result<HookOutput, String> {
    // Run validate_summary (advisory)
    let (summary_output, _) = validate_summary::validate_summary(&input.data);

    // Run skill_hook_dispatch (advisory, may invoke user scripts)
    let (_, _) = skill_hook_dispatch::skill_hook_dispatch("PostToolUse", &input.data);

    // Return summary validation advisory if present
    if !summary_output.is_null() {
        let stdout = serde_json::to_string(&summary_output).unwrap_or_default();
        return Ok(HookOutput::ok(stdout));
    }

    Ok(HookOutput::empty())
}

/// TaskCompleted handler: runs blocker_notify to detect newly-unblocked tasks.
/// Non-blocking: always returns exit 0 with advisory context.
fn handle_task_completed(input: &HookInput) -> Result<HookOutput, String> {
    let (output, _) = blocker_notify::blocker_notify(&input.data);

    if !output.is_null() {
        let stdout = serde_json::to_string(&output).unwrap_or_default();
        return Ok(HookOutput::ok(stdout));
    }

    Ok(HookOutput::empty())
}

/// Convert a (Value, i32) handler result to HookOutput.
fn value_to_hook_output(value: &Value, exit_code: i32) -> HookOutput {
    if value.is_null() {
        return HookOutput { stdout: String::new(), exit_code };
    }
    let stdout = serde_json::to_string(value).unwrap_or_default();
    HookOutput { stdout, exit_code }
}

/// SessionStart handler: detects compact-triggered sessions and runs post_compact.
/// For non-compact sessions, runs map_staleness check.
fn handle_session_start(input: &HookInput) -> Result<HookOutput, String> {
    // Check if this is a compact-triggered session start
    let is_compact = input.data.get("compact")
        .and_then(|v| v.as_bool())
        .unwrap_or(false)
        || input.data.get("reason")
            .and_then(|v| v.as_str())
            .map(|r| r == "compact")
            .unwrap_or(false);

    if is_compact {
        let (output, code) = post_compact::handle_post_compact(&input.data);
        return Ok(value_to_hook_output(&output, code));
    }

    // Non-compact session: check codebase map staleness
    map_staleness::handle(input, true)
}

/// PreCompact handler: inject agent-specific summarization priorities.
fn handle_pre_compact(input: &HookInput) -> Result<HookOutput, String> {
    let (output, code) = compaction_instructions::handle_pre_compact(&input.data);
    Ok(value_to_hook_output(&output, code))
}

/// Notification handler: log notification metadata.
fn handle_notification(input: &HookInput) -> Result<HookOutput, String> {
    let (output, code) = notification_log::handle_notification(&input.data);
    Ok(value_to_hook_output(&output, code))
}

/// Stop handler: log session metrics and clean up transient files.
fn handle_stop(input: &HookInput) -> Result<HookOutput, String> {
    let (output, code) = session_stop::handle_stop(&input.data);
    Ok(value_to_hook_output(&output, code))
}

/// Stub handler for events not yet migrated.
/// Returns empty output with exit 0 — no-op passthrough.
#[allow(dead_code)]
fn handle_stub(_event_name: &str, _input: &HookInput) -> Result<HookOutput, String> {
    Ok(HookOutput::empty())
}

/// Find the `.yolo-planning` directory from cwd.
fn find_planning_dir() -> Option<std::path::PathBuf> {
    let cwd = std::env::current_dir().ok()?;
    utils::get_planning_dir(&cwd)
}

/// Convenience: dispatch from raw CLI args.
/// Reads stdin, parses event name, calls dispatch().
pub fn dispatch_from_cli(event_name: &str, stdin_json: &str) -> Result<(String, i32), String> {
    let event = HookEvent::from_arg(event_name)
        .ok_or_else(|| format!("Unknown hook event: {}", event_name))?;
    Ok(dispatch(&event, stdin_json))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_dispatch_all_events_return_ok() {
        let events_exit_0 = vec![
            HookEvent::SessionStart,
            HookEvent::PostToolUse,
            HookEvent::PreCompact,
            HookEvent::SubagentStart,
            HookEvent::SubagentStop,
            HookEvent::TeammateIdle,
            HookEvent::TaskCompleted,
            HookEvent::UserPromptSubmit,
            HookEvent::Notification,
            HookEvent::Stop,
        ];

        let stdin = r#"{"tool_name":"Bash"}"#;
        for event in events_exit_0 {
            let (_output, code) = dispatch(&event, stdin);
            assert_eq!(code, 0, "Event {:?} should return exit 0", event);
        }
    }

    #[test]
    fn test_dispatch_pre_tool_use_blocks_without_tool_input() {
        // security_filter is fail-closed: no tool_input => exit 2
        let stdin = r#"{"tool_name":"Bash"}"#;
        let (_output, code) = dispatch(&HookEvent::PreToolUse, stdin);
        assert_eq!(code, 2, "PreToolUse without tool_input should block (fail-closed)");
    }

    #[test]
    fn test_dispatch_pre_tool_use_allows_normal_file() {
        let stdin = r#"{"tool_name":"Read","tool_input":{"file_path":"/project/src/main.rs"}}"#;
        let (_output, code) = dispatch(&HookEvent::PreToolUse, stdin);
        assert_eq!(code, 0, "PreToolUse with normal file should pass");
    }

    #[test]
    fn test_dispatch_pre_tool_use_blocks_env_file() {
        let stdin = r#"{"tool_name":"Read","tool_input":{"file_path":"/project/.env"}}"#;
        let (output, code) = dispatch(&HookEvent::PreToolUse, stdin);
        assert_eq!(code, 2, "PreToolUse with .env should block");
        assert!(output.contains("deny"));
    }

    #[test]
    fn test_dispatch_bad_json_graceful() {
        let (output, code) = dispatch(&HookEvent::PreToolUse, "not valid json {{{");
        assert_eq!(code, 0, "Bad JSON should degrade gracefully to exit 0");
        assert!(output.is_empty());
    }

    #[test]
    fn test_dispatch_empty_json_object() {
        let (output, code) = dispatch(&HookEvent::SessionStart, "{}");
        assert_eq!(code, 0);
        assert!(output.is_empty());
    }

    #[test]
    fn test_dispatch_from_cli_valid() {
        let result = dispatch_from_cli(
            "pre-tool-use",
            r#"{"tool_name":"Read","tool_input":{"file_path":"/project/src/main.rs"}}"#,
        );
        assert!(result.is_ok());
        let (output, code) = result.unwrap();
        assert_eq!(code, 0);
        assert!(output.is_empty());
    }

    #[test]
    fn test_dispatch_from_cli_unknown_event() {
        let result = dispatch_from_cli("bogus-event", "{}");
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Unknown hook event"));
    }

    #[test]
    fn test_dispatch_from_cli_all_event_names() {
        let names = vec![
            "session-start",
            "pre-tool-use",
            "post-tool-use",
            "pre-compact",
            "subagent-start",
            "subagent-stop",
            "teammate-idle",
            "task-completed",
            "user-prompt-submit",
            "notification",
            "stop",
        ];
        for name in names {
            let result = dispatch_from_cli(name, "{}");
            assert!(
                result.is_ok(),
                "Event '{}' should be recognized",
                name
            );
        }
    }

    #[test]
    fn test_route_event_stop_returns_ok() {
        let input = HookInput {
            data: serde_json::json!({"test": true}),
        };
        let result = route_event(&HookEvent::Stop, &input);
        assert!(result.is_ok());
        let output = result.unwrap();
        assert_eq!(output.exit_code, 0);
    }

    #[test]
    fn test_post_tool_use_exits_0_with_normal_input() {
        let stdin = r#"{"tool_name":"Bash","tool_input":{"command":"ls"}}"#;
        let (_output, code) = dispatch(&HookEvent::PostToolUse, stdin);
        assert_eq!(code, 0, "PostToolUse should always exit 0 (advisory)");
    }

    #[test]
    fn test_task_completed_exits_0_with_task_id() {
        let stdin = r#"{"task_id":"42"}"#;
        let (_output, code) = dispatch(&HookEvent::TaskCompleted, stdin);
        assert_eq!(code, 0, "TaskCompleted should always exit 0 (advisory)");
    }

    #[test]
    fn test_task_completed_exits_0_empty_input() {
        let stdin = r#"{}"#;
        let (_output, code) = dispatch(&HookEvent::TaskCompleted, stdin);
        assert_eq!(code, 0, "TaskCompleted with empty input should exit 0");
    }

    #[test]
    fn test_pre_compact_returns_priorities() {
        let stdin = r#"{"agent_name": "yolo-dev-1", "matcher": "auto"}"#;
        let (output, code) = dispatch(&HookEvent::PreCompact, stdin);
        assert_eq!(code, 0);
        assert!(output.contains("Compaction priorities:"));
        assert!(output.contains("commit hashes"));
    }

    #[test]
    fn test_notification_exits_0() {
        let stdin = r#"{"notification_type": "info", "message": "test msg", "title": "Test"}"#;
        let (_output, code) = dispatch(&HookEvent::Notification, stdin);
        assert_eq!(code, 0, "Notification should always exit 0");
    }

    #[test]
    fn test_stop_exits_0() {
        let stdin = r#"{"cost_usd": 0.42, "duration_ms": 30000, "model": "claude-opus-4-6"}"#;
        let (_output, code) = dispatch(&HookEvent::Stop, stdin);
        assert_eq!(code, 0, "Stop should always exit 0");
    }

    #[test]
    fn test_session_start_non_compact_empty() {
        let stdin = r#"{}"#;
        let (output, code) = dispatch(&HookEvent::SessionStart, stdin);
        assert_eq!(code, 0);
        assert!(output.is_empty(), "Non-compact SessionStart should be empty");
    }

    #[test]
    fn test_session_start_compact_returns_context() {
        let stdin = r#"{"compact": true}"#;
        let (output, code) = dispatch(&HookEvent::SessionStart, stdin);
        assert_eq!(code, 0);
        assert!(output.contains("Context was compacted"));
    }
}
