//! Native Rust hook handlers for Claude Code hook events.
//!
//! Supported hook events and their handlers:
//!   - **SessionStart**: `post_compact` (compact mode), `map_staleness` (non-compact)
//!   - **PreToolUse**: `security_filter` (blocks sensitive file access)
//!   - **PostToolUse**: `validate_summary`, `skill_hook_dispatch`
//!   - **PreCompact**: `compaction_instructions`
//!   - **SubagentStart**: `agent_start`, `agent_health`
//!   - **SubagentStop**: `agent_stop`, `agent_health`
//!   - **TeammateIdle**: `agent_health`
//!   - **TaskCompleted**: `blocker_notify`
//!   - **UserPromptSubmit**: `prompt_preflight`
//!   - **Stop**: `session_stop`
//!   - **Notification**: `notification_log`
//!
//! All events are dispatched via `dispatcher::dispatch()`.
//! Entry point: `yolo hook <event-name>` (reads JSON from stdin).

// Hook infrastructure modules (dev-01)
pub mod dispatcher;
pub mod sighup;
pub mod types;
pub mod utils;

// Agent lifecycle modules (dev-01)
pub mod agent_health;
pub mod agent_pid_tracker;
pub mod agent_start;
pub mod agent_stop;

// Hook validation modules (dev-03)
pub mod validate_summary;
pub mod validate_frontmatter;
pub mod validate_contract;
pub mod validate_message;
pub mod validate_schema;

// Security hooks (dev-05)
pub mod security_filter;
pub mod prompt_preflight;

// Skill/blocker hook modules (dev-07)
pub mod skill_hook_dispatch;
pub mod blocker_notify;

// Compaction, session, and notification hooks (dev-06)
pub mod compaction_instructions;
pub mod notification_log;
pub mod post_compact;
pub mod session_stop;

// Cache/delta hooks (dev-10)
pub mod map_staleness;

#[cfg(test)]
mod no_bash_regression {
    use std::fs;
    use std::path::Path;

    /// Static analysis: verify no hook module uses Command::new("bash").
    /// skill_hook_dispatch.rs is exempt (legitimately invokes user skill scripts).
    #[test]
    fn test_no_command_new_bash_in_hooks() {
        let hooks_dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("src/hooks");
        let exempt = ["skill_hook_dispatch.rs", "mod.rs"];

        for entry in fs::read_dir(&hooks_dir).unwrap() {
            let entry = entry.unwrap();
            let path = entry.path();
            if !path.extension().map_or(false, |e| e == "rs") {
                continue;
            }
            let filename = path.file_name().unwrap().to_string_lossy().to_string();
            if exempt.contains(&filename.as_str()) {
                continue;
            }
            let content = fs::read_to_string(&path).unwrap();
            assert!(
                !content.contains(r#"Command::new("bash")"#),
                "hooks/{} contains Command::new(\"bash\") -- migrate to native Rust",
                filename
            );
        }
    }

    /// Verify session_start.rs has no bash shell-outs.
    #[test]
    fn test_no_command_new_bash_in_session_start() {
        let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("src/commands/session_start.rs");
        let content = fs::read_to_string(&path).unwrap();
        assert!(
            !content.contains(r#"Command::new("bash")"#),
            "session_start.rs still contains Command::new(\"bash\") -- should be migrated"
        );
    }

    /// Verify hard_gate.rs only uses Command::new("bash") for user-defined verification checks.
    /// hard_gate evaluates arbitrary shell commands from contract JSON (verification_checks),
    /// which is a legitimate use case similar to skill_hook_dispatch.
    #[test]
    fn test_hard_gate_bash_is_user_defined_checks_only() {
        let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("src/commands/hard_gate.rs");
        let content = fs::read_to_string(&path).unwrap();
        let bash_count = content.matches(r#"Command::new("bash")"#).count();
        // hard_gate has exactly 1 bash invocation for user-defined verification_checks.
        // If this increases, new bash usages need justification.
        assert!(
            bash_count <= 1,
            "hard_gate.rs has {} Command::new(\"bash\") calls -- only 1 is expected (verification_checks)",
            bash_count
        );
    }

    /// Verify two_phase_complete.rs only uses Command::new("sh") for user-defined verification checks.
    #[test]
    fn test_two_phase_complete_sh_is_user_defined_checks_only() {
        let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("src/commands/two_phase_complete.rs");
        let content = fs::read_to_string(&path).unwrap();
        let sh_count = content.matches(r#"Command::new("sh")"#).count();
        assert!(
            sh_count <= 1,
            "two_phase_complete.rs has {} Command::new(\"sh\") calls -- only 1 is expected (verification_checks)",
            sh_count
        );
    }
}
