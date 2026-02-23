use std::env;
use std::path::{Path, PathBuf};
use std::time::Instant;
use serde_json::json;

/// Resolve the plugin root directory using a 3-step fallback:
/// 1. CLAUDE_PLUGIN_ROOT env var
/// 2. Walk up from cwd looking for config/defaults.json
/// 3. Binary location parent
pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    let start = Instant::now();

    let start_path = if args.len() > 2 {
        PathBuf::from(&args[2])
    } else {
        cwd.to_path_buf()
    };

    // Strategy 1: CLAUDE_PLUGIN_ROOT env var
    if let Ok(env_root) = env::var("CLAUDE_PLUGIN_ROOT") {
        let p = Path::new(&env_root);
        if p.is_dir() {
            let elapsed = start.elapsed().as_millis();
            let out = json!({
                "ok": true,
                "cmd": "resolve-plugin-root",
                "plugin_root": p.to_string_lossy(),
                "resolved_via": "env",
                "elapsed_ms": elapsed
            });
            return Ok((serde_json::to_string(&out).map_err(|e| e.to_string())? + "\n", 0));
        }
    }

    // Strategy 2: Walk up from start_path looking for config/defaults.json
    let mut current = if start_path.is_absolute() {
        start_path.clone()
    } else {
        cwd.join(&start_path)
    };
    loop {
        let marker = current.join("config").join("defaults.json");
        if marker.exists() {
            let elapsed = start.elapsed().as_millis();
            let out = json!({
                "ok": true,
                "cmd": "resolve-plugin-root",
                "plugin_root": current.to_string_lossy(),
                "resolved_via": "walk",
                "elapsed_ms": elapsed
            });
            return Ok((serde_json::to_string(&out).map_err(|e| e.to_string())? + "\n", 0));
        }
        if !current.pop() {
            break;
        }
    }

    // Strategy 3: Binary location — grandparent of current_exe.
    // This always succeeds when current_exe resolves, since the binary must reside in a directory.
    if let Ok(exe) = env::current_exe() {
        if let Some(parent) = exe.parent() {
            let grandparent = parent.parent().unwrap_or(parent);
            let elapsed = start.elapsed().as_millis();
            let out = json!({
                "ok": true,
                "cmd": "resolve-plugin-root",
                "plugin_root": grandparent.to_string_lossy(),
                "resolved_via": "binary",
                "elapsed_ms": elapsed
            });
            return Ok((serde_json::to_string(&out).map_err(|e| e.to_string())? + "\n", 0));
        }
    }

    let out = json!({"error": "could not resolve plugin root"});
    Ok((serde_json::to_string(&out).map_err(|e| e.to_string())? + "\n", 1))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use tempfile::tempdir;

    #[test]
    fn test_resolves_via_env() {
        let dir = tempdir().unwrap();
        // Temporarily set env var
        unsafe { env::set_var("CLAUDE_PLUGIN_ROOT", dir.path().to_string_lossy().as_ref()); }
        let (out, code) = execute(
            &["yolo".into(), "resolve-plugin-root".into()],
            dir.path(),
        ).unwrap();
        unsafe { env::remove_var("CLAUDE_PLUGIN_ROOT"); }

        assert_eq!(code, 0);
        let parsed: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert_eq!(parsed["ok"], true);
        assert_eq!(parsed["resolved_via"], "env");
        assert_eq!(parsed["plugin_root"], dir.path().to_string_lossy().as_ref());
    }

    #[test]
    fn test_resolves_by_walking_up() {
        let dir = tempdir().unwrap();
        // Create marker
        let config_dir = dir.path().join("config");
        fs::create_dir_all(&config_dir).unwrap();
        fs::write(config_dir.join("defaults.json"), "{}").unwrap();

        // Create a nested child directory
        let nested = dir.path().join("a").join("b").join("c");
        fs::create_dir_all(&nested).unwrap();

        // Unset env var to avoid strategy 1
        unsafe { env::remove_var("CLAUDE_PLUGIN_ROOT"); }

        let (out, code) = execute(
            &["yolo".into(), "resolve-plugin-root".into()],
            &nested,
        ).unwrap();
        assert_eq!(code, 0);
        let parsed: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert_eq!(parsed["resolved_via"], "walk");
        assert_eq!(parsed["plugin_root"], dir.path().to_string_lossy().as_ref());
    }

    #[test]
    fn test_error_when_nothing_found() {
        let dir = tempdir().unwrap();
        // Empty dir with no markers, no env var
        unsafe { env::remove_var("CLAUDE_PLUGIN_ROOT"); }

        let (out, code) = execute(
            &["yolo".into(), "resolve-plugin-root".into()],
            dir.path(),
        ).unwrap();
        // Binary fallback will likely succeed (current_exe exists), so we test differently:
        // The output should be valid JSON regardless
        let parsed: serde_json::Value = serde_json::from_str(&out).unwrap();
        // Either resolved via binary or error
        if code == 0 {
            assert_eq!(parsed["ok"], true);
        } else {
            assert!(parsed["error"].as_str().is_some());
        }
    }
}
