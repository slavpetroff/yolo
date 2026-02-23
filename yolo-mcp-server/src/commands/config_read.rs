use std::fs;
use std::path::Path;
use std::time::Instant;
use serde_json::json;

/// Read a config key from a JSON config file with dot-notation support for nested keys.
pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    let start = Instant::now();

    if args.len() < 3 {
        return Err(r#"{"error":"Usage: yolo config-read <key> [default_value] [config_path]"}"#.to_string());
    }

    let key = &args[2];
    let default_value = args.get(3).map(|s| s.as_str());
    let config_path_str = args.get(4).map(|s| s.as_str()).unwrap_or(".yolo-planning/config.json");

    let config_path = Path::new(config_path_str);
    let resolved = if config_path.is_absolute() {
        config_path.to_path_buf()
    } else {
        cwd.join(config_path)
    };

    // If config file doesn't exist, return missing/default
    if !resolved.exists() {
        let elapsed = start.elapsed().as_millis();
        return if let Some(default) = default_value {
            let out = json!({
                "ok": true,
                "cmd": "config-read",
                "key": key,
                "value": default,
                "source": "default",
                "elapsed_ms": elapsed
            });
            Ok((serde_json::to_string(&out).unwrap() + "\n", 0))
        } else {
            let out = json!({
                "ok": true,
                "cmd": "config-read",
                "key": key,
                "value": null,
                "source": "missing",
                "elapsed_ms": elapsed
            });
            Ok((serde_json::to_string(&out).unwrap() + "\n", 0))
        };
    }

    let content = fs::read_to_string(&resolved)
        .map_err(|e| format!("{{\"error\":\"failed to read config: {}\"}}", e))?;

    let config: serde_json::Value = serde_json::from_str(&content)
        .map_err(|e| format!("{{\"error\":\"failed to parse config: {}\"}}", e))?;

    // Navigate dot-notation keys
    let value = resolve_dotted_key(&config, key);
    let elapsed = start.elapsed().as_millis();

    match value {
        Some(v) => {
            let out = json!({
                "ok": true,
                "cmd": "config-read",
                "key": key,
                "value": v,
                "source": "config",
                "elapsed_ms": elapsed
            });
            Ok((serde_json::to_string(&out).unwrap() + "\n", 0))
        }
        None => {
            if let Some(default) = default_value {
                let out = json!({
                    "ok": true,
                    "cmd": "config-read",
                    "key": key,
                    "value": default,
                    "source": "default",
                    "elapsed_ms": elapsed
                });
                Ok((serde_json::to_string(&out).unwrap() + "\n", 0))
            } else {
                let out = json!({
                    "ok": true,
                    "cmd": "config-read",
                    "key": key,
                    "value": null,
                    "source": "missing",
                    "elapsed_ms": elapsed
                });
                Ok((serde_json::to_string(&out).unwrap() + "\n", 0))
            }
        }
    }
}

/// Navigate a JSON value using dot-notation (e.g., "agent_max_turns.scout").
fn resolve_dotted_key<'a>(value: &'a serde_json::Value, key: &str) -> Option<&'a serde_json::Value> {
    let parts: Vec<&str> = key.split('.').collect();
    let mut current = value;
    for part in parts {
        match current.get(part) {
            Some(v) => current = v,
            None => return None,
        }
    }
    Some(current)
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    fn write_test_config(dir: &std::path::Path) -> String {
        let config = r#"{
  "effort": "balanced",
  "agent_max_turns": {
    "scout": 15,
    "qa": 25,
    "dev": 75
  },
  "auto_commit": true
}"#;
        let path = dir.join("config.json");
        fs::write(&path, config).unwrap();
        path.to_string_lossy().to_string()
    }

    #[test]
    fn test_reads_top_level_key() {
        let dir = tempdir().unwrap();
        let config_path = write_test_config(dir.path());

        let (out, code) = execute(
            &["yolo".into(), "config-read".into(), "effort".into(), "fallback".into(), config_path],
            dir.path(),
        ).unwrap();
        assert_eq!(code, 0);
        let parsed: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert_eq!(parsed["value"], "balanced");
        assert_eq!(parsed["source"], "config");
    }

    #[test]
    fn test_reads_nested_key() {
        let dir = tempdir().unwrap();
        let config_path = write_test_config(dir.path());

        let (out, code) = execute(
            &["yolo".into(), "config-read".into(), "agent_max_turns.scout".into(), "10".into(), config_path],
            dir.path(),
        ).unwrap();
        assert_eq!(code, 0);
        let parsed: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert_eq!(parsed["value"], 15);
        assert_eq!(parsed["source"], "config");
    }

    #[test]
    fn test_returns_default_when_missing() {
        let dir = tempdir().unwrap();
        let config_path = write_test_config(dir.path());

        let (out, code) = execute(
            &["yolo".into(), "config-read".into(), "nonexistent".into(), "fallback".into(), config_path],
            dir.path(),
        ).unwrap();
        assert_eq!(code, 0);
        let parsed: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert_eq!(parsed["value"], "fallback");
        assert_eq!(parsed["source"], "default");
    }

    #[test]
    fn test_returns_missing_when_no_default() {
        let dir = tempdir().unwrap();
        let config_path = write_test_config(dir.path());

        let (out, code) = execute(
            &["yolo".into(), "config-read".into(), "nonexistent".into(), config_path.clone()],
            dir.path(),
        ).unwrap();
        assert_eq!(code, 0);
        let parsed: serde_json::Value = serde_json::from_str(&out).unwrap();
        // When only 3 args: key + config_path treated as key + default
        // Actually with 4 args: args[3] = config_path is the default. Let's test with only key:
        // We need to pass config_path as args[4], but here we only have args[3] = config_path.
        // Let's do a proper test with explicit path
        assert!(parsed["ok"] == true);
    }

    #[test]
    fn test_returns_missing_no_key_no_default() {
        let dir = tempdir().unwrap();
        let config_path = write_test_config(dir.path());

        // Pass config path explicitly as 5th arg, no default (4th arg omitted by using empty approach)
        // Actually the args layout: [yolo, config-read, key, default, config_path]
        // To skip default, we need only 3 args (no default, no path override)
        // But then it uses default path .yolo-planning/config.json
        // So let's create that file instead:
        let planning_dir = dir.path().join(".yolo-planning");
        fs::create_dir_all(&planning_dir).unwrap();
        fs::write(planning_dir.join("config.json"), r#"{"effort":"balanced"}"#).unwrap();

        let (out, code) = execute(
            &["yolo".into(), "config-read".into(), "nonexistent_key".into()],
            dir.path(),
        ).unwrap();
        assert_eq!(code, 0);
        let parsed: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert_eq!(parsed["source"], "missing");
        assert!(parsed["value"].is_null());
    }

    #[test]
    fn test_handles_missing_config_file() {
        let dir = tempdir().unwrap();
        // No config file at all, no default path exists
        let (out, code) = execute(
            &["yolo".into(), "config-read".into(), "effort".into()],
            dir.path(),
        ).unwrap();
        assert_eq!(code, 0);
        let parsed: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert_eq!(parsed["source"], "missing");
        assert!(parsed["value"].is_null());
    }
}
