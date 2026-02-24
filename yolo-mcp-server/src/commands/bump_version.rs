use serde_json::{json, Value};
use std::fs;
use std::path::Path;
use std::time::Instant;

/// Read version from VERSION file, trimmed.
fn read_version_file(cwd: &Path) -> Result<String, String> {
    let path = cwd.join("VERSION");
    if !path.exists() {
        return Err("VERSION file not found".to_string());
    }
    Ok(fs::read_to_string(&path)
        .map_err(|e| format!("Failed to read VERSION: {}", e))?
        .trim()
        .to_string())
}

/// Extract version from a JSON file at a given JSON pointer path.
/// For plugin.json: pointer = "/version"
/// For marketplace.json: pointer = "/plugins/0/version"
fn read_json_version(path: &Path, pointer: &str) -> Result<String, String> {
    if !path.exists() {
        return Err(format!("{} not found", path.display()));
    }
    let content = fs::read_to_string(path)
        .map_err(|e| format!("Failed to read {}: {}", path.display(), e))?;
    let val: Value = serde_json::from_str(&content)
        .map_err(|e| format!("Invalid JSON in {}: {}", path.display(), e))?;
    val.pointer(pointer)
        .and_then(|v| v.as_str())
        .map(|s| s.to_string())
        .ok_or_else(|| format!("Version field not found at {} in {}", pointer, path.display()))
}

/// Write a version string into a JSON file at the given pointer path.
fn write_json_version(path: &Path, pointer: &str, version: &str) -> Result<(), String> {
    let content = fs::read_to_string(path)
        .map_err(|e| format!("Failed to read {}: {}", path.display(), e))?;
    let mut val: Value = serde_json::from_str(&content)
        .map_err(|e| format!("Invalid JSON in {}: {}", path.display(), e))?;

    // Navigate the pointer and set the value
    let parts: Vec<&str> = pointer.trim_start_matches('/').split('/').collect();
    let mut current = &mut val;
    for (i, part) in parts.iter().enumerate() {
        if i == parts.len() - 1 {
            // Last part: set the value
            if let Ok(idx) = part.parse::<usize>() {
                current[idx] = Value::String(version.to_string());
            } else {
                current[*part] = Value::String(version.to_string());
            }
        } else {
            // Navigate deeper
            if let Ok(idx) = part.parse::<usize>() {
                current = &mut current[idx];
            } else {
                current = &mut current[*part];
            }
        }
    }

    let output = serde_json::to_string_pretty(&val)
        .map_err(|e| format!("Failed to serialize JSON: {}", e))?;
    fs::write(path, format!("{}\n", output))
        .map_err(|e| format!("Failed to write {}: {}", path.display(), e))?;
    Ok(())
}

/// Read version from a TOML file's [package] table.
fn read_toml_version(path: &Path) -> Result<String, String> {
    if !path.exists() {
        return Err(format!("{} not found", path.display()));
    }
    let content = fs::read_to_string(path)
        .map_err(|e| format!("Failed to read {}: {}", path.display(), e))?;
    let doc = content
        .parse::<toml_edit::DocumentMut>()
        .map_err(|e| format!("Invalid TOML in {}: {}", path.display(), e))?;
    doc.get("package")
        .and_then(|p| p.get("version"))
        .and_then(|v| v.as_str())
        .map(|s| s.to_string())
        .ok_or_else(|| format!("package.version not found in {}", path.display()))
}

/// Write version into a TOML file's [package] table, preserving formatting.
fn write_toml_version(path: &Path, version: &str) -> Result<(), String> {
    let content = fs::read_to_string(path)
        .map_err(|e| format!("Failed to read {}: {}", path.display(), e))?;
    let mut doc = content
        .parse::<toml_edit::DocumentMut>()
        .map_err(|e| format!("Invalid TOML in {}: {}", path.display(), e))?;
    doc["package"]["version"] = toml_edit::value(version);
    fs::write(path, doc.to_string())
        .map_err(|e| format!("Failed to write {}: {}", path.display(), e))?;
    Ok(())
}

