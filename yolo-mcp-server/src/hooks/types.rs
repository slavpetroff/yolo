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

/// Typed input for the security filter hook.
#[derive(Debug, Clone, Deserialize)]
pub struct SecurityFilterInput {
    pub tool_name: Option<String>,
    pub tool_input: Option<SecurityToolInput>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct SecurityToolInput {
    pub file_path: Option<String>,
    pub path: Option<String>,
    pub pattern: Option<String>,
}

/// Typed input for the contract validation hook.
#[derive(Debug, Clone, Deserialize)]
pub struct ContractValidationInput {
    pub mode: Option<String>,
    pub contract_path: Option<String>,
    pub task_number: Option<u32>,
    pub modified_files: Option<Vec<String>>,
}

impl SecurityFilterInput {
    /// Try to parse from a HookInput, falling back to None fields on failure.
    pub fn from_hook_input(input: &HookInput) -> Self {
        serde_json::from_value(input.data.clone()).unwrap_or(SecurityFilterInput {
            tool_name: None,
            tool_input: None,
        })
    }
}

impl ContractValidationInput {
    /// Try to parse from a serde_json::Value.
    pub fn from_value(value: &serde_json::Value) -> Self {
        serde_json::from_value(value.clone()).unwrap_or(ContractValidationInput {
            mode: None,
            contract_path: None,
            task_number: None,
            modified_files: None,
        })
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

    #[test]
    fn test_security_filter_input_from_hook_input() {
        let input = HookInput {
            data: serde_json::json!({
                "tool_name": "Read",
                "tool_input": {
                    "file_path": "/project/src/main.rs",
                    "path": null,
                    "pattern": null
                }
            }),
        };
        let typed = SecurityFilterInput::from_hook_input(&input);
        assert_eq!(typed.tool_name.as_deref(), Some("Read"));
        let ti = typed.tool_input.unwrap();
        assert_eq!(ti.file_path.as_deref(), Some("/project/src/main.rs"));
        assert!(ti.path.is_none());
        assert!(ti.pattern.is_none());
    }

    #[test]
    fn test_security_filter_input_fallback() {
        let input = HookInput {
            data: serde_json::json!({"unexpected": 42}),
        };
        let typed = SecurityFilterInput::from_hook_input(&input);
        assert!(typed.tool_name.is_none());
        assert!(typed.tool_input.is_none());
    }

    #[test]
    fn test_contract_validation_input_from_value() {
        let value = serde_json::json!({
            "mode": "start",
            "contract_path": "/project/.yolo-planning/contract.json",
            "task_number": 3,
            "modified_files": ["src/main.rs", "src/lib.rs"]
        });
        let typed = ContractValidationInput::from_value(&value);
        assert_eq!(typed.mode.as_deref(), Some("start"));
        assert_eq!(
            typed.contract_path.as_deref(),
            Some("/project/.yolo-planning/contract.json")
        );
        assert_eq!(typed.task_number, Some(3));
        assert_eq!(
            typed.modified_files.as_deref(),
            Some(&["src/main.rs".to_string(), "src/lib.rs".to_string()][..])
        );
    }

    #[test]
    fn test_contract_validation_input_fallback() {
        let value = serde_json::json!({"bogus": true});
        let typed = ContractValidationInput::from_value(&value);
        assert!(typed.mode.is_none());
        assert!(typed.contract_path.is_none());
        assert!(typed.task_number.is_none());
        assert!(typed.modified_files.is_none());
    }
}
