use regex::Regex;
use std::fs;
use std::path::Path;
use std::sync::OnceLock;
use std::time::SystemTime;

use super::types::{HookInput, HookOutput, SecurityFilterInput};

/// Sensitive file patterns that must be blocked.
const SENSITIVE_PATTERN: &str = r"\.env$|\.env\.|\.pem$|\.key$|\.cert$|\.p12$|\.pfx$|credentials\.json$|secrets\.json$|service-account.*\.json$|node_modules/|\.git/|dist/|build/";

/// Maximum marker age in seconds (24 hours).
const MARKER_MAX_AGE_SECS: u64 = 86400;

/// PreToolUse handler: block access to sensitive files and enforce GSD isolation.
///
/// Fail-CLOSED: returns exit 2 on any parse error (never allow unvalidated input through).
/// Extracts `file_path` from `tool_input.file_path`, `tool_input.path`, or `tool_input.pattern`.
pub fn handle(input: &HookInput) -> Result<HookOutput, String> {
    let typed = SecurityFilterInput::from_hook_input(input);

    // Skip file-path validation for tools that don't operate on files (e.g., Bash)
    let tool_name = typed.tool_name.as_deref().unwrap_or("");
    if tool_name == "Bash" {
        return Ok(HookOutput::empty());
    }

    // Prefer typed tool_input fields, fall back to raw extraction
    let file_path = typed
        .tool_input
        .as_ref()
        .and_then(|ti| {
            ti.file_path
                .as_deref()
                .filter(|s| !s.is_empty())
                .or(ti.path.as_deref().filter(|s| !s.is_empty()))
                .or(ti.pattern.as_deref().filter(|s| !s.is_empty()))
                .map(|s| s.to_string())
        })
        .or_else(|| extract_file_path(&input.data));

    // Fail-closed: if we can't extract a path, block
    let file_path = match file_path {
        Some(p) if !p.is_empty() => p,
        _ => return Ok(deny("Blocked: cannot extract file path from tool input")),
    };

    // Check sensitive file patterns
    fn get_sensitive_re() -> &'static Regex {
        static RE: OnceLock<Regex> = OnceLock::new();
        RE.get_or_init(|| Regex::new(SENSITIVE_PATTERN).unwrap())
    }

    if get_sensitive_re().is_match(&file_path) {
        return Ok(deny(&format!("Blocked: sensitive file ({})", file_path)));
    }

    // GSD isolation: block .planning/ when YOLO is actively running
    if file_path.contains(".planning/") && !file_path.contains(".yolo-planning/") {
        let project_root = derive_project_root(&file_path, ".planning");
        let yolo_dir = Path::new(&project_root).join(".yolo-planning");

        let active_agent_fresh = is_marker_fresh(&yolo_dir.join(".active-agent"));
        let yolo_session_fresh = is_marker_fresh(&yolo_dir.join(".yolo-session"));

        if active_agent_fresh || yolo_session_fresh {
            return Ok(deny(&format!(
                "Blocked: .planning/ is managed by GSD, not YOLO ({})",
                file_path
            )));
        }
    }

    Ok(HookOutput::empty())
}

/// Extract file path from tool_input, checking file_path, path, and pattern fields.
fn extract_file_path(data: &serde_json::Value) -> Option<String> {
    let tool_input = data.get("tool_input")?;

    for key in &["file_path", "path", "pattern"] {
        if let Some(val) = tool_input.get(key).and_then(|v| v.as_str())
            && !val.is_empty()
        {
            return Some(val.to_string());
        }
    }

    None
}

/// Check if a marker file exists and is less than 24 hours old.
fn is_marker_fresh(marker: &Path) -> bool {
    let metadata = match fs::metadata(marker) {
        Ok(m) => m,
        Err(_) => return false,
    };

    let modified = match metadata.modified() {
        Ok(t) => t,
        Err(_) => return false,
    };

    let age = SystemTime::now()
        .duration_since(modified)
        .unwrap_or_default();

    age.as_secs() < MARKER_MAX_AGE_SECS
}

/// Derive project root by finding the path segment before the marker directory.
fn derive_project_root(path: &str, marker_dir: &str) -> String {
    let needle = format!("/{}/", marker_dir);
    if let Some(idx) = path.find(&needle) {
        if idx == 0 {
            return ".".to_string();
        }
        return path[..idx].to_string();
    }

    // Try without leading slash (relative path)
    let needle_rel = format!("{}/", marker_dir);
    if path.starts_with(&needle_rel) {
        return ".".to_string();
    }

    ".".to_string()
}