/// Increment the patch component of a semver string.
fn increment_patch(version: &str) -> String {
    let parts: Vec<&str> = version.split('.').collect();
    if parts.len() == 3
        && let Ok(patch) = parts[2].parse::<u64>() {
            return format!("{}.{}.{}", parts[0], parts[1], patch + 1);
    }
    // Fallback: append .1
    format!("{}.1", version)
}

/// Increment the major component: X.Y.Z -> (X+1).0.0
fn increment_major(version: &str) -> String {
    let parts: Vec<&str> = version.split('.').collect();
    if !parts.is_empty() {
        if let Ok(major) = parts[0].parse::<u64>() {
            return format!("{}.0.0", major + 1);
        }
    }
    format!("{}.1", version)
}

/// Increment the minor component: X.Y.Z -> X.(Y+1).0
fn increment_minor(version: &str) -> String {
    let parts: Vec<&str> = version.split('.').collect();
    if parts.len() >= 2 {
        if let Ok(major) = parts[0].parse::<u64>() {
            if let Ok(minor) = parts[1].parse::<u64>() {
                return format!("{}.{}.0", major, minor + 1);
            }
        }
    }
    format!("{}.1", version)
}

/// Return the higher of two semver strings.
fn max_version<'a>(a: &'a str, b: &'a str) -> &'a str {
    let parse = |v: &str| -> (u64, u64, u64) {
        let parts: Vec<&str> = v.split('.').collect();
        let major = parts.first().and_then(|p| p.parse().ok()).unwrap_or(0);
        let minor = parts.get(1).and_then(|p| p.parse().ok()).unwrap_or(0);
        let patch = parts.get(2).and_then(|p| p.parse().ok()).unwrap_or(0);
        (major, minor, patch)
    };
    if parse(a) >= parse(b) { a } else { b }
}

/// All version file locations (relative to cwd).
struct VersionFiles {
    version_file: &'static str,
    json_files: Vec<(&'static str, &'static str)>, // (path, json_pointer)
    toml_files: Vec<&'static str>,
}

fn version_files() -> VersionFiles {
    VersionFiles {
        version_file: "VERSION",
        json_files: vec![
            (".claude-plugin/plugin.json", "/version"),
            ("marketplace.json", "/plugins/0/version"),
        ],
        toml_files: vec!["yolo-mcp-server/Cargo.toml"],
    }
}

/// Verify mode: read all version sources and report mismatches.
fn verify_versions(cwd: &Path, start: Instant) -> Result<(String, i32), String> {
    let vf = version_files();
    let mut versions: Vec<(String, String)> = Vec::new();
    let mut errors: Vec<String> = Vec::new();

    // Read VERSION file
    match read_version_file(cwd) {
        Ok(v) => versions.push(("VERSION".to_string(), v)),
        Err(e) => errors.push(e),
    }

    // Read JSON files
    for (path, pointer) in &vf.json_files {
        let full = cwd.join(path);
        match read_json_version(&full, pointer) {
            Ok(v) => versions.push((path.to_string(), v)),
            Err(e) => errors.push(e),
        }
    }

    // Read TOML files
    for path in &vf.toml_files {
        let full = cwd.join(path);
        match read_toml_version(&full) {
            Ok(v) => versions.push((path.to_string(), v)),
            Err(e) => errors.push(e),
        }
    }

    if versions.is_empty() {
        let response = json!({
            "ok": false,
            "cmd": "bump-version",
            "delta": { "mode": "verify", "versions": [], "all_match": false, "errors": errors },
            "elapsed_ms": start.elapsed().as_millis() as u64
        });
        return Ok((response.to_string(), 1));
    }

    let first_ver = &versions[0].1;
    let mut mismatch = false;
    let mut version_entries: Vec<Value> = Vec::new();

    for (file, ver) in &versions {
        let status = if ver == first_ver { "OK" } else { mismatch = true; "MISMATCH" };
        version_entries.push(json!({"file": file, "version": ver, "status": status}));
    }

    let all_match = !mismatch && errors.is_empty();
    let code = if all_match { 0 } else { 1 };

    let response = json!({
        "ok": all_match,
        "cmd": "bump-version",
        "delta": {
            "mode": "verify",
            "versions": version_entries,
            "all_match": all_match,
            "errors": errors
        },
        "elapsed_ms": start.elapsed().as_millis() as u64
    });

    Ok((response.to_string(), code))
}

