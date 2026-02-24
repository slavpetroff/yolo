use serde_json::{json, Value};
use std::fs;
use std::path::Path;
use std::time::Instant;

use crate::commands::{bootstrap_project, bootstrap_requirements, bootstrap_roadmap, bootstrap_state};

fn s(v: &str) -> String {
    v.to_string()
}

/// Facade command that runs all 4 bootstrap sub-commands sequentially.
///
/// Usage: yolo bootstrap-all <output_dir> <name> <description> <phases_json> <discovery_json>
///        [--core-value V] [--research R] [--milestone M]
///
/// Runs:
/// 1. bootstrap-project  — creates PROJECT.md
/// 2. bootstrap-requirements — creates REQUIREMENTS.md
/// 3. bootstrap-roadmap  — creates ROADMAP.md + phase dirs
/// 4. bootstrap-state    — creates STATE.md
///
/// Exit codes: 0=all pass, 1=any fail
pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    let start = Instant::now();

    // Positional args (skip args[0]="yolo", args[1]="bootstrap-all"):
    // args[2]=output_dir, args[3]=name, args[4]=description,
    // args[5]=phases_json, args[6]=discovery_json
    let positional: Vec<&String> = args.iter().filter(|a| !a.starts_with("--")).collect();

    if positional.len() < 7 {
        return Err(
            "Usage: yolo bootstrap-all <output_dir> <name> <description> <phases_json> <discovery_json> [--core-value V] [--research R] [--milestone M]"
                .to_string(),
        );
    }

    let output_dir = &positional[2];
    let name = &positional[3];
    let description = &positional[4];
    let phases_json = &positional[5];
    let discovery_json = &positional[6];

    // Parse optional flags
    let mut core_value: Option<String> = None;
    let mut research: Option<String> = None;
    let mut milestone: Option<String> = None;

    let mut i = 2;
    while i < args.len() {
        match args[i].as_str() {
            "--core-value" if i + 1 < args.len() => {
                core_value = Some(args[i + 1].clone());
                i += 2;
            }
            "--research" if i + 1 < args.len() => {
                research = Some(args[i + 1].clone());
                i += 2;
            }
            "--milestone" if i + 1 < args.len() => {
                milestone = Some(args[i + 1].clone());
                i += 2;
            }
            _ => {
                i += 1;
            }
        }
    }

    let milestone_name = milestone.unwrap_or_else(|| name.to_string());

    // Derive output paths
    let output_path = Path::new(output_dir.as_str());
    let project_path = output_path.join("PROJECT.md");
    let requirements_path = output_path.join("REQUIREMENTS.md");
    let roadmap_path = output_path.join("ROADMAP.md");
    let state_path = output_path.join("STATE.md");

    let project_str = project_path.to_string_lossy().to_string();
    let requirements_str = requirements_path.to_string_lossy().to_string();
    let roadmap_str = roadmap_path.to_string_lossy().to_string();
    let state_str = state_path.to_string_lossy().to_string();

    let mut steps = serde_json::Map::new();
    let mut all_ok = true;

    // --- Step 1: bootstrap-project ---
    let mut project_args = vec![s("project"), project_str.clone(), name.to_string(), description.to_string()];
    if let Some(ref cv) = core_value {
        project_args.push(cv.clone());
    }
    match bootstrap_project::execute(&project_args, cwd) {
        Ok((json_str, code)) => {
            let parsed: Value = serde_json::from_str(&json_str).unwrap_or(json!({"raw": json_str.trim()}));
            if code != 0 {
                all_ok = false;
            }
            steps.insert("project".to_string(), parsed.get("delta").cloned().unwrap_or(parsed));
        }
        Err(e) => {
            steps.insert("project".to_string(), json!({"error": e}));
            return Ok((build_response(false, name, output_dir, &steps, 0, start).to_string(), 1));
        }
    }

    // --- Step 2: bootstrap-requirements ---
    let mut requirements_args = vec![s("requirements"), requirements_str.clone(), discovery_json.to_string()];
    if let Some(ref r) = research {
        requirements_args.push(r.clone());
    }
    match bootstrap_requirements::execute(&requirements_args, cwd) {
        Ok((json_str, code)) => {
            let parsed: Value = serde_json::from_str(&json_str).unwrap_or(json!({"raw": json_str.trim()}));
            if code != 0 {
                all_ok = false;
            }
            steps.insert("requirements".to_string(), parsed.get("delta").cloned().unwrap_or(parsed));
        }
        Err(e) => {
            steps.insert("requirements".to_string(), json!({"error": e}));
            return Ok((build_response(false, name, output_dir, &steps, 0, start).to_string(), 1));
        }
    }

    // --- Step 3: bootstrap-roadmap (need phase_count for state) ---
    let roadmap_args = vec![s("roadmap"), roadmap_str.clone(), name.to_string(), phases_json.to_string()];
    let phase_count: usize;
    match bootstrap_roadmap::execute(&roadmap_args, cwd) {
        Ok((json_str, code)) => {
            let parsed: Value = serde_json::from_str(&json_str).unwrap_or(json!({"raw": json_str.trim()}));
            phase_count = parsed
                .get("delta")
                .and_then(|d| d.get("phase_count"))
                .and_then(|v| v.as_u64())
                .unwrap_or(0) as usize;
            if code != 0 {
                all_ok = false;
            }
            steps.insert("roadmap".to_string(), parsed.get("delta").cloned().unwrap_or(parsed));
        }
        Err(e) => {
            steps.insert("roadmap".to_string(), json!({"error": e}));
            return Ok((build_response(false, name, output_dir, &steps, 0, start).to_string(), 1));
        }
    }

    // --- Step 4: bootstrap-state ---
    let phase_count_str = phase_count.to_string();
    let state_args = vec![
        s("state"),
        state_str.clone(),
        name.to_string(),
        milestone_name.clone(),
        phase_count_str,
    ];
    match bootstrap_state::execute(&state_args, cwd) {
        Ok((json_str, code)) => {
            let parsed: Value = serde_json::from_str(&json_str).unwrap_or(json!({"raw": json_str.trim()}));
            if code != 0 {
                all_ok = false;
            }
            steps.insert("state".to_string(), parsed.get("delta").cloned().unwrap_or(parsed));
        }
        Err(e) => {
            all_ok = false;
            steps.insert("state".to_string(), json!({"error": e}));
        }
    }

    let response = build_response(all_ok, name, output_dir, &steps, phase_count, start);
    Ok((response.to_string(), if all_ok { 0 } else { 1 }))
}