/// Build a deny HookOutput with permissionDecision JSON.
fn deny(message: &str) -> HookOutput {
    eprintln!("{}", message);
    let json = serde_json::json!({
        "permissionDecision": "deny",
        "message": message
    });
    HookOutput::block(json.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn make_input(tool_input: serde_json::Value) -> HookInput {
        HookInput {
            data: json!({ "tool_input": tool_input }),
        }
    }

    #[test]
    fn test_block_env_file() {
        let input = make_input(json!({ "file_path": "/project/.env" }));
        let result = handle(&input).unwrap();
        assert_eq!(result.exit_code, 2);
        assert!(result.stdout.contains("deny"));
    }

    #[test]
    fn test_block_env_dotfile() {
        let input = make_input(json!({ "file_path": "/project/.env.local" }));
        let result = handle(&input).unwrap();
        assert_eq!(result.exit_code, 2);
    }

    #[test]
    fn test_block_pem_file() {
        let input = make_input(json!({ "file_path": "/project/certs/server.pem" }));
        let result = handle(&input).unwrap();
        assert_eq!(result.exit_code, 2);
    }

    #[test]
    fn test_block_key_file() {
        let input = make_input(json!({ "file_path": "/project/private.key" }));
        let result = handle(&input).unwrap();
        assert_eq!(result.exit_code, 2);
    }

    #[test]
    fn test_block_cert_file() {
        let input = make_input(json!({ "file_path": "/project/ssl.cert" }));
        let result = handle(&input).unwrap();
        assert_eq!(result.exit_code, 2);
    }

    #[test]
    fn test_block_p12_file() {
        let input = make_input(json!({ "file_path": "/project/keystore.p12" }));
        let result = handle(&input).unwrap();
        assert_eq!(result.exit_code, 2);
    }

    #[test]
    fn test_block_pfx_file() {
        let input = make_input(json!({ "file_path": "/project/cert.pfx" }));
        let result = handle(&input).unwrap();
        assert_eq!(result.exit_code, 2);
    }

    #[test]
    fn test_block_credentials_json() {
        let input = make_input(json!({ "file_path": "/project/credentials.json" }));
        let result = handle(&input).unwrap();
        assert_eq!(result.exit_code, 2);
    }

    #[test]
    fn test_block_secrets_json() {
        let input = make_input(json!({ "file_path": "/project/secrets.json" }));
        let result = handle(&input).unwrap();
        assert_eq!(result.exit_code, 2);
    }

    #[test]
    fn test_block_service_account_json() {
        let input = make_input(json!({ "file_path": "/project/service-account-prod.json" }));
        let result = handle(&input).unwrap();
        assert_eq!(result.exit_code, 2);
    }

    #[test]
    fn test_block_node_modules() {
        let input = make_input(json!({ "file_path": "/project/node_modules/pkg/index.js" }));
        let result = handle(&input).unwrap();
        assert_eq!(result.exit_code, 2);
    }

    #[test]
    fn test_block_git_dir() {
        let input = make_input(json!({ "file_path": "/project/.git/config" }));
        let result = handle(&input).unwrap();
        assert_eq!(result.exit_code, 2);
    }

    #[test]
    fn test_block_dist_dir() {
        let input = make_input(json!({ "file_path": "/project/dist/bundle.js" }));
        let result = handle(&input).unwrap();
        assert_eq!(result.exit_code, 2);
    }

    #[test]
    fn test_block_build_dir() {
        let input = make_input(json!({ "file_path": "/project/build/output.js" }));
        let result = handle(&input).unwrap();
        assert_eq!(result.exit_code, 2);
    }

    #[test]
    fn test_allow_normal_file() {
        let input = make_input(json!({ "file_path": "/project/src/main.rs" }));
        let result = handle(&input).unwrap();
        assert_eq!(result.exit_code, 0);
        assert!(result.stdout.is_empty());
    }

    #[test]
    fn test_allow_yolo_planning() {
        let input = make_input(json!({ "file_path": "/project/.yolo-planning/state.json" }));
        let result = handle(&input).unwrap();
        assert_eq!(result.exit_code, 0);
    }

    #[test]
    fn test_extract_from_path_field() {
        let input = make_input(json!({ "path": "/project/src/lib.rs" }));
        let result = handle(&input).unwrap();
        assert_eq!(result.exit_code, 0);
    }

    #[test]
    fn test_extract_from_pattern_field() {
        let input = make_input(json!({ "pattern": "/project/src/**/*.rs" }));
        let result = handle(&input).unwrap();
        assert_eq!(result.exit_code, 0);
    }

    #[test]
    fn test_bash_tool_skips_file_path_check() {
        let input = HookInput {
            data: json!({ "tool_name": "Bash" }),
        };
        let result = handle(&input).unwrap();
        assert_eq!(result.exit_code, 0, "Bash tool should skip file path validation");
    }

    #[test]
    fn test_fail_closed_no_tool_input() {
        let input = HookInput {
            data: json!({ "tool_name": "Read" }),
        };
        let result = handle(&input).unwrap();
        assert_eq!(result.exit_code, 2);
    }

    #[test]
    fn test_fail_closed_empty_file_path() {
        let input = make_input(json!({ "file_path": "" }));
        let result = handle(&input).unwrap();
        assert_eq!(result.exit_code, 2);
    }

    #[test]
    fn test_fail_closed_no_path_fields() {
        let input = make_input(json!({ "command": "ls -la" }));
        let result = handle(&input).unwrap();
        assert_eq!(result.exit_code, 2);
    }

    #[test]
    fn test_derive_project_root_absolute() {
        assert_eq!(
            derive_project_root("/home/user/project/.planning/state.json", ".planning"),
            "/home/user/project"
        );
    }

    #[test]
    fn test_derive_project_root_relative() {
        assert_eq!(
            derive_project_root(".planning/state.json", ".planning"),
            "."
        );
    }

    #[test]
    fn test_derive_project_root_no_match() {
        assert_eq!(derive_project_root("/some/other/path", ".planning"), ".");
    }

    #[test]
    fn test_gsd_isolation_no_markers() {
        // Without markers, .planning/ access should be allowed
        let input = make_input(json!({ "file_path": "/tmp/nonexistent-test/.planning/state.json" }));
        let result = handle(&input).unwrap();
        assert_eq!(result.exit_code, 0);
    }

    #[test]
    fn test_gsd_isolation_with_fresh_markers() {
        let tmp = tempfile::TempDir::new().unwrap();
        let yolo_dir = tmp.path().join(".yolo-planning");
        fs::create_dir_all(&yolo_dir).unwrap();
        fs::write(yolo_dir.join(".yolo-session"), "session").unwrap();

        let planning_path = format!("{}/.planning/state.json", tmp.path().display());
        let input = make_input(json!({ "file_path": planning_path }));
        let result = handle(&input).unwrap();
        assert_eq!(result.exit_code, 2);
        assert!(result.stdout.contains("deny"));
    }

    #[test]
    fn test_is_marker_fresh_nonexistent() {
        assert!(!is_marker_fresh(Path::new("/tmp/nonexistent-marker-test-xyz")));
    }

    #[test]
    fn test_is_marker_fresh_exists() {
        let tmp = tempfile::TempDir::new().unwrap();
        let marker = tmp.path().join("test-marker");
        fs::write(&marker, "test").unwrap();
        assert!(is_marker_fresh(&marker));
    }

    #[test]
    fn test_deny_output_format() {
        let output = deny("test message");
        assert_eq!(output.exit_code, 2);
        let parsed: serde_json::Value = serde_json::from_str(&output.stdout).unwrap();
        assert_eq!(parsed["permissionDecision"], "deny");
        assert_eq!(parsed["message"], "test message");
    }

    #[test]
    fn test_file_path_priority() {
        // file_path takes precedence over path and pattern
        let input = make_input(json!({
            "file_path": "/project/.env",
            "path": "/project/src/main.rs",
            "pattern": "/project/src/**/*.rs"
        }));
        let result = handle(&input).unwrap();
        assert_eq!(result.exit_code, 2); // .env should be blocked
    }

    #[test]
    fn test_allow_env_in_directory_name() {
        // A directory named .env-config should not be blocked (the pattern targets files)
        // But .env.local IS blocked by \.env\. pattern
        let input = make_input(json!({ "file_path": "/project/src/environment.rs" }));
        let result = handle(&input).unwrap();
        assert_eq!(result.exit_code, 0);
    }

    #[test]
    fn test_block_nested_credentials() {
        let input = make_input(json!({ "file_path": "/project/config/credentials.json" }));
        let result = handle(&input).unwrap();
        assert_eq!(result.exit_code, 2);
    }

    #[test]
    fn test_block_service_account_with_env() {
        let input = make_input(json!({ "file_path": "/project/service-account-staging.json" }));
        let result = handle(&input).unwrap();
        assert_eq!(result.exit_code, 2);
    }

    #[test]
    fn test_allow_json_that_is_not_sensitive() {
        let input = make_input(json!({ "file_path": "/project/package.json" }));
        let result = handle(&input).unwrap();
        assert_eq!(result.exit_code, 0);
    }

    #[test]
    fn test_gsd_isolation_with_active_agent_marker() {
        let tmp = tempfile::TempDir::new().unwrap();
        let yolo_dir = tmp.path().join(".yolo-planning");
        fs::create_dir_all(&yolo_dir).unwrap();
        fs::write(yolo_dir.join(".active-agent"), "agent").unwrap();

        let planning_path = format!("{}/.planning/intel/index.md", tmp.path().display());
        let input = make_input(json!({ "file_path": planning_path }));
        let result = handle(&input).unwrap();
        assert_eq!(result.exit_code, 2);
    }

    #[test]
    fn test_yolo_planning_not_blocked() {
        // .yolo-planning/ paths should NEVER trigger GSD isolation
        let tmp = tempfile::TempDir::new().unwrap();
        let yolo_dir = tmp.path().join(".yolo-planning");
        fs::create_dir_all(&yolo_dir).unwrap();
        fs::write(yolo_dir.join(".yolo-session"), "session").unwrap();

        let yolo_path = format!("{}/.yolo-planning/state.json", tmp.path().display());
        let input = make_input(json!({ "file_path": yolo_path }));
        let result = handle(&input).unwrap();
        assert_eq!(result.exit_code, 0);
    }

    #[test]
    fn test_tool_input_null_value() {
        let input = HookInput {
            data: json!({ "tool_input": null }),
        };
        let result = handle(&input).unwrap();
        assert_eq!(result.exit_code, 2); // fail-closed
    }
}