/// Fetch remote VERSION from GitHub (raw content URL).
fn fetch_remote_version(offline: bool) -> Option<String> {
    if offline {
        return None;
    }
    let url = "https://raw.githubusercontent.com/slavpetroff/yolo/main/VERSION";
    let client = reqwest::blocking::Client::builder()
        .timeout(std::time::Duration::from_secs(5))
        .build()
        .ok()?;
    let resp = client.get(url).send().ok()?;
    if resp.status().is_success() {
        Some(resp.text().ok()?.trim().to_string())
    } else {
        None
    }
}

/// Bump mode: increment version, write to all files.
fn bump_version(
    cwd: &Path,
    offline: bool,
    major: bool,
    minor: bool,
    start: Instant,
) -> Result<(String, i32), String> {
    let local_version = read_version_file(cwd)?;

    let remote_version = fetch_remote_version(offline);
    let base_version = match &remote_version {
        Some(rv) => max_version(&local_version, rv),
        None => &local_version,
    };

    let new_version = if major {
        increment_major(base_version)
    } else if minor {
        increment_minor(base_version)
    } else {
        increment_patch(base_version)
    };
    let bump_type = if major {
        "major"
    } else if minor {
        "minor"
    } else {
        "patch"
    };

    let vf = version_files();
    let mut files_updated: Vec<Value> = Vec::new();
    let mut changed: Vec<String> = Vec::new();

    // Write VERSION file
    let version_path = cwd.join(vf.version_file);
    fs::write(&version_path, format!("{}\n", new_version))
        .map_err(|e| format!("Failed to write VERSION: {}", e))?;
    files_updated.push(json!({"path": vf.version_file, "old": local_version, "new": new_version}));
    changed.push(vf.version_file.to_string());

    // Write JSON files
    for (path, pointer) in &vf.json_files {
        let full = cwd.join(path);
        if full.exists() {
            let old = read_json_version(&full, pointer).unwrap_or_else(|_| "unknown".to_string());
            write_json_version(&full, pointer, &new_version)?;
            files_updated.push(json!({"path": path, "old": old, "new": new_version}));
            changed.push(path.to_string());
        }
    }

    // Write TOML files
    for path in &vf.toml_files {
        let full = cwd.join(path);
        if full.exists() {
            let old = read_toml_version(&full).unwrap_or_else(|_| "unknown".to_string());
            write_toml_version(&full, &new_version)?;
            files_updated.push(json!({"path": path, "old": old, "new": new_version}));
            changed.push(path.to_string());
        }
    }

    let response = json!({
        "ok": true,
        "cmd": "bump-version",
        "changed": changed,
        "delta": {
            "old_version": local_version,
            "new_version": new_version,
            "bump_type": bump_type,
            "remote_version": remote_version,
            "files_updated": files_updated
        },
        "elapsed_ms": start.elapsed().as_millis() as u64
    });

    Ok((response.to_string(), 0))
}