fn build_response(
    ok: bool,
    name: &str,
    output_dir: &str,
    steps: &serde_json::Map<String, Value>,
    phase_count: usize,
    start: Instant,
) -> Value {
    json!({
        "ok": ok,
        "cmd": "bootstrap-all",
        "delta": {
            "name": name,
            "output_dir": output_dir,
            "steps": Value::Object(steps.clone()),
            "files_created": ["PROJECT.md", "REQUIREMENTS.md", "ROADMAP.md", "STATE.md"],
            "phase_count": phase_count
        },
        "elapsed_ms": start.elapsed().as_millis() as u64
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    fn write_phases(dir: &Path, content: &str) -> String {
        let path = dir.join("phases.json");
        fs::write(&path, content).unwrap();
        path.to_string_lossy().to_string()
    }

    fn write_discovery(dir: &Path, content: &str) -> String {
        let path = dir.join("discovery.json");
        fs::write(&path, content).unwrap();
        path.to_string_lossy().to_string()
    }

    #[test]
    fn test_bootstrap_all_success() {
        let dir = tempdir().unwrap();
        let output_dir = dir.path().join("output");
        fs::create_dir_all(&output_dir).unwrap();

        let phases = write_phases(dir.path(), r#"[
            {"name": "Foundation", "goal": "Build base", "requirements": ["REQ-01"], "success_criteria": ["Compiles"]},
            {"name": "Features", "goal": "Add features", "requirements": [], "success_criteria": ["Tests pass"]}
        ]"#);

        let discovery = write_discovery(dir.path(), r#"{
            "answered": [],
            "inferred": [{"text": "Auth system", "priority": "Must-have"}]
        }"#);

        let (out, code) = execute(
            &[
                s("yolo"),
                s("bootstrap-all"),
                output_dir.to_string_lossy().to_string(),
                s("TestApp"),
                s("A test application"),
                phases,
                discovery,
            ],
            dir.path(),
        )
        .unwrap();

        assert_eq!(code, 0);
        let parsed: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(parsed["ok"], true);
        assert_eq!(parsed["cmd"], "bootstrap-all");
        assert_eq!(parsed["delta"]["name"], "TestApp");
        assert_eq!(parsed["delta"]["phase_count"], 2);
        assert!(parsed["elapsed_ms"].is_number());

        // Verify all files created
        assert!(output_dir.join("PROJECT.md").exists());
        assert!(output_dir.join("REQUIREMENTS.md").exists());
        assert!(output_dir.join("ROADMAP.md").exists());
        assert!(output_dir.join("STATE.md").exists());

        // Verify steps present
        let steps = parsed["delta"]["steps"].as_object().unwrap();
        assert!(steps.contains_key("project"));
        assert!(steps.contains_key("requirements"));
        assert!(steps.contains_key("roadmap"));
        assert!(steps.contains_key("state"));

        // Verify files_created array
        let files = parsed["delta"]["files_created"].as_array().unwrap();
        assert_eq!(files.len(), 4);
    }

    #[test]
    fn test_missing_args() {
        let dir = tempdir().unwrap();
        let result = execute(
            &[s("yolo"), s("bootstrap-all"), s("outdir"), s("name")],
            dir.path(),
        );
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Usage:"));
    }

    #[test]
    fn test_invalid_phases_json() {
        let dir = tempdir().unwrap();
        let output_dir = dir.path().join("output");
        fs::create_dir_all(&output_dir).unwrap();

        let bad_phases = dir.path().join("phases.json");
        fs::write(&bad_phases, "not valid json").unwrap();

        let discovery = write_discovery(dir.path(), r#"{"answered": [], "inferred": []}"#);

        let (out, code) = execute(
            &[
                s("yolo"),
                s("bootstrap-all"),
                output_dir.to_string_lossy().to_string(),
                s("TestApp"),
                s("A test app"),
                bad_phases.to_string_lossy().to_string(),
                discovery,
            ],
            dir.path(),
        )
        .unwrap();

        assert_eq!(code, 1);
        let parsed: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(parsed["ok"], false);
        assert!(parsed["delta"]["steps"]["roadmap"]["error"]
            .as_str()
            .unwrap()
            .contains("Invalid JSON"));
    }

    #[test]
    fn test_response_has_cmd_and_elapsed() {
        let dir = tempdir().unwrap();
        let output_dir = dir.path().join("output");
        fs::create_dir_all(&output_dir).unwrap();

        let phases = write_phases(
            dir.path(),
            r#"[{"name": "Init", "goal": "Setup", "requirements": [], "success_criteria": []}]"#,
        );
        let discovery = write_discovery(dir.path(), r#"{"answered": [], "inferred": []}"#);

        let (out, _) = execute(
            &[
                s("yolo"),
                s("bootstrap-all"),
                output_dir.to_string_lossy().to_string(),
                s("App"),
                s("Desc"),
                phases,
                discovery,
            ],
            dir.path(),
        )
        .unwrap();

        let parsed: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(parsed["cmd"], "bootstrap-all");
        assert!(parsed["elapsed_ms"].is_number());
    }

    #[test]
    fn test_milestone_flag() {
        let dir = tempdir().unwrap();
        let output_dir = dir.path().join("output");
        fs::create_dir_all(&output_dir).unwrap();

        let phases = write_phases(
            dir.path(),
            r#"[{"name": "Core", "goal": "Build core", "requirements": [], "success_criteria": []}]"#,
        );
        let discovery = write_discovery(dir.path(), r#"{"answered": [], "inferred": []}"#);

        let (out, code) = execute(
            &[
                s("yolo"),
                s("bootstrap-all"),
                output_dir.to_string_lossy().to_string(),
                s("MyApp"),
                s("Description"),
                phases,
                discovery,
                s("--milestone"),
                s("Custom Milestone v2"),
            ],
            dir.path(),
        )
        .unwrap();

        assert_eq!(code, 0);
        let parsed: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(parsed["ok"], true);

        // Verify the state file contains the custom milestone
        let state_content = fs::read_to_string(output_dir.join("STATE.md")).unwrap();
        assert!(state_content.contains("Custom Milestone v2"));
        assert!(parsed["delta"]["steps"]["state"]["milestone_name"] == "Custom Milestone v2");
    }

    #[test]
    fn test_core_value_flag() {
        let dir = tempdir().unwrap();
        let output_dir = dir.path().join("output");
        fs::create_dir_all(&output_dir).unwrap();

        let phases = write_phases(
            dir.path(),
            r#"[{"name": "Init", "goal": "Setup", "requirements": [], "success_criteria": []}]"#,
        );
        let discovery = write_discovery(dir.path(), r#"{"answered": [], "inferred": []}"#);

        let (out, code) = execute(
            &[
                s("yolo"),
                s("bootstrap-all"),
                output_dir.to_string_lossy().to_string(),
                s("MyApp"),
                s("A great app"),
                phases,
                discovery,
                s("--core-value"),
                s("Simplicity above all"),
            ],
            dir.path(),
        )
        .unwrap();

        assert_eq!(code, 0);
        let parsed: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(parsed["ok"], true);

        let project_content = fs::read_to_string(output_dir.join("PROJECT.md")).unwrap();
        assert!(project_content.contains("**Core value:** Simplicity above all"));
    }
}
