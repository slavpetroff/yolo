use chrono::Utc;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::fs;
use std::io::Write;
use std::path::Path;

/// Register an artifact: compute SHA-256 checksum and append to registry.jsonl.
pub fn register(
    artifact_path: &str,
    event_id: &str,
    phase: u64,
    plan: u64,
    cwd: &Path,
) -> Result<Value, String> {
    if !is_enabled(cwd) {
        return Ok(json!({"result": "skipped", "reason": "v2_two_phase_completion=false"}));
    }

    let artifacts_dir = cwd.join(".yolo-planning/.artifacts");
    fs::create_dir_all(&artifacts_dir)
        .map_err(|e| format!("Failed to create artifacts dir: {}", e))?;

    // Compute checksum if file exists
    let checksum = compute_sha256(cwd, artifact_path);

    let ts = Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string();

    let entry = json!({
        "path": artifact_path,
        "checksum": checksum,
        "event_id": event_id,
        "phase": phase,
        "plan": plan,
        "registered_at": ts,
    });

    // Append to registry
    let registry_file = artifacts_dir.join("registry.jsonl");
    let line = format!("{}\n", serde_json::to_string(&entry).unwrap_or_default());

    let mut file = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&registry_file)
        .map_err(|e| format!("Failed to open registry: {}", e))?;

    file.write_all(line.as_bytes())
        .map_err(|e| format!("Failed to write registry: {}", e))?;

    Ok(json!({
        "result": "registered",
        "path": artifact_path,
        "checksum": checksum,
    }))
}

/// Query artifacts by path. Returns all matching entries.
pub fn query(path: &str, cwd: &Path) -> Result<Value, String> {
    if !is_enabled(cwd) {
        return Ok(json!({"result": "skipped", "reason": "v2_two_phase_completion=false"}));
    }

    let registry_file = cwd.join(".yolo-planning/.artifacts/registry.jsonl");
    if !registry_file.exists() {
        return Ok(json!({"result": "not_found", "entries": []}));
    }

    let entries = read_registry(&registry_file)?;
    let matched: Vec<&Value> = entries
        .iter()
        .filter(|e| e.get("path").and_then(|v| v.as_str()) == Some(path))
        .collect();

    if matched.is_empty() {
        Ok(json!({"result": "not_found", "entries": []}))
    } else {
        Ok(json!({
            "result": "found",
            "count": matched.len(),
            "entries": matched,
        }))
    }
}

/// List all artifacts, optionally filtered by phase.
pub fn list(phase_filter: Option<u64>, cwd: &Path) -> Result<Value, String> {
    if !is_enabled(cwd) {
        return Ok(json!({"result": "skipped", "reason": "v2_two_phase_completion=false"}));
    }

    let registry_file = cwd.join(".yolo-planning/.artifacts/registry.jsonl");
    if !registry_file.exists() {
        return Ok(json!({"result": "empty", "entries": []}));
    }

    let entries = read_registry(&registry_file)?;

    let filtered: Vec<&Value> = match phase_filter {
        Some(p) => entries
            .iter()
            .filter(|e| e.get("phase").and_then(|v| v.as_u64()) == Some(p))
            .collect(),
        None => entries.iter().collect(),
    };

    Ok(json!({
        "result": "ok",
        "count": filtered.len(),
        "entries": filtered,
    }))
}

/// Check if v2_two_phase_completion is enabled in config.
fn is_enabled(cwd: &Path) -> bool {
    let config_path = cwd.join(".yolo-planning/config.json");
    if !config_path.exists() {
        return false;
    }
    fs::read_to_string(&config_path)
        .ok()
        .and_then(|s| serde_json::from_str::<Value>(&s).ok())
        .and_then(|v| v.get("v2_two_phase_completion").and_then(|v| v.as_bool()))
        .unwrap_or(false)
}