/// CLI entry point: `yolo bump-version [--verify] [--offline] [--major] [--minor]`
pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    let start = Instant::now();
    let verify = args.iter().any(|a| a == "--verify");
    let offline = args.iter().any(|a| a == "--offline");
    let major = args.iter().any(|a| a == "--major");
    let minor = args.iter().any(|a| a == "--minor");

    if major && minor {
        return Err("Cannot use both --major and --minor".to_string());
    }

    if verify {
        verify_versions(cwd, start)
    } else {
        bump_version(cwd, offline, major, minor, start)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn setup_test_env() -> TempDir {
        let dir = TempDir::new().unwrap();

        // VERSION file
        fs::write(dir.path().join("VERSION"), "1.2.3\n").unwrap();

        // .claude-plugin/plugin.json
        let plugin_dir = dir.path().join(".claude-plugin");
        fs::create_dir_all(&plugin_dir).unwrap();
        fs::write(
            plugin_dir.join("plugin.json"),
            serde_json::to_string_pretty(&json!({
                "name": "test",
                "version": "1.2.3"
            }))
            .unwrap(),
        )
        .unwrap();

        // Root marketplace.json
        fs::write(
            dir.path().join("marketplace.json"),
            serde_json::to_string_pretty(&json!({
                "plugins": [{"name": "test", "version": "1.2.3"}]
            }))
            .unwrap(),
        )
        .unwrap();

        // yolo-mcp-server/Cargo.toml
        let cargo_dir = dir.path().join("yolo-mcp-server");
        fs::create_dir_all(&cargo_dir).unwrap();
        fs::write(
            cargo_dir.join("Cargo.toml"),
            "[package]\nname = \"yolo-mcp-server\"\nversion = \"1.2.3\"\nedition = \"2024\"\n",
        )
        .unwrap();

        dir
    }

    #[test]
    fn test_verify_all_match() {
        let dir = setup_test_env();
        let (output, code) = verify_versions(dir.path(), Instant::now()).unwrap();
        assert_eq!(code, 0);
        let j: Value = serde_json::from_str(&output).unwrap();
        assert_eq!(j["ok"], true);
        assert_eq!(j["delta"]["mode"], "verify");
        assert_eq!(j["delta"]["all_match"], true);
        let versions = j["delta"]["versions"].as_array().unwrap();
        assert!(versions.iter().all(|v| v["status"] == "OK"));
    }

    #[test]
    fn test_verify_mismatch() {
        let dir = setup_test_env();
        fs::write(dir.path().join("VERSION"), "1.2.4\n").unwrap();
        let (output, code) = verify_versions(dir.path(), Instant::now()).unwrap();
        assert_eq!(code, 1);
        let j: Value = serde_json::from_str(&output).unwrap();
        assert_eq!(j["ok"], false);
        assert_eq!(j["delta"]["all_match"], false);
        let versions = j["delta"]["versions"].as_array().unwrap();
        assert!(versions.iter().any(|v| v["status"] == "MISMATCH"));
    }

    #[test]
    fn test_bump_offline() {
        let dir = setup_test_env();
        let (output, code) = bump_version(dir.path(), true, false, false, Instant::now()).unwrap();
        assert_eq!(code, 0);
        let j: Value = serde_json::from_str(&output).unwrap();
        assert_eq!(j["ok"], true);
        assert_eq!(j["cmd"], "bump-version");
        assert_eq!(j["delta"]["old_version"], "1.2.3");
        assert_eq!(j["delta"]["new_version"], "1.2.4");
        assert_eq!(j["delta"]["bump_type"], "patch");
        let files = j["delta"]["files_updated"].as_array().unwrap();
        assert!(files.iter().any(|f| f["path"] == "VERSION" && f["old"] == "1.2.3" && f["new"] == "1.2.4"));

        // Verify all files actually updated
        let new_ver = fs::read_to_string(dir.path().join("VERSION")).unwrap();
        assert_eq!(new_ver.trim(), "1.2.4");

        let plugin: Value = serde_json::from_str(
            &fs::read_to_string(dir.path().join(".claude-plugin/plugin.json")).unwrap(),
        )
        .unwrap();
        assert_eq!(plugin["version"], "1.2.4");

        let mp: Value = serde_json::from_str(
            &fs::read_to_string(dir.path().join("marketplace.json")).unwrap(),
        )
        .unwrap();
        assert_eq!(mp["plugins"][0]["version"], "1.2.4");

        // Verify Cargo.toml updated
        let cargo_content =
            fs::read_to_string(dir.path().join("yolo-mcp-server/Cargo.toml")).unwrap();
        assert!(cargo_content.contains("version = \"1.2.4\""));
    }

    #[test]
    fn test_increment_patch() {
        assert_eq!(increment_patch("1.2.3"), "1.2.4");
        assert_eq!(increment_patch("0.0.0"), "0.0.1");
        assert_eq!(increment_patch("10.20.99"), "10.20.100");
    }

    #[test]
    fn test_max_version() {
        assert_eq!(max_version("1.2.3", "1.2.4"), "1.2.4");
        assert_eq!(max_version("2.0.0", "1.9.9"), "2.0.0");
        assert_eq!(max_version("1.2.3", "1.2.3"), "1.2.3");
    }

    #[test]
    fn test_execute_verify() {
        let dir = setup_test_env();
        let args: Vec<String> = vec!["yolo".into(), "bump-version".into(), "--verify".into()];
        let (output, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
        let j: Value = serde_json::from_str(&output).unwrap();
        assert_eq!(j["delta"]["all_match"], true);
    }

    #[test]
    fn test_execute_bump_offline() {
        let dir = setup_test_env();
        let args: Vec<String> = vec!["yolo".into(), "bump-version".into(), "--offline".into()];
        let (output, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
        let j: Value = serde_json::from_str(&output).unwrap();
        assert_eq!(j["delta"]["new_version"], "1.2.4");
        let changed = j["changed"].as_array().unwrap();
        assert!(changed.iter().any(|c| c == "VERSION"));
    }

    #[test]
    fn test_missing_version_file() {
        let dir = TempDir::new().unwrap();
        let result = read_version_file(dir.path());
        assert!(result.is_err());
    }

    #[test]
    fn test_write_json_version() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("test.json");
        fs::write(&path, r#"{"version": "1.0.0"}"#).unwrap();

        write_json_version(&path, "/version", "2.0.0").unwrap();

        let content: Value = serde_json::from_str(&fs::read_to_string(&path).unwrap()).unwrap();
        assert_eq!(content["version"], "2.0.0");
    }

    #[test]
    fn test_write_json_version_nested() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("test.json");
        fs::write(&path, r#"{"plugins": [{"version": "1.0.0"}]}"#).unwrap();

        write_json_version(&path, "/plugins/0/version", "3.0.0").unwrap();

        let content: Value = serde_json::from_str(&fs::read_to_string(&path).unwrap()).unwrap();
        assert_eq!(content["plugins"][0]["version"], "3.0.0");
    }

    #[test]
    fn test_increment_major() {
        assert_eq!(increment_major("1.2.3"), "2.0.0");
        assert_eq!(increment_major("0.9.9"), "1.0.0");
    }

    #[test]
    fn test_increment_minor() {
        assert_eq!(increment_minor("1.2.3"), "1.3.0");
        assert_eq!(increment_minor("0.0.1"), "0.1.0");
    }

    #[test]
    fn test_bump_major_flag() {
        let dir = setup_test_env();
        let (output, code) =
            bump_version(dir.path(), true, true, false, Instant::now()).unwrap();
        assert_eq!(code, 0);
        let j: Value = serde_json::from_str(&output).unwrap();
        assert_eq!(j["delta"]["new_version"], "2.0.0");
        assert_eq!(j["delta"]["bump_type"], "major");
    }

    #[test]
    fn test_bump_minor_flag() {
        let dir = setup_test_env();
        let (output, code) =
            bump_version(dir.path(), true, false, true, Instant::now()).unwrap();
        assert_eq!(code, 0);
        let j: Value = serde_json::from_str(&output).unwrap();
        assert_eq!(j["delta"]["new_version"], "1.3.0");
        assert_eq!(j["delta"]["bump_type"], "minor");
    }

    #[test]
    fn test_toml_read_write() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("Cargo.toml");
        fs::write(
            &path,
            "[package]\nname = \"test\"\nversion = \"1.0.0\"\n",
        )
        .unwrap();
        assert_eq!(read_toml_version(&path).unwrap(), "1.0.0");
        write_toml_version(&path, "2.0.0").unwrap();
        assert_eq!(read_toml_version(&path).unwrap(), "2.0.0");
        // Verify formatting preserved
        let content = fs::read_to_string(&path).unwrap();
        assert!(content.contains("name = \"test\""));
    }

    #[test]
    fn test_major_minor_conflict() {
        let dir = setup_test_env();
        let args: Vec<String> = vec![
            "yolo".into(),
            "bump-version".into(),
            "--major".into(),
            "--minor".into(),
        ];
        let result = execute(&args, dir.path());
        assert!(result.is_err());
    }
}
