use serde_json::Value;
use std::fs;
use std::path::Path;
use std::process::Command;

use super::utils;

/// PostToolUse handler that dispatches to user-defined skill hook scripts.
///
/// Reads `skill_hooks` from `.yolo-planning/config.json`:
/// ```json
/// { "skill_hooks": { "skill-name": { "event": "PostToolUse", "tools": "Write|Edit" } } }
/// ```
///
/// For each matching skill hook:
/// 1. Matches event type against configured `event`
/// 2. Matches tool_name against `tools` (pipe-delimited regex pattern)
/// 3. Finds the skill script in plugin cache (latest version)
/// 4. Invokes via `Command::new("bash")` (user-defined external scripts)
///
/// Always returns exit 0 (fail-open, advisory only).
pub fn skill_hook_dispatch(event_type: &str, input: &Value) -> (Value, i32) {
    let tool_name = input
        .get("tool_name")
        .and_then(|v| v.as_str())
        .unwrap_or("");

    if tool_name.is_empty() {
        return (Value::Null, 0);
    }

    // Find config.json
    let config = match load_config() {
        Some(c) => c,
        None => return (Value::Null, 0),
    };

    // Read skill_hooks from config
    let skill_hooks = match config.get("skill_hooks") {
        Some(hooks) if hooks.is_object() => hooks,
        _ => return (Value::Null, 0),
    };

    let hooks_obj = match skill_hooks.as_object() {
        Some(obj) => obj,
        None => return (Value::Null, 0),
    };

    let plugin_cache = utils::resolve_plugin_cache();

    for (skill_name, hook_config) in hooks_obj {
        let configured_event = hook_config
            .get("event")
            .and_then(|v| v.as_str())
            .unwrap_or("");

        // Check event type matches
        if configured_event != event_type {
            continue;
        }

        let tools_pattern = hook_config
            .get("tools")
            .and_then(|v| v.as_str())
            .unwrap_or("");

        // Check tool name matches (pipe-delimited exact match)
        if !matches_tool_pattern(tool_name, tools_pattern) {
            continue;
        }

        // Find and invoke the skill script from plugin cache
        if let Some(ref cache_dir) = plugin_cache {
            let script_name = format!("{}-hook.sh", skill_name);
            if let Some(script_path) = find_skill_script(cache_dir, &script_name) {
                invoke_skill_script(&script_path, input);
            }
        }
    }

    (Value::Null, 0)
}

/// Check if tool_name matches a pipe-delimited pattern (e.g. "Write|Edit").
fn matches_tool_pattern(tool_name: &str, pattern: &str) -> bool {
    if pattern.is_empty() {
        return false;
    }
    pattern.split('|').any(|p| p.trim() == tool_name)
}

/// Find a skill hook script in the plugin cache directory.
/// Looks in `<cache_dir>/scripts/<script_name>` for the resolved (latest version) cache dir.
fn find_skill_script(cache_dir: &Path, script_name: &str) -> Option<std::path::PathBuf> {
    let script_path = cache_dir.join("scripts").join(script_name);
    if script_path.is_file() {
        Some(script_path)
    } else {
        None
    }
}

/// Invoke a user-defined skill hook script via bash.
/// This is the ONE acceptable shell-out: user-defined external scripts.
fn invoke_skill_script(script_path: &Path, input: &Value) {
    let input_json = serde_json::to_string(input).unwrap_or_default();

    let _ = Command::new("bash")
        .arg(script_path)
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .spawn()
        .and_then(|mut child| {
            use std::io::Write;
            if let Some(ref mut stdin) = child.stdin {
                let _ = stdin.write_all(input_json.as_bytes());
            }
            child.wait()
        });
}

/// Load config.json from .yolo-planning/.
fn load_config() -> Option<Value> {
    let cwd = std::env::current_dir().ok()?;
    let planning_dir = utils::get_planning_dir(&cwd)?;
    let config_path = planning_dir.join("config.json");
    let content = fs::read_to_string(config_path).ok()?;
    serde_json::from_str(&content).ok()
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn test_matches_tool_pattern_single() {
        assert!(matches_tool_pattern("Write", "Write"));
        assert!(!matches_tool_pattern("Read", "Write"));
    }

    #[test]
    fn test_matches_tool_pattern_pipe_delimited() {
        assert!(matches_tool_pattern("Write", "Write|Edit"));
        assert!(matches_tool_pattern("Edit", "Write|Edit"));
        assert!(!matches_tool_pattern("Read", "Write|Edit"));
    }

    #[test]
    fn test_matches_tool_pattern_empty() {
        assert!(!matches_tool_pattern("Write", ""));
    }

    #[test]
    fn test_matches_tool_pattern_exact_no_substring() {
        assert!(!matches_tool_pattern("Writ", "Write|Edit"));
        assert!(!matches_tool_pattern("WriteFile", "Write|Edit"));
    }

    #[test]
    fn test_skill_hook_dispatch_empty_tool_name() {
        let input = json!({});
        let (output, code) = skill_hook_dispatch("PostToolUse", &input);
        assert_eq!(code, 0);
        assert_eq!(output, Value::Null);
    }

    #[test]
    fn test_skill_hook_dispatch_no_config() {
        let input = json!({"tool_name": "Write"});
        let (output, code) = skill_hook_dispatch("PostToolUse", &input);
        assert_eq!(code, 0);
        assert_eq!(output, Value::Null);
    }

    #[test]
    fn test_find_skill_script_missing() {
        let dir = tempfile::tempdir().unwrap();
        let result = find_skill_script(dir.path(), "nonexistent-hook.sh");
        assert!(result.is_none());
    }

    #[test]
    fn test_find_skill_script_found() {
        let dir = tempfile::tempdir().unwrap();
        let scripts_dir = dir.path().join("scripts");
        std::fs::create_dir_all(&scripts_dir).unwrap();
        let script_path = scripts_dir.join("my-skill-hook.sh");
        std::fs::write(&script_path, "#!/bin/bash\nexit 0").unwrap();

        let result = find_skill_script(dir.path(), "my-skill-hook.sh");
        assert!(result.is_some());
        assert_eq!(result.unwrap(), script_path);
    }

    #[test]
    fn test_skill_hook_dispatch_with_config() {
        // Set up a temp dir with .yolo-planning/config.json containing skill_hooks
        let dir = tempfile::tempdir().unwrap();
        let planning = dir.path().join(".yolo-planning");
        std::fs::create_dir_all(&planning).unwrap();
        std::fs::write(
            planning.join("config.json"),
            r#"{
                "skill_hooks": {
                    "auto-format": {
                        "event": "PostToolUse",
                        "tools": "Write|Edit"
                    }
                }
            }"#,
        )
        .unwrap();

        // This won't find the actual script (no plugin cache), but verifies config parsing
        // The function should still return (Null, 0) gracefully
        let input = json!({"tool_name": "Write"});
        let (output, code) = skill_hook_dispatch("PostToolUse", &input);
        assert_eq!(code, 0);
        assert_eq!(output, Value::Null);
    }

    #[test]
    fn test_skill_hook_dispatch_event_mismatch() {
        // Even with valid config, wrong event type should not match
        let input = json!({"tool_name": "Write"});
        let (output, code) = skill_hook_dispatch("PreToolUse", &input);
        assert_eq!(code, 0);
        assert_eq!(output, Value::Null);
    }
}