/// Compute SHA-256 of a file. Returns hex string or empty string if file doesn't exist.
fn compute_sha256(cwd: &Path, artifact_path: &str) -> String {
    let full_path = cwd.join(artifact_path);
    if !full_path.exists() {
        return String::new();
    }
    match fs::read(&full_path) {
        Ok(bytes) => {
            let mut hasher = Sha256::new();
            hasher.update(&bytes);
            format!("{:x}", hasher.finalize())
        }
        Err(_) => String::new(),
    }
}

/// Read all entries from registry.jsonl.
fn read_registry(path: &Path) -> Result<Vec<Value>, String> {
    let content =
        fs::read_to_string(path).map_err(|e| format!("Failed to read registry: {}", e))?;

    Ok(content
        .lines()
        .filter(|l| !l.trim().is_empty())
        .filter_map(|l| serde_json::from_str::<Value>(l).ok())
        .collect())
}

/// CLI entry point: `yolo artifact <register|query|list> [args...]`
pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    if args.len() < 3 {
        return Err(
            "Usage: yolo artifact <register|query|list> [args...]".to_string(),
        );
    }

    let subcommand = &args[2];
    let result = match subcommand.as_str() {
        "register" => {
            if args.len() < 5 {
                return Err(
                    "Usage: yolo artifact register <path> <event_id> [phase] [plan]".to_string(),
                );
            }
            let path = &args[3];
            let event_id = &args[4];
            let phase: u64 = args.get(5).and_then(|s| s.parse().ok()).unwrap_or(0);
            let plan: u64 = args.get(6).and_then(|s| s.parse().ok()).unwrap_or(0);
            register(path, event_id, phase, plan, cwd)?
        }
        "query" => {
            if args.len() < 4 {
                return Err("Usage: yolo artifact query <path>".to_string());
            }
            query(&args[3], cwd)?
        }
        "list" => {
            let phase_filter = args.get(3).and_then(|s| s.parse::<u64>().ok());
            list(phase_filter, cwd)?
        }
        _ => {
            return Err(format!("Unknown artifact command: {}", subcommand));
        }
    };

    let output = serde_json::to_string(&result)
        .map_err(|e| format!("Failed to serialize: {}", e))?;

    Ok((output, 0))
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn setup_enabled(dir: &Path) {
        let planning = dir.join(".yolo-planning");
        fs::create_dir_all(&planning).unwrap();
        fs::write(
            planning.join("config.json"),
            r#"{"v2_two_phase_completion": true}"#,
        )
        .unwrap();
    }

    fn setup_disabled(dir: &Path) {
        let planning = dir.join(".yolo-planning");
        fs::create_dir_all(&planning).unwrap();
        fs::write(
            planning.join("config.json"),
            r#"{"v2_two_phase_completion": false}"#,
        )
        .unwrap();
    }

    #[test]
    fn test_register_when_disabled() {
        let dir = TempDir::new().unwrap();
        setup_disabled(dir.path());

        let result = register("test.rs", "evt-1", 1, 1, dir.path()).unwrap();
        assert_eq!(result["result"], "skipped");
    }

    #[test]
    fn test_register_basic() {
        let dir = TempDir::new().unwrap();
        setup_enabled(dir.path());

        // Create a test file to hash
        fs::write(dir.path().join("test.txt"), "hello world").unwrap();

        let result = register("test.txt", "evt-1", 1, 2, dir.path()).unwrap();
        assert_eq!(result["result"], "registered");
        assert_eq!(result["path"], "test.txt");
        assert!(!result["checksum"].as_str().unwrap().is_empty());

        // Verify registry file
        let registry = dir.path().join(".yolo-planning/.artifacts/registry.jsonl");
        assert!(registry.exists());
        let content = fs::read_to_string(&registry).unwrap();
        let entry: Value = serde_json::from_str(content.trim()).unwrap();
        assert_eq!(entry["event_id"], "evt-1");
        assert_eq!(entry["phase"], 1);
        assert_eq!(entry["plan"], 2);
    }

    #[test]
    fn test_register_missing_file() {
        let dir = TempDir::new().unwrap();
        setup_enabled(dir.path());

        let result = register("nonexistent.rs", "evt-2", 1, 1, dir.path()).unwrap();
        assert_eq!(result["result"], "registered");
        assert_eq!(result["checksum"], "");
    }

    #[test]
    fn test_query_not_found() {
        let dir = TempDir::new().unwrap();
        setup_enabled(dir.path());

        let result = query("missing.rs", dir.path()).unwrap();
        assert_eq!(result["result"], "not_found");
    }

    #[test]
    fn test_query_found() {
        let dir = TempDir::new().unwrap();
        setup_enabled(dir.path());

        // Register first
        let _ = register("src/main.rs", "evt-1", 1, 1, dir.path()).unwrap();

        let result = query("src/main.rs", dir.path()).unwrap();
        assert_eq!(result["result"], "found");
        assert_eq!(result["count"], 1);
    }

    #[test]
    fn test_list_empty() {
        let dir = TempDir::new().unwrap();
        setup_enabled(dir.path());

        let result = list(None, dir.path()).unwrap();
        assert_eq!(result["result"], "empty");
    }

    #[test]
    fn test_list_all() {
        let dir = TempDir::new().unwrap();
        setup_enabled(dir.path());

        let _ = register("a.rs", "evt-1", 1, 1, dir.path()).unwrap();
        let _ = register("b.rs", "evt-2", 2, 1, dir.path()).unwrap();

        let result = list(None, dir.path()).unwrap();
        assert_eq!(result["result"], "ok");
        assert_eq!(result["count"], 2);
    }

    #[test]
    fn test_list_phase_filter() {
        let dir = TempDir::new().unwrap();
        setup_enabled(dir.path());

        let _ = register("a.rs", "evt-1", 1, 1, dir.path()).unwrap();
        let _ = register("b.rs", "evt-2", 2, 1, dir.path()).unwrap();

        let result = list(Some(1), dir.path()).unwrap();
        assert_eq!(result["result"], "ok");
        assert_eq!(result["count"], 1);
        assert_eq!(result["entries"][0]["path"], "a.rs");
    }

    #[test]
    fn test_checksum_deterministic() {
        let dir = TempDir::new().unwrap();
        fs::write(dir.path().join("file.txt"), "test content").unwrap();

        let hash1 = compute_sha256(dir.path(), "file.txt");
        let hash2 = compute_sha256(dir.path(), "file.txt");
        assert_eq!(hash1, hash2);
        assert!(!hash1.is_empty());
    }

    #[test]
    fn test_execute_cli_register() {
        let dir = TempDir::new().unwrap();
        setup_enabled(dir.path());

        let args: Vec<String> = vec![
            "yolo".into(),
            "artifact".into(),
            "register".into(),
            "test.rs".into(),
            "evt-99".into(),
            "1".into(),
            "2".into(),
        ];
        let (output, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
        assert!(output.contains("registered"));
    }

    #[test]
    fn test_execute_cli_query() {
        let dir = TempDir::new().unwrap();
        setup_enabled(dir.path());

        let args: Vec<String> = vec![
            "yolo".into(),
            "artifact".into(),
            "query".into(),
            "test.rs".into(),
        ];
        let (output, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
        assert!(output.contains("not_found"));
    }

    #[test]
    fn test_execute_cli_list() {
        let dir = TempDir::new().unwrap();
        setup_enabled(dir.path());

        let args: Vec<String> = vec!["yolo".into(), "artifact".into(), "list".into()];
        let (output, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
        assert!(output.contains("empty"));
    }

    #[test]
    fn test_execute_cli_missing_subcommand() {
        let dir = TempDir::new().unwrap();
        let args: Vec<String> = vec!["yolo".into(), "artifact".into()];
        assert!(execute(&args, dir.path()).is_err());
    }

    #[test]
    fn test_execute_cli_unknown_subcommand() {
        let dir = TempDir::new().unwrap();
        let args: Vec<String> = vec!["yolo".into(), "artifact".into(), "delete".into()];
        assert!(execute(&args, dir.path()).is_err());
    }
}
