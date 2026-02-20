use serde::{Deserialize, Serialize};

/// All Claude Code hook events the dispatcher can handle.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub enum HookEvent {
    SessionStart,
    PreToolUse,
    PostToolUse,
    PreCompact,
    SubagentStart,
    SubagentStop,
    TeammateIdle,
    TaskCompleted,
    UserPromptSubmit,
    Notification,
    Stop,
}

impl HookEvent {
    /// Parse an event name from CLI argument (case-insensitive).
    pub fn from_arg(s: &str) -> Option<HookEvent> {
        match s.to_lowercase().as_str() {
            "sessionstart" | "session-start" | "session_start" => Some(HookEvent::SessionStart),
            "pretooluse" | "pre-tool-use" | "pre_tool_use" => Some(HookEvent::PreToolUse),
            "posttooluse" | "post-tool-use" | "post_tool_use" => Some(HookEvent::PostToolUse),
            "precompact" | "pre-compact" | "pre_compact" => Some(HookEvent::PreCompact),
            "subagentstart" | "subagent-start" | "subagent_start" => Some(HookEvent::SubagentStart),
            "subagentstop" | "subagent-stop" | "subagent_stop" => Some(HookEvent::SubagentStop),
            "teammateidle" | "teammate-idle" | "teammate_idle" => Some(HookEvent::TeammateIdle),
            "taskcompleted" | "task-completed" | "task_completed" => Some(HookEvent::TaskCompleted),
            "userpromptsubmit" | "user-prompt-submit" | "user_prompt_submit" => {
                Some(HookEvent::UserPromptSubmit)
            }
            "notification" => Some(HookEvent::Notification),
            "stop" => Some(HookEvent::Stop),
            _ => None,
        }
    }
}

/// Raw JSON input from Claude Code hook stdin.
/// We keep this as a serde_json::Value to stay flexible — each handler
/// destructures the fields it needs.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HookInput {
    /// The raw JSON value from stdin.
    #[serde(flatten)]
    pub data: serde_json::Value,
}

/// Result returned by a hook handler.
#[derive(Debug, Clone)]
pub struct HookOutput {
    /// Text to write to stdout (may be empty).
    pub stdout: String,
    /// Process exit code: 0 = success/graceful, 2 = intentional block.
    pub exit_code: i32,
}

impl HookOutput {
    pub fn ok(stdout: String) -> Self {
        Self {
            stdout,
            exit_code: 0,
        }
    }

    pub fn block(stdout: String) -> Self {
        Self {
            stdout,
            exit_code: 2,
        }
    }

    pub fn empty() -> Self {
        Self {
            stdout: String::new(),
            exit_code: 0,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_hook_event_from_arg_all_variants() {
        // PascalCase
        assert_eq!(
            HookEvent::from_arg("SessionStart"),
            Some(HookEvent::SessionStart)
        );
        assert_eq!(
            HookEvent::from_arg("PreToolUse"),
            Some(HookEvent::PreToolUse)
        );
        assert_eq!(
            HookEvent::from_arg("PostToolUse"),
            Some(HookEvent::PostToolUse)
        );
        assert_eq!(
            HookEvent::from_arg("PreCompact"),
            Some(HookEvent::PreCompact)
        );
        assert_eq!(
            HookEvent::from_arg("SubagentStart"),
            Some(HookEvent::SubagentStart)
        );
        assert_eq!(
            HookEvent::from_arg("SubagentStop"),
            Some(HookEvent::SubagentStop)
        );
        assert_eq!(
            HookEvent::from_arg("TeammateIdle"),
            Some(HookEvent::TeammateIdle)
        );
        assert_eq!(
            HookEvent::from_arg("TaskCompleted"),
            Some(HookEvent::TaskCompleted)
        );
        assert_eq!(
            HookEvent::from_arg("UserPromptSubmit"),
            Some(HookEvent::UserPromptSubmit)
        );
        assert_eq!(
            HookEvent::from_arg("Notification"),
            Some(HookEvent::Notification)
        );
        assert_eq!(HookEvent::from_arg("Stop"), Some(HookEvent::Stop));

        // kebab-case
        assert_eq!(
            HookEvent::from_arg("session-start"),
            Some(HookEvent::SessionStart)
        );
        assert_eq!(
            HookEvent::from_arg("pre-tool-use"),
            Some(HookEvent::PreToolUse)
        );
        assert_eq!(
            HookEvent::from_arg("subagent-start"),
            Some(HookEvent::SubagentStart)
        );

        // snake_case
        assert_eq!(
            HookEvent::from_arg("session_start"),
            Some(HookEvent::SessionStart)
        );
        assert_eq!(
            HookEvent::from_arg("pre_tool_use"),
            Some(HookEvent::PreToolUse)
        );

        // Unknown
        assert_eq!(HookEvent::from_arg("bogus"), None);
        assert_eq!(HookEvent::from_arg(""), None);
    }

    #[test]
    fn test_hook_input_deserialize() {
        let json_str = r#"{"tool_name":"Bash","input":{"command":"ls"}}"#;
        let input: HookInput = serde_json::from_str(json_str).unwrap();
        assert_eq!(input.data["tool_name"], "Bash");
        assert_eq!(input.data["input"]["command"], "ls");
    }

    #[test]
    fn test_hook_output_constructors() {
        let ok = HookOutput::ok("hello".to_string());
        assert_eq!(ok.exit_code, 0);
        assert_eq!(ok.stdout, "hello");

        let block = HookOutput::block("denied".to_string());
        assert_eq!(block.exit_code, 2);
        assert_eq!(block.stdout, "denied");

        let empty = HookOutput::empty();
        assert_eq!(empty.exit_code, 0);
        assert!(empty.stdout.is_empty());
    }

    #[test]
    fn test_hook_event_serde_roundtrip() {
        let event = HookEvent::PreToolUse;
        let json = serde_json::to_string(&event).unwrap();
        assert_eq!(json, "\"PreToolUse\"");
        let back: HookEvent = serde_json::from_str(&json).unwrap();
        assert_eq!(back, HookEvent::PreToolUse);
    }
}
