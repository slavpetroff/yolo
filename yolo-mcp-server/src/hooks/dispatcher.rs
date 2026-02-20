use std::path::Path;

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
/// Each handler will be implemented in subsequent plans by other dev agents.
/// For now, unimplemented handlers return Ok(empty) — graceful no-op.
fn route_event(event: &HookEvent, input: &HookInput) -> Result<HookOutput, String> {
    match event {
        HookEvent::SessionStart => handle_stub("SessionStart", input),
        HookEvent::PreToolUse => handle_stub("PreToolUse", input),
        HookEvent::PostToolUse => handle_stub("PostToolUse", input),
        HookEvent::PreCompact => handle_stub("PreCompact", input),
        HookEvent::SubagentStart => handle_stub("SubagentStart", input),
        HookEvent::SubagentStop => handle_stub("SubagentStop", input),
        HookEvent::TeammateIdle => handle_stub("TeammateIdle", input),
        HookEvent::TaskCompleted => handle_stub("TaskCompleted", input),
        HookEvent::UserPromptSubmit => handle_stub("UserPromptSubmit", input),
        HookEvent::Notification => handle_stub("Notification", input),
        HookEvent::Stop => handle_stub("Stop", input),
    }
}

/// Stub handler for events not yet migrated.
/// Returns empty output with exit 0 — no-op passthrough.
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
        let events = vec![
            HookEvent::SessionStart,
            HookEvent::PreToolUse,
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
        for event in events {
            let (output, code) = dispatch(&event, stdin);
            assert_eq!(code, 0, "Event {:?} should return exit 0", event);
            assert!(
                output.is_empty(),
                "Stub for {:?} should produce empty output",
                event
            );
        }
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
        let result = dispatch_from_cli("pre-tool-use", r#"{"tool_name":"Read"}"#);
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
    fn test_route_event_stub_returns_empty() {
        let input = HookInput {
            data: serde_json::json!({"test": true}),
        };
        let result = route_event(&HookEvent::Stop, &input);
        assert!(result.is_ok());
        let output = result.unwrap();
        assert_eq!(output.exit_code, 0);
        assert!(output.stdout.is_empty());
    }
}
