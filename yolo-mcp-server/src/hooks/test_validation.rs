use serde_json::{json, Value};
use std::fs;
use std::path::Path;

const PLANNING_DIR: &str = ".yolo-planning";

/// PostToolUse handler: advisory test validation after Write/Edit operations.
///
/// When a source file is written or edited, checks if a corresponding test file
/// exists and surfaces a reminder. Always returns exit 0 (advisory, non-blocking).
///
/// Gated behind `v4_post_edit_test_check` feature flag (default: false).
pub fn handle(input: &Value) -> (Value, i32) {
    // Check feature flag first
    if !is_enabled() {
        return (Value::Null, 0);
    }

    // Only trigger on Write or Edit tools
    let tool_name = input
        .get("tool_name")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    if tool_name != "Write" && tool_name != "Edit" {
        return (Value::Null, 0);
    }

    // Extract file path from tool_input
    let file_path = input
        .get("tool_input")
        .and_then(|ti| ti.get("file_path"))
        .and_then(|v| v.as_str())
        .unwrap_or("");

    if file_path.is_empty() {
        return (Value::Null, 0);
    }

    // Skip non-source files (tests themselves, config, planning artifacts)
    if is_non_source_file(file_path) {
        return (Value::Null, 0);
    }

    // Check for corresponding test file
    let test_path = find_test_file(file_path);

    let advisory = match test_path {
        Some(tp) => json!({
            "hookSpecificOutput": {
                "hookEventName": "PostToolUse",
                "additionalContext": format!(
                    "Test file exists: {}. Remember to run tests after changes.",
                    tp
                )
            }
        }),
        None => json!({
            "hookSpecificOutput": {
                "hookEventName": "PostToolUse",
                "additionalContext": format!(
                    "No test file found for {}. Consider creating tests.",
                    file_path
                )
            }
        }),
    };

    (advisory, 0)
}

/// Check if the v4_post_edit_test_check feature flag is enabled.
fn is_enabled() -> bool {
    let config_path = format!("{}/config.json", PLANNING_DIR);
    let content = match fs::read_to_string(&config_path) {
        Ok(c) => c,
        Err(_) => return false,
    };

    let config: Value = match serde_json::from_str(&content) {
        Ok(v) => v,
        Err(_) => return false,
    };

    config
        .get("v4_post_edit_test_check")
        .and_then(|v| v.as_bool())
        .unwrap_or(false)
}

/// Skip files that aren't source code (tests, config, planning, markdown).
fn is_non_source_file(path: &str) -> bool {
    let p = Path::new(path);
    let filename = p.file_name().and_then(|n| n.to_str()).unwrap_or("");

    // Skip test files themselves
    if filename.ends_with(".bats")
        || filename.ends_with("_test.rs")
        || filename.ends_with("_test.go")
        || filename.starts_with("test_")
        || path.contains("/tests/")
        || path.contains("/test/")
    {
        return true;
    }

    // Skip planning artifacts
    if path.contains(".yolo-planning/") || path.contains(".vbw-planning/") {
        return true;
    }

    // Skip config/docs
    if filename.ends_with(".json")
        || filename.ends_with(".toml")
        || filename.ends_with(".yaml")
        || filename.ends_with(".yml")
        || filename.ends_with(".md")
    {
        return true;
    }

    false
}

/// Find a corresponding test file for the given source file.
/// Returns Some(path_string) if found, None otherwise.
fn find_test_file(source_path: &str) -> Option<String> {
    let p = Path::new(source_path);
    let stem = p.file_stem().and_then(|s| s.to_str())?;
    let ext = p.extension().and_then(|e| e.to_str()).unwrap_or("");

    // Strategy 1: Check for tests/<stem>.bats (bats convention)
    // Walk up to find a tests/ directory
    let mut dir = p.parent();
    while let Some(d) = dir {
        let bats = d.join("tests").join(format!("{}.bats", stem));
        if bats.is_file() {
            return Some(bats.to_string_lossy().to_string());
        }
        dir = d.parent();
    }

    // Strategy 2: Rust convention — src/foo.rs -> same dir foo_test or tests/foo.rs
    if ext == "rs" {
        if let Some(parent) = p.parent() {
            // Check for sibling _test file
            let test_mod = parent.join(format!("{}_test.rs", stem));
            if test_mod.is_file() {
                return Some(test_mod.to_string_lossy().to_string());
            }
        }
    }

    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn test_handle_non_write_edit_returns_null() {
        let input = json!({"tool_name": "Bash", "tool_input": {"command": "ls"}});
        let (output, code) = handle(&input);
        assert!(output.is_null());
        assert_eq!(code, 0);
    }

    #[test]
    fn test_handle_no_file_path_returns_null() {
        let input = json!({"tool_name": "Write"});
        let (output, code) = handle(&input);
        assert!(output.is_null());
        assert_eq!(code, 0);
    }

    #[test]
    fn test_is_non_source_file_test_files() {
        assert!(is_non_source_file("/project/tests/foo.bats"));
        assert!(is_non_source_file("/project/src/foo_test.rs"));
        assert!(is_non_source_file("/project/test/bar.py"));
    }

    #[test]
    fn test_is_non_source_file_planning() {
        assert!(is_non_source_file("/project/.yolo-planning/PLAN.md"));
        assert!(is_non_source_file("/project/.vbw-planning/config.json"));
    }

    #[test]
    fn test_is_non_source_file_config() {
        assert!(is_non_source_file("/project/config.json"));
        assert!(is_non_source_file("/project/Cargo.toml"));
        assert!(is_non_source_file("/project/README.md"));
    }

    #[test]
    fn test_is_non_source_file_source_files() {
        assert!(!is_non_source_file("/project/src/main.rs"));
        assert!(!is_non_source_file("/project/src/hooks/dispatcher.rs"));
        assert!(!is_non_source_file("/project/scripts/deploy.sh"));
    }

    #[test]
    fn test_find_test_file_no_tests_dir() {
        // Non-existent paths won't find test files
        let result = find_test_file("/nonexistent/project/src/main.rs");
        assert!(result.is_none());
    }

    #[test]
    fn test_handle_always_exits_0() {
        // Even with Write/Edit, always advisory (exit 0)
        let input = json!({
            "tool_name": "Write",
            "tool_input": {"file_path": "/project/src/main.rs"}
        });
        let (_, code) = handle(&input);
        assert_eq!(code, 0);
    }

    #[test]
    fn test_handle_skips_non_source_write() {
        let input = json!({
            "tool_name": "Write",
            "tool_input": {"file_path": "/project/README.md"}
        });
        let (output, code) = handle(&input);
        assert!(output.is_null());
        assert_eq!(code, 0);
    }
}
